# Runs as SYSTEM via SetupComplete.cmd after Windows is installed, before first interactive logon.
# One-shot — Windows runs this exactly once during the very first boot of the installed image.
# Cleanup of C:\Windows\Panther\unattend*.xml is the priority security task here: the answer
# file embeds the user's local-admin password in base64 in the AutoLogon block and must be
# wiped before any interactive user can read it. That wipe is kept INLINE in this orchestrator
# (not a dot-sourced module) so it still runs even if a per-concern module fails to load.
#
# Per-concern work lives in SetupComplete\*.ps1, dot-sourced below. Those modules define
# Invoke-Sc* functions that read this orchestrator's script-scope variables and helpers.
#Requires -Version 5.1
$ErrorActionPreference = 'Continue'
# Logs go to ProgramData (Administrators-readable). C:\Windows\Setup\Scripts is the staged
# payload directory and is readable by Users by default — transcripts can capture command
# lines and shouldn't land there.
$logDir = Join-Path $env:ProgramData 'WinMint\Logs'
$null = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue
$payloadDir = 'C:\Windows\Setup\Scripts'
. (Join-Path $payloadDir 'Setup.Actions.ps1')

function Set-ScPowerShellConsoleEncoding {
    try {
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [Console]::InputEncoding = $utf8
        [Console]::OutputEncoding = $utf8
        $global:OutputEncoding = $utf8
        $global:PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
        $global:PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
        $global:PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
    }
    catch { }
    try {
        $chcpExe = Join-Path $env:SystemRoot 'System32\chcp.com'
        $null = & $chcpExe 65001 2>$null
    }
    catch { }
}

Set-ScPowerShellConsoleEncoding

$transcriptPath = Join-Path $logDir 'SetupComplete_transcript.log'
try { Stop-Transcript -ErrorAction SilentlyContinue } catch { }
Start-Transcript -Path $transcriptPath -Force -ErrorAction SilentlyContinue | Out-Null

function Write-ScLog {
    param([string]$Message)
    "$(Get-Date -Format 'o') $Message" | Out-File (Join-Path $logDir 'SetupComplete.log') -Append
}

function Test-ScInternet443 {
    try {
        $connectivityHost = 'www.microsoft.com'
        return [bool](Test-NetConnection -ComputerName $connectivityHost -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction Stop)
    }
    catch {
        return $false
    }
}

function Get-ScProcessorArchitecture {
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch -Regex ([string]$arch) {
        '^ARM64$' { return 'arm64' }
        '^(AMD64|IA64)$' { return 'amd64' }
        '^x86$' { return 'x86' }
        default { return ([string]$arch).ToLowerInvariant() }
    }
}

function ConvertTo-ScWingetArchitecture {
    param([Parameter(Mandatory)][string]$Architecture)
    switch ($Architecture) {
        'amd64' { return 'x64' }
        'arm64' { return 'arm64' }
        'x86' { return 'x86' }
        default { return $null }
    }
}

function New-ScWingetInstallArgs {
    param([Parameter(Mandatory)][string]$Id)

    $wingetArgs = @(
        'install', '--exact', '--id', $Id, '--source', 'winget', '--silent',
        '--accept-source-agreements', '--accept-package-agreements'
    )
    $wingetArchitecture = ConvertTo-ScWingetArchitecture -Architecture (Get-ScProcessorArchitecture)
    if ($wingetArchitecture) {
        $wingetArgs += @('--architecture', $wingetArchitecture)
    }
    return $wingetArgs
}

$setupProfilePath = Join-Path $payloadDir 'WinMintSetupProfile.json'
$setupProfile = $null
try {
    if (Test-Path -LiteralPath $setupProfilePath) {
        $setupProfile = Get-Content -LiteralPath $setupProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
}
catch {
    "SetupComplete profile read failed: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
}

function Get-ScSetupProfileBool {
    param(
        [string]$Section,
        [string]$Name,
        [bool]$Default
    )
    if (-not $setupProfile) { return $Default }
    $sectionProp = $setupProfile.PSObject.Properties[$Section]
    if (-not $sectionProp) { return $Default }
    $valueProp = $sectionProp.Value.PSObject.Properties[$Name]
    if (-not $valueProp) { return $Default }
    return [bool]$valueProp.Value
}

function Get-ScSetupProfileValue {
    param(
        [string]$Section,
        [string]$Name,
        $Default = $null
    )
    if (-not $setupProfile) { return $Default }
    $sectionProp = $setupProfile.PSObject.Properties[$Section]
    if (-not $sectionProp) { return $Default }
    $valueProp = $sectionProp.Value.PSObject.Properties[$Name]
    if (-not $valueProp) { return $Default }
    return $valueProp.Value
}

function ConvertTo-ScStringArray {
    param($Value)
    @(
        @($Value) |
            ForEach-Object { ([string]$_) -split ',' } |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )
}

$preserveWindowsUpdate = Get-ScSetupProfileBool -Section 'setupComplete' -Name 'preserveWindowsUpdate' -Default $true
$removeRecall = Get-ScSetupProfileBool -Section 'setupComplete' -Name 'removeRecall' -Default $true
$aiPolicy = [string](Get-ScSetupProfileValue -Section 'aiRemoval' -Name 'policy' -Default 'ServiceableFull')
$aiRemoveRecall = [bool](Get-ScSetupProfileValue -Section 'aiRemoval' -Name 'removeRecall' -Default $removeRecall)
$aiDisableServices = [bool](Get-ScSetupProfileValue -Section 'aiRemoval' -Name 'disableAiServices' -Default $false)
$aiDisableTasks = [bool](Get-ScSetupProfileValue -Section 'aiRemoval' -Name 'disableAiTasks' -Default $false)
$aiServicesToDisable = @(ConvertTo-ScStringArray (Get-ScSetupProfileValue -Section 'aiRemoval' -Name 'servicesToDisable' -Default @('WSAIFabricSvc')))
$aiTaskPatternsToDisable = @(ConvertTo-ScStringArray (Get-ScSetupProfileValue -Section 'aiRemoval' -Name 'scheduledTaskPatternsToDisable' -Default @('Recall', 'WindowsAI', 'Copilot')))
$disableTelemetryTasks = [bool](Get-ScSetupProfileValue -Section 'privacy' -Name 'disableTelemetryTasks' -Default $false)
$telemetryTaskPatternsToDisable = @(ConvertTo-ScStringArray (Get-ScSetupProfileValue -Section 'privacy' -Name 'telemetryTaskPatternsToDisable' -Default @()))
$powerFormFactor = [string](Get-ScSetupProfileValue -Section 'power' -Name 'formFactor' -Default 'Auto')
$powerDisableHibernationOnDesktop = [bool](Get-ScSetupProfileValue -Section 'power' -Name 'disableHibernationOnDesktop' -Default $true)
$powerPlan = [string](Get-ScSetupProfileValue -Section 'power' -Name 'selectedPlan' -Default (Get-ScSetupProfileValue -Section 'power' -Name 'desktopPowerPlan' -Default 'Balanced'))
$powerDesktopPlan = $powerPlan
$edgeRemove = Get-ScSetupProfileBool -Section 'edge' -Name 'removeEdge' -Default $false
$edgeKeep = Get-ScSetupProfileBool -Section 'edge' -Name 'keepEdge' -Default $false
$edgeDmaEnabled = Get-ScSetupProfileBool -Section 'edge' -Name 'dmaInteropEnabled' -Default $false
$null = @(
    $preserveWindowsUpdate,
    $aiPolicy,
    $aiRemoveRecall,
    $aiDisableServices,
    $aiDisableTasks,
    $aiServicesToDisable,
    $aiTaskPatternsToDisable,
    $disableTelemetryTasks,
    $telemetryTaskPatternsToDisable,
    $powerFormFactor,
    $powerDisableHibernationOnDesktop,
    $powerDesktopPlan,
    $edgeRemove,
    $edgeKeep,
    $edgeDmaEnabled
)

try {
    Import-WinMintSetupActionModules -PayloadRoot $payloadDir
}
catch {
    "SetupComplete action module load failed: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
}

Write-ScLog 'SetupComplete.ps1 start'

try {
    $firstLogonPath = Join-Path $payloadDir 'FirstLogon.ps1'
    if (Test-Path -LiteralPath $firstLogonPath) {
        $pwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
        if (-not (Test-Path -LiteralPath $pwsh -PathType Leaf)) {
            throw "PowerShell 7 is required for FirstLogon but was not found: $pwsh"
        }
        $runOnceCommand = "`"$pwsh`" -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$firstLogonPath`""
        $null = & reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' /v 'WinMintFirstLogon' /t REG_SZ /d $runOnceCommand /f
        Write-ScLog 'Registered HKLM RunOnce fallback for FirstLogon.ps1 under PowerShell 7.'
    }
}
catch {
    "SetupComplete FirstLogon RunOnce registration failed: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
}

$errors = @()
foreach ($action in @(
        Get-WinMintSetupActionCatalog |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.FunctionName) }
    )) {
    try {
        & ([string]$action.FunctionName)
    }
    catch {
        $inv = $_.InvocationInfo
        $where = if ($inv) { " [$([IO.Path]::GetFileName([string]$inv.ScriptName)):$($inv.ScriptLineNumber)]" } else { '' }
        $errors += "SetupComplete action '$([string]$action.Id)': $($_.Exception.Message)$where"
    }
}
try {
    # Wildcard sweep — Setup keeps multiple phase copies of the answer file
    # under Panther (unattend.xml, unattend-original.xml, sometimes per-pass
    # copies). All of them embed the base64 password and must go. Kept inline
    # so this security step never depends on a module loading successfully.
    Remove-Item -Path @(
        'C:\Windows\Panther\unattend*.xml'
        'C:\Windows\Panther\unattend\*.xml'
    ) -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath @(
        'C:\Windows\Setup\Scripts\Wifi.xml'
    ) -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    $errors += "SetupComplete inline cleanup: $($_.Exception.Message)"
}
if ($errors.Count -gt 0) {
    # Append — never -Force overwrite. Module-load failures are written earlier with
    # -Append; clobbering that file hid the real root cause behind action dispatch noise.
    ($errors -join "`n") | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
}

Write-ScLog 'SetupComplete.ps1 end'
try { Stop-Transcript -ErrorAction SilentlyContinue } catch { }
