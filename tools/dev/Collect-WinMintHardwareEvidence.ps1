#Requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$MachineId,

    [Parameter(Mandatory)]
    [string]$OutputDir,

    [string]$Notes = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'tools\acceptance\New-WinMintAcceptanceResult.ps1')
. (Join-Path $repoRoot 'tools\acceptance\Test-WinMintHardwareAcceptanceSignals.ps1')

$inventoryPath = Join-Path $repoRoot 'config\hardware-acceptance.json'
if (-not (Test-Path -LiteralPath $inventoryPath)) {
    throw "Hardware inventory not found: $inventoryPath"
}

$inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
$machine = @($inventory.machines | Where-Object { $_.id -eq $MachineId } | Select-Object -First 1)
if (-not $machine) {
    $known = @($inventory.machines.id) -join ', '
    throw "Unknown machine id '$MachineId'. Known: $known"
}

$startedAt = Get-Date
$evidenceDir = if ([IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $repoRoot $OutputDir }
$null = New-Item -ItemType Directory -Path $evidenceDir -Force

function Copy-IfExists {
    param(
        [string]$Source,
        [string]$Destination
    )
    if (-not (Test-Path -LiteralPath $Source)) { return $false }
    $parent = Split-Path -Parent $Destination
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    if (Test-Path -LiteralPath $Source -PathType Container) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
    }
    else {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
    return $true
}

$copied = [System.Collections.Generic.List[string]]::new()
$missing = [System.Collections.Generic.List[string]]::new()

$hostBuildDir = Join-Path $evidenceDir 'host-build'
$null = New-Item -ItemType Directory -Path $hostBuildDir -Force
$manifest = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'output') -Filter 'WinMint-BuildManifest.json' -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $manifest) {
    $manifest = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'output') -Filter 'BuildManifest.json' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
if ($manifest) {
    foreach ($pair in @(
            @{ Src = 'WinMint-BuildManifest.json'; Dst = 'BuildManifest.json' }
            @{ Src = 'WinMint-BuildDelta.json'; Dst = 'BuildDelta.json' }
            @{ Src = 'WinMint-BuildProfile.json'; Dst = 'BuildProfile.json' }
            @{ Src = 'BuildManifest.json'; Dst = 'BuildManifest.json' }
            @{ Src = 'BuildDelta.json'; Dst = 'BuildDelta.json' }
            @{ Src = 'BuildProfile.json'; Dst = 'BuildProfile.json' }
            @{ Src = 'WinMint-DriverInventory.json'; Dst = 'WinMint-DriverInventory.json' }
        )) {
        $src = Join-Path $manifest.Directory.FullName $pair.Src
        $dst = Join-Path $hostBuildDir $pair.Dst
        if (Copy-IfExists -Source $src -Destination $dst) { $copied.Add($pair.Dst) | Out-Null }
    }
}
else {
    $missing.Add('host build manifest (output\**\WinMint-BuildManifest.json)') | Out-Null
}

$guestRoot = Join-Path $evidenceDir 'guest'
$null = New-Item -ItemType Directory -Path $guestRoot -Force
$guestPaths = @(
    @{ Src = 'C:\Windows\Setup\Scripts\WinMintSetupProfile.json'; Dst = 'WinMintSetupProfile.json' }
    @{ Src = "$env:LOCALAPPDATA\WinMint\state.json"; Dst = 'state.json' }
    @{ Src = 'C:\ProgramData\WinMint\Logs\LiveInstallAudit.json'; Dst = 'LiveInstallAudit.json' }
)
foreach ($entry in $guestPaths) {
    $dst = Join-Path $guestRoot $entry.Dst
    if (Copy-IfExists -Source $entry.Src -Destination $dst) {
        $copied.Add($entry.Dst) | Out-Null
    }
    else {
        $missing.Add($entry.Src) | Out-Null
    }
}
$logsSrc = 'C:\ProgramData\WinMint\Logs'
$logsDst = Join-Path $guestRoot 'Logs'
if (Copy-IfExists -Source $logsSrc -Destination $logsDst) {
    $copied.Add('Logs') | Out-Null
}
else {
    $missing.Add($logsSrc) | Out-Null
}

$firstLogon = $null
$statePath = Join-Path $guestRoot 'state.json'
if (Test-Path -LiteralPath $statePath) {
    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $firstLogon = [ordered]@{
            status = if ($state.PSObject.Properties['status']) { [string]$state.status } else { [string]$state.run.status }
            warningSteps = @($state.warningSteps | Where-Object { $_ })
        }
    }
    catch {
        $firstLogon = [ordered]@{ status = 'unknown'; error = $_.Exception.Message }
    }
}

$liveInstallAudit = $null
$auditPath = Join-Path $guestRoot 'LiveInstallAudit.json'
if (Test-Path -LiteralPath $auditPath) {
    try {
        $audit = Get-Content -LiteralPath $auditPath -Raw | ConvertFrom-Json
        $errorCount = [int]$audit.summary.error
        $liveInstallAudit = [ordered]@{
            ok = ($errorCount -eq 0)
            path = $auditPath
            errorCount = $errorCount
            warningCount = [int]$audit.summary.warning
        }
    }
    catch {
        $liveInstallAudit = [ordered]@{ ok = $false; error = $_.Exception.Message }
    }
}

$signals = Test-WinMintHardwareAcceptanceSignals -EvidenceDir $evidenceDir -Machine $machine
$warnings = [System.Collections.Generic.List[string]]::new()
$reasons = [System.Collections.Generic.List[string]]::new()
foreach ($m in $missing) { $warnings.Add("Missing artifact: $m") | Out-Null }
foreach ($signal in $signals) {
    if ($signal.ok) { continue }
    $line = if ([string]$signal.message) { "$($signal.id): $($signal.message)" } else { $signal.id }
    if ($signal.severity -eq 'plumbing') { $reasons.Add($line) | Out-Null }
    else { $warnings.Add($line) | Out-Null }
}

$result = [ordered]@{
    acceptanceMode = 'hardware'
    machineId = $MachineId
    machineLabel = [string]$machine.label
    profile = [string]$machine.profile
    acceptanceTier = 'Hardware'
    phase = 'Evidence'
    startedAt = $startedAt.ToString('o')
    reachable = $true
    firstLogon = $firstLogon
    inspect = $null
    liveInstallAudit = $liveInstallAudit
    copiedArtifacts = @($copied)
    missingArtifacts = @($missing)
    checks = @($machine.checks)
    warnings = @($warnings)
    reasons = @($reasons)
    evidenceDir = $evidenceDir
}

$result = Complete-WinMintAcceptanceResult -Result $result -Signals $signals -AcceptanceTier Hardware
$resultPath = Join-Path $evidenceDir 'acceptance-result.json'
Write-WinMintAcceptanceResult -Result $result -Path $resultPath

$notesPath = Join-Path $evidenceDir 'notes.md'
if (-not (Test-Path -LiteralPath $notesPath)) {
    @(
        "# $($machine.label) — hardware evidence"
        ''
        "- machine id: ``$MachineId``"
        "- profile: ``$($machine.profile)``"
        "- collected: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        "- verdict: **$($result.verdict)**"
        ''
        '## Maintainer notes'
        ''
        if ($Notes) { $Notes } else { '_Add Wi-Fi, sleep/resume, Copilot key, display scaling, and any product issues._' }
        ''
    ) | Set-Content -LiteralPath $notesPath -Encoding UTF8
}

Write-Host "Hardware evidence: $evidenceDir"
Write-Host "Verdict: $($result.verdict) | Copied: $($copied.Count) | Missing: $($missing.Count) | Signals: $($signals.Count)"
if ($result.verdict -ne 'pass') { exit 1 }
