#Requires -Version 7.6
<#
.SYNOPSIS
  Red/green check: SetupComplete must stamp Winlogon Autologon for Local+autoLogon.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$setupRoot = Join-Path $root 'src\runtime\setup'
$failures = [System.Collections.Generic.List[string]]::new()

. (Join-Path $setupRoot 'Setup.Actions.ps1')

$action = Get-WinMintSetupActionCatalog | Where-Object { [string]$_.Id -eq 'autologon-stamp' } | Select-Object -First 1
if (-not $action) {
    $failures.Add('Catalog missing autologon-stamp action.') | Out-Null
}
elseif ([string]$action.FunctionName -ne 'Invoke-ScAutoLogonStamp') {
    $failures.Add("autologon-stamp FunctionName should be Invoke-ScAutoLogonStamp; got '$($action.FunctionName)'.") | Out-Null
}

Remove-Item -LiteralPath 'Function:Invoke-ScAutoLogonStamp' -ErrorAction SilentlyContinue
Import-WinMintSetupActionModules -PayloadRoot $setupRoot
if (-not (Get-Command Invoke-ScAutoLogonStamp -ErrorAction SilentlyContinue)) {
    $failures.Add('Invoke-ScAutoLogonStamp missing after Import-WinMintSetupActionModules.') | Out-Null
}

$autoLogonText = Get-Content -LiteralPath (Join-Path $setupRoot 'SetupComplete\AutoLogon.ps1') -Raw
foreach ($needle in @(
        'defaultuser0',
        'DefaultUserName',
        'AutoAdminLogon',
        'AutoLogonCount',
        'DefaultPassword',
        'account'
    )) {
    if ($autoLogonText -notmatch [regex]::Escape($needle)) {
        $failures.Add("AutoLogon.ps1 should mention '$needle'.") | Out-Null
    }
}

# Dry resolve path: skip when autoLogon is off (no registry writes).
$script:logDir = Join-Path ([System.IO.Path]::GetTempPath()) ("winmint-sc-autologon-" + [guid]::NewGuid().ToString('n'))
$null = New-Item -ItemType Directory -Path $script:logDir -Force
function Write-ScLog { param([string]$Message) }
function Get-ScSetupProfileValue {
    param([string]$Section, [string]$Name, $Default = $null)
    if ($Section -eq 'account' -and $Name -eq 'accountMode') { return 'Local' }
    if ($Section -eq 'account' -and $Name -eq 'autoLogon') { return $false }
    return $Default
}
try {
    Invoke-ScAutoLogonStamp
    $artifact = Join-Path $script:logDir 'SetupComplete_AutoLogon.json'
    if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
        $failures.Add('Invoke-ScAutoLogonStamp should write SetupComplete_AutoLogon.json when skipped.') | Out-Null
    }
    else {
        $json = Get-Content -LiteralPath $artifact -Raw | ConvertFrom-Json
        if (-not [bool]$json.skipped) {
            $failures.Add('autoLogon=false should skip the Winlogon stamp.') | Out-Null
        }
    }
}
finally {
    Remove-Item -LiteralPath $script:logDir -Recurse -Force -ErrorAction SilentlyContinue
}

$unattendText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\Image\Unattend.ps1') -Raw
if ($unattendText -notmatch "CreateElement\('Domain'") {
    $failures.Add('Unattend AutoLogon should set Domain to the target computer name for local accounts.') | Out-Null
}
if ($unattendText -notmatch "LogonCount'.*InnerText = '10'") {
    $failures.Add('Unattend AutoLogon LogonCount should be 10 (bounded, survives OOBE burns).') | Out-Null
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}

Write-Host 'Assert-WinMintSetupCompleteAutoLogonStamp: OK'
exit 0
