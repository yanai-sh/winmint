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

# Historical bug: Import ran `. $modulePath` inside a helper function, so Invoke-Sc*
# landed in that function's local scope and vanished before the action loop.
Remove-Item function:Invoke-ScEdgeRemoval -ErrorAction SilentlyContinue
Remove-Item function:Invoke-ScTimeSync -ErrorAction SilentlyContinue
Import-WinMintSetupActionModules -PayloadRoot $setupRoot
if (-not (Get-Command Invoke-ScEdgeRemoval -ErrorAction SilentlyContinue)) {
    Add-ScDispatchFailure 'Import-WinMintSetupActionModules must expose Invoke-ScEdgeRemoval after return (script scope, not function-local).'
}
if (-not (Get-Command Invoke-ScTimeSync -ErrorAction SilentlyContinue)) {
    Add-ScDispatchFailure 'Import-WinMintSetupActionModules must expose Invoke-ScTimeSync after return.'
}

$dispatchText = Get-Content -LiteralPath (Join-Path $setupRoot 'SetupComplete.ps1') -Raw
if ($dispatchText -notmatch 'IsNullOrWhiteSpace\(\[string\]\$_\.FunctionName\)') {
    Add-ScDispatchFailure 'SetupComplete.ps1 must skip catalog actions with empty FunctionName before calling & $action.FunctionName.'
}
if ($dispatchText -match "SetupComplete_errors\.log'\)\s*-Force") {
    Add-ScDispatchFailure 'SetupComplete.ps1 must Append action errors (not -Force overwrite) so module-load failures stay visible.'
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}

Write-Host 'SetupComplete action dispatch contract: OK'
exit 0
