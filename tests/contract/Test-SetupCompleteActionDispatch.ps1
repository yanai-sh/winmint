#Requires -Version 7.6
<#
.SYNOPSIS
    SetupComplete action dispatch must load Invoke-Sc* into script scope and
    skip catalog rows with empty FunctionName (inline-only steps).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [System.Collections.Generic.List[string]]::new()

function Add-ScDispatchFailure {
    param([string]$Message)
    $script:failures.Add($Message) | Out-Null
}

$setupRoot = Join-Path $root 'src\runtime\setup'
. (Join-Path $setupRoot 'Setup.Actions.ps1')

$emptyNameActions = @(
    Get-WinMintSetupActionCatalog |
        Where-Object { [string]::IsNullOrWhiteSpace([string]$_.FunctionName) } |
        ForEach-Object { [string]$_.Id }
)
foreach ($expectedInline in @('first-logon-runonce', 'inline-secret-cleanup')) {
    if ($emptyNameActions -notcontains $expectedInline) {
        Add-ScDispatchFailure "Catalog action '$expectedInline' must use empty FunctionName (inline-only)."
    }
}

# Historical bug: Import ran `. $modulePath` inside a helper function, so module
# functions landed in that function's local scope and vanished before the action loop.
# Promoting only Invoke-Sc* still stranded helpers (Resolve-ScPowerPlanActivation).
foreach ($name in @(
        'Invoke-ScTimeSync',
        'Invoke-ScPowerProfile',
        'Invoke-ScAutoLogonStamp',
        'Invoke-ScAutoLogonStampFinal',
        'Resolve-ScPowerPlanActivation',
        'Get-ScPowerPlanCatalog',
        'Test-ScWindowsTerminalPresent'
    )) {
    Remove-Item -LiteralPath "Function:$name" -ErrorAction SilentlyContinue
}
Import-WinMintSetupActionModules -PayloadRoot $setupRoot
if (Get-Command Invoke-ScEdgeRemoval -ErrorAction SilentlyContinue) {
    Add-ScDispatchFailure 'Invoke-ScEdgeRemoval must not exist; Edge uninstall is not a SetupComplete product path.'
}
if (@(Get-WinMintSetupActionCatalog | Where-Object { [string]$_.Id -eq 'edge-removal' }).Count -gt 0) {
    Add-ScDispatchFailure 'Setup action catalog must not include edge-removal.'
}
if (-not (Get-Command Invoke-ScTimeSync -ErrorAction SilentlyContinue)) {
    Add-ScDispatchFailure 'Import-WinMintSetupActionModules must expose Invoke-ScTimeSync after return.'
}
if (-not (Get-Command Invoke-ScAutoLogonStamp -ErrorAction SilentlyContinue)) {
    Add-ScDispatchFailure 'Import-WinMintSetupActionModules must expose Invoke-ScAutoLogonStamp (defaultuser0 Winlogon restamp).'
}
if (-not (Get-Command Invoke-ScAutoLogonStampFinal -ErrorAction SilentlyContinue)) {
    Add-ScDispatchFailure 'Import-WinMintSetupActionModules must expose Invoke-ScAutoLogonStampFinal (late defaultuser0 restamp).'
}
if (-not (Get-Command Resolve-ScPowerPlanActivation -ErrorAction SilentlyContinue)) {
    Add-ScDispatchFailure 'Import-WinMintSetupActionModules must promote helpers (Resolve-ScPowerPlanActivation), not only Invoke-Sc*.'
}
if (-not (Get-Command Test-ScWindowsTerminalPresent -ErrorAction SilentlyContinue)) {
    Add-ScDispatchFailure 'Import-WinMintSetupActionModules must promote Test-ScWindowsTerminalPresent for toolchain sanity check.'
}
if (-not (Get-Command Invoke-ScOobeRehydrationSuppression -ErrorAction SilentlyContinue)) {
    Add-ScDispatchFailure 'Import-WinMintSetupActionModules must expose Invoke-ScOobeRehydrationSuppression.'
}
$catalogIds = @(Get-WinMintSetupActionCatalog | ForEach-Object { [string]$_.Id })
$autoLogonIdx = $catalogIds.IndexOf('autologon-stamp')
$autoLogonFinalIdx = $catalogIds.IndexOf('autologon-stamp-final')
$toolchainIdx = $catalogIds.IndexOf('toolchain-install')
$runOnceIdx = $catalogIds.IndexOf('first-logon-runonce')
$secretCleanupIdx = $catalogIds.IndexOf('inline-secret-cleanup')
if ($autoLogonIdx -lt 0) {
    Add-ScDispatchFailure 'Catalog must include autologon-stamp.'
}
elseif ($toolchainIdx -ge 0 -and $autoLogonIdx -gt $toolchainIdx) {
    Add-ScDispatchFailure 'autologon-stamp must run before toolchain-install so defaultuser0 cannot hang FirstLogonAnim during later SetupComplete work.'
}
elseif ($runOnceIdx -ge 0 -and $autoLogonIdx -lt $runOnceIdx) {
    Add-ScDispatchFailure 'autologon-stamp should run after first-logon-runonce registration.'
}
if ($autoLogonFinalIdx -lt 0) {
    Add-ScDispatchFailure 'Catalog must include autologon-stamp-final before secret cleanup.'
}
elseif ($toolchainIdx -ge 0 -and $autoLogonFinalIdx -lt $toolchainIdx) {
    Add-ScDispatchFailure 'autologon-stamp-final must run after toolchain-install.'
}
elseif ($secretCleanupIdx -ge 0 -and $autoLogonFinalIdx -gt $secretCleanupIdx) {
    Add-ScDispatchFailure 'autologon-stamp-final must run before inline-secret-cleanup.'
}
$toolchainText = Get-Content -LiteralPath (Join-Path $setupRoot 'SetupComplete\Toolchain.ps1') -Raw
if ($toolchainText -notmatch 'function Test-ScWindowsTerminalPresent') {
    Add-ScDispatchFailure 'Toolchain must detect inbox Windows Terminal.'
}
if ($toolchainText -match 'New-ScWingetInstallArgs|WaitForExit|Start-Process|Resolve-ScWingetExePath') {
    Add-ScDispatchFailure 'Toolchain must not invoke winget/Start-Process to install or upgrade Windows Terminal during SetupComplete.'
}
$wuText = Get-Content -LiteralPath (Join-Path $setupRoot 'SetupComplete\WindowsUpdate.ps1') -Raw
if ($wuText -notmatch 'Start-Process') {
    Add-ScDispatchFailure 'WindowsUpdate restore must use Start-Process for reg.exe (native-command preference must not throw).'
}
if ($wuText -match 'Get-WindowsUpdateLog|Get-WUHistory|UpdateSession|IUpdateSearcher') {
    Add-ScDispatchFailure 'WindowsUpdate restore must not query Windows Update history APIs.'
}
$autoLogonText = Get-Content -LiteralPath (Join-Path $setupRoot 'SetupComplete\AutoLogon.ps1') -Raw
if ($autoLogonText -notmatch 'verify-after-stamp') {
    Add-ScDispatchFailure 'AutoLogon.ps1 must verify-after-stamp Winlogon DefaultUserName/password.'
}
if ($autoLogonText -notmatch 'Local\+autoLogon requires') {
    Add-ScDispatchFailure 'AutoLogon.ps1 must fail-closed (throw) when Local+autoLogon lacks userName/password.'
}
if ($autoLogonText -notmatch "Phase = 'early'") {
    Add-ScDispatchFailure 'AutoLogon.ps1 must support phase early|final for stamp artifacts.'
}

$dispatchText = Get-Content -LiteralPath (Join-Path $setupRoot 'SetupComplete.ps1') -Raw
if ($dispatchText -notmatch 'IsNullOrWhiteSpace\(\[string\]\$_\.FunctionName\)') {
    Add-ScDispatchFailure 'SetupComplete.ps1 must skip catalog actions with empty FunctionName before calling & $action.FunctionName.'
}
if ($dispatchText -match "SetupComplete_errors\.log'\)\s*-Force") {
    Add-ScDispatchFailure 'SetupComplete.ps1 must Append action errors (not -Force overwrite) so module-load failures stay visible.'
}
if ($dispatchText -notmatch 'function Write-ScError') {
    Add-ScDispatchFailure 'SetupComplete.ps1 must define Write-ScError for the hard error channel.'
}
if ($dispatchText -notmatch 'function Write-ScWarn') {
    Add-ScDispatchFailure 'SetupComplete.ps1 must define Write-ScWarn for the soft warning channel.'
}
if ($dispatchText -notmatch 'SetupComplete_warnings\.log') {
    Add-ScDispatchFailure 'Write-ScWarn must target SetupComplete_warnings.log.'
}
if ($dispatchText -match 'function New-ScWingetInstallArgs') {
    Add-ScDispatchFailure 'SetupComplete.ps1 must not keep dead New-ScWingetInstallArgs (Toolchain is presence-only).'
}

# Modules must not Out-File directly to the hard channel — only Write-ScError / orchestrator Write-ScError.
$moduleDir = Join-Path $setupRoot 'SetupComplete'
foreach ($moduleFile in @(Get-ChildItem -LiteralPath $moduleDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue)) {
    $moduleText = Get-Content -LiteralPath $moduleFile.FullName -Raw
    if ($moduleText -match "Out-File[^\n]*SetupComplete_errors\.log") {
        Add-ScDispatchFailure "SetupComplete module '$($moduleFile.Name)' must not Out-File SetupComplete_errors.log directly (use Write-ScError)."
    }
}
if ($wuText -notmatch 'Write-ScError') {
    Add-ScDispatchFailure 'WindowsUpdate restore hard failures must use Write-ScError.'
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}

Write-Host 'SetupComplete action dispatch contract: OK'
exit 0
