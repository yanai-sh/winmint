#Requires -Version 7.6
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path -LiteralPath (Join-Path $root 'src\runtime\setup\FirstLogon.Region.ps1'))) {
    $root = Split-Path -Parent $PSScriptRoot
}

. (Join-Path $root 'src\runtime\setup\FirstLogon.Region.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
function Add-DmaLocFailure([string]$Message) { $failures.Add($Message) | Out-Null }

$offErrors = @(Test-WinMintFirstLogonLocationRestoreCompliant -RestoreLocationServices $false -LocationPosture ([ordered]@{
            machineConsent = 'Deny'
            userConsent = 'Deny'
            disableLocationPolicy = 1
            sensorPermissionState = 0
            locationService = [ordered]@{ present = $true; start = 4 }
        }))
if (@($offErrors).Count -ne 0) {
    Add-DmaLocFailure 'Location-off restore must not add consent/lfsvc compliance errors.'
}

$badOn = @(Test-WinMintFirstLogonLocationRestoreCompliant -RestoreLocationServices $true -LocationPosture ([ordered]@{
            machineConsent = 'Deny'
            userConsent = 'Deny'
            disableLocationPolicy = 1
            sensorPermissionState = 0
            locationService = [ordered]@{ present = $true; start = 4 }
        }))
if (@($badOn).Count -lt 2) {
    Add-DmaLocFailure 'Location-on restore must fail closed on Deny consent and disabled lfsvc/DisableLocation.'
}
if (-not (@($badOn) -match 'consent')) {
    Add-DmaLocFailure 'Location-on restore must mention consent when Allow is missing.'
}
if (-not (@($badOn) -match 'lfsvc')) {
    Add-DmaLocFailure 'Location-on restore must mention lfsvc when Start=4.'
}

$goodOn = @(Test-WinMintFirstLogonLocationRestoreCompliant -RestoreLocationServices $true -LocationPosture ([ordered]@{
            machineConsent = 'Allow'
            userConsent = 'Allow'
            disableLocationPolicy = $null
            sensorPermissionState = 1
            locationService = [ordered]@{ present = $true; start = 3 }
        }))
if (@($goodOn).Count -ne 0) {
    Add-DmaLocFailure "Location-on restore should pass when consent Allow and lfsvc Start=3; got: $($goodOn -join ' | ')"
}

if ($failures.Count -gt 0) {
    Write-Host 'DMA location compliance contract: FAIL'
    $failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}
Write-Host 'DMA location compliance contract: OK'
exit 0
