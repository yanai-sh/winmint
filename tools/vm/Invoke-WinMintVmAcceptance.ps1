#Requires -Version 7.6
<#
.SYNOPSIS
    Run the full WinMint Hyper-V VM acceptance pass and emit a single pass/fail
    verdict plus an evidence folder.

.DESCRIPTION
    The acceptance gate from roadmap Track D: prove a build goes end to end (build
    the ISO -> unattended install -> FirstLogon completes) and leave reusable
    evidence behind. It sequences the existing single-purpose scripts and adds the
    missing tail (wait for FirstLogon, score it, collect evidence):

      1. Build + boot   -> Build-And-TestVm.ps1 -NoConnect (skip with -SkipBuild
                           to attach to an already-running VM).
      2. Wait           -> poll the guest %LOCALAPPDATA%\WinMint\state.json over
                           PowerShell Direct until the FirstLogon agent reaches a
                           terminal run.status ('ok'/'failed'). The first reachable
                           call also means install + autologon are done.
      3. Inspect        -> Invoke-WinMintGuestAcceptance.ps1 (best-effort signals).
      4. Evidence       -> pull guest logs + state, copy the host build artifacts,
                           write acceptance-result.json, print the verdict.

    All output goes to BOTH the terminal and output\vm-acceptance\<vm>-<stamp>\run.log
    (the noisy build is teed; orchestrator lines via Say), so a run is always
    watchable live and fully captured, foreground or detached.

    Requires an elevated PowerShell (WIM servicing + Hyper-V PowerShell Direct).
    The profile must be a Hyper-V-valid Local-account profile (Windows 11 Pro,
    explicit password) so the install is unattended and PowerShell Direct can sign
    in.

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\Invoke-WinMintVmAcceptance.ps1 -ProfilePath .\tests\profiles\hyper-v-install-arm64.json

.EXAMPLE
    # VM already installed; attach, wait/score, collect evidence without rebuilding.
    pwsh -NoProfile -File .\tools\vm\Invoke-WinMintVmAcceptance.ps1 -ProfilePath .\tests\profiles\hyper-v-install-arm64.json -SkipBuild
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProfilePath,
    [string]$VMName = 'WinMint-ARM-Test',
    [int]$MemoryGB = 6,
    [int]$DiskGB = 100,
    [int]$CpuCount = 4,
    [string]$SwitchName,
    [switch]$SkipBuild,
    [switch]$ForceBuild,
    [switch]$FullImage,
    [int]$TimeoutMinutes = 60,
    [string]$EvidenceRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw 'Run this in an elevated PowerShell - building (WIM servicing) and Hyper-V PowerShell Direct both require Administrator.'
}
if (-not (Get-Command New-VM -ErrorAction SilentlyContinue)) {
    throw 'Hyper-V PowerShell module not found. Enable it: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All'
}

# Resolve the profile and the local-account credentials the install will create.
$resolvedProfile = if ([IO.Path]::IsPathRooted($ProfilePath)) { $ProfilePath } else { Join-Path $repoRoot $ProfilePath }
if (-not (Test-Path -LiteralPath $resolvedProfile)) { throw "Build profile not found: $resolvedProfile" }
$profileJson = Get-Content -LiteralPath $resolvedProfile -Raw | ConvertFrom-Json
if (-not $profileJson.identity -or [string]$profileJson.identity.accountMode -ne 'Local') {
    throw 'VM acceptance requires a Local-account profile so the install is unattended and PowerShell Direct can sign in.'
}
$guestUser = [string]$profileJson.identity.accountName
$guestPassword = [string]$profileJson.identity.password
if ([string]::IsNullOrWhiteSpace($guestUser) -or [string]::IsNullOrWhiteSpace($guestPassword)) {
    throw 'The profile must set identity.accountName and identity.password for unattended VM acceptance.'
}
$cred = [pscredential]::new($guestUser, (ConvertTo-SecureString $guestPassword -AsPlainText -Force))
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source

$startedAt = Get-Date
$result = [ordered]@{
    vmName = $VMName; profile = $resolvedProfile; startedAt = $startedAt.ToString('o')
    reachable = $false; firstLogon = $null; inspect = $null; verdict = 'unknown'; reasons = @()
}

# Create the evidence dir up front and tee everything into run.log so the run is
# always watchable live (terminal) and fully captured (file), foreground or
# detached. Start-Transcript is not used: it misses child-process (build) output.
if (-not $EvidenceRoot) { $EvidenceRoot = Join-Path $repoRoot 'output\vm-acceptance' }
$evidenceDir = Join-Path $EvidenceRoot ("$VMName-" + $startedAt.ToString('yyyyMMdd-HHmmss'))
$null = New-Item -ItemType Directory -Path $evidenceDir -Force
$result.evidenceDir = $evidenceDir
$runLog = Join-Path $evidenceDir 'run.log'
function Say {
    param([string]$Message, [string]$Color)
    if ($Color) { Write-Host $Message -ForegroundColor $Color } else { Write-Host $Message }
    Add-Content -LiteralPath $runLog -Value $Message
}
Say "Run log: $runLog  (watch live: Get-Content '$runLog' -Wait -Tail 20)"

# --- 1. Build + boot ------------------------------------------------------------
if (-not $SkipBuild) {
    Say "`n=== Build ===" 'Cyan'
    $buildArgs = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'Build-And-TestVm.ps1'),
        '-ProfilePath', $resolvedProfile, '-VMName', $VMName,
        '-MemoryGB', $MemoryGB, '-DiskGB', $DiskGB, '-CpuCount', $CpuCount, '-NoConnect')
    if ($SwitchName) { $buildArgs += @('-SwitchName', $SwitchName) }
    if ($ForceBuild) { $buildArgs += '-ForceBuild' }
    if ($FullImage) { $buildArgs += '-FullImage' }
    # Tee the delegated build to terminal + run.log; $LASTEXITCODE stays the child's.
    & $pwsh @buildArgs 2>&1 | Tee-Object -FilePath $runLog -Append
    if ($LASTEXITCODE -ne 0) { throw "Build/boot phase failed with exit code $LASTEXITCODE." }
}
else {
    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if (-not $vm) { throw "VM '$VMName' not found; drop -SkipBuild to build it first." }
    if ($vm.State -ne 'Running') { throw "VM '$VMName' is not running (state: $($vm.State))." }
}

# --- 2. Wait for FirstLogon ----------------------------------------------------
# One loop: a successful PowerShell Direct call means install + autologon are done
# (that sets reachable); then we read state.json until run.status is terminal.
Say "`n=== Wait for FirstLogon ===" 'Cyan'
$deadline = $startedAt.AddMinutes($TimeoutMinutes)
$finalState = $null
while ((Get-Date) -lt $deadline) {
    try {
        $stateText = Invoke-Command -VMName $VMName -Credential $cred -ErrorAction Stop -ScriptBlock {
            $p = Join-Path $env:LOCALAPPDATA 'WinMint\state.json'
            if (Test-Path -LiteralPath $p) { Get-Content -LiteralPath $p -Raw } else { '' }
        }
        $result.reachable = $true
        if (-not [string]::IsNullOrWhiteSpace($stateText)) {
            $stateObj = $stateText | ConvertFrom-Json
            $runStatus = [string]$stateObj.run.status
            if ($runStatus -in @('ok', 'failed')) { $finalState = $stateObj; break }
            Say "  ...FirstLogon in progress (run.status = '$runStatus')."
        }
    }
    catch { }  # guest not reachable yet
    Start-Sleep -Seconds 20
}
if (-not $result.reachable) { throw "Guest '$VMName' was not reachable over PowerShell Direct within $TimeoutMinutes min (install/autologon did not complete)." }
if (-not $finalState) { throw "FirstLogon did not reach a terminal run.status within $TimeoutMinutes min." }

$result.firstLogon = [ordered]@{
    status = [string]$finalState.run.status; exitCode = $finalState.run.exitCode
    completedAt = [string]$finalState.run.completedAt
    failedSteps = @($finalState.run.failedSteps); warningSteps = @($finalState.run.warningSteps)
    rebootPending = [bool]$finalState.run.rebootPending
}
if ($result.firstLogon.status -eq 'ok') {
    Say "FirstLogon completed (exitCode $($result.firstLogon.exitCode))." 'Green'
}
else {
    $result.reasons += "FirstLogon failed: $($result.firstLogon.failedSteps -join ', ')."
    Say "FirstLogon failed: $($result.firstLogon.failedSteps -join ', ')." 'Red'
}

# --- 3. Inspect live desktop signals -------------------------------------------
# These are correctness signals, not best-effort: if we cannot gather them we cannot
# prove the desktop is right, so an inspect failure fails the verdict (no silent pass).
Say "`n=== Inspect ===" 'Cyan'
$inspectOk = $false
try {
    $inspectJson = & $pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Invoke-WinMintGuestAcceptance.ps1') -VMName $VMName -GuestUser $guestUser -GuestPassword $guestPassword
    if ($LASTEXITCODE -ne 0) { throw "inspector exited $LASTEXITCODE" }
    $result.inspect = ($inspectJson -join "`n") | ConvertFrom-Json
    Add-Content -LiteralPath $runLog -Value ($inspectJson -join "`n")
    $inspectOk = $true
}
catch {
    $result.reasons += "Inspect could not gather guest signals: $($_.Exception.Message)"
    Say "Inspect failed: $($_.Exception.Message)" 'Red'
}

# --- 4. Evidence + verdict -----------------------------------------------------
Say "`n=== Evidence ===" 'Cyan'
try {
    $session = New-PSSession -VMName $VMName -Credential $cred -ErrorAction Stop
    try {
        Invoke-Command -Session $session -ScriptBlock {
            $dst = 'C:\Windows\Temp\winmint-acceptance-pull'
            Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue
            $null = New-Item -ItemType Directory -Path $dst -Force
            Copy-Item -LiteralPath 'C:\ProgramData\WinMint\Logs' -Destination (Join-Path $dst 'ProgramData-Logs') -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath "$env:LOCALAPPDATA\WinMint") {
                Copy-Item -LiteralPath "$env:LOCALAPPDATA\WinMint" -Destination (Join-Path $dst 'LocalAppData-WinMint') -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        Copy-Item -FromSession $session -Path 'C:\Windows\Temp\winmint-acceptance-pull\*' -Destination $evidenceDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    finally { Remove-PSSession $session -ErrorAction SilentlyContinue }
}
catch {
    $result.reasons += "Could not pull guest logs: $($_.Exception.Message)"
    Say "Guest log pull failed (non-fatal): $($_.Exception.Message)" 'Yellow'
}

# Copy the host build artifacts from the newest build that has a manifest.
$manifest = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'output') -Filter 'BuildManifest.json' -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($manifest) {
    $hostDir = Join-Path $evidenceDir 'host-build'
    $null = New-Item -ItemType Directory -Path $hostDir -Force
    foreach ($name in @('BuildManifest.json', 'BuildDelta.json', 'BuildProfile.json')) {
        $src = Join-Path $manifest.Directory.FullName $name
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $hostDir -Force }
    }
}

# A test PASS requires EVERY step to succeed - no silent failures. The agent marks
# live-user installs 'advisory' so a failure does not brick a real user's desktop
# (run.status stays 'ok' with the failures listed in warningSteps). That leniency is
# correct in production but wrong for acceptance: here an advisory failure is still a
# failure and must fail the verdict, not pass with a buried warning line.
# Filter nulls: @($null).Count is 1, and a failed run carries no warningSteps property.
$warnSteps = @($result.firstLogon.warningSteps | Where-Object { $_ })
$warned = $warnSteps.Count -gt 0
if ($warned) { $result.reasons += "Advisory step(s) failed (strict test verdict): $($warnSteps -join ', ')." }

# Desktop signal assertions (derived from the profile). The agent can report run.status
# 'ok' yet leave the desktop wrong - missing account picture, etc.
# Those gathered signals were diagnostic only; assert them so they cannot pass silently.
$signalFail = [System.Collections.Generic.List[string]]::new()
if (-not $inspectOk) {
    $signalFail.Add('guest inspection failed; desktop signals unverified') | Out-Null
}
else {
    $insp = $result.inspect
    $wslDistros = @($profileJson.development.wsl.distros)
    if ($wslDistros -contains 'Ubuntu') {
        if (-not $insp.UbuntuProfileExists) { $signalFail.Add('Windows Terminal Ubuntu profile missing') | Out-Null }
    }
    if ($wslDistros -contains 'NixOS-WSL') {
        if (-not $insp.NixProfileExists) { $signalFail.Add('Windows Terminal NixOS profile missing') | Out-Null }
    }
    if (-not $insp.AccountPictureBmpExists) { $signalFail.Add('Account picture bitmap missing') | Out-Null }
}
foreach ($s in $signalFail) { $result.reasons += "Signal check failed: $s." }
$result.signalChecks = [ordered]@{ ok = ($signalFail.Count -eq 0); failures = @($signalFail) }

$passed = $result.reachable -and $result.firstLogon -and $result.firstLogon.status -eq 'ok' -and -not $warned -and ($signalFail.Count -eq 0)
$result.verdict = if ($passed) { 'pass' } else { 'fail' }
$result.finishedAt = (Get-Date).ToString('o')
($result | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $evidenceDir 'acceptance-result.json') -Encoding UTF8

Say "`n=== Acceptance verdict: $($result.verdict.ToUpper()) ===" ($passed ? 'Green' : 'Red')
foreach ($r in $result.reasons) { Say "  - $r" }
Say "Evidence: $evidenceDir"
if (-not $passed) { exit 1 }
