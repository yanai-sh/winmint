#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Removes the consumer apps listed on the SL7 profile.
.DESCRIPTION
  Run after Windows Update if you still want that strip. Missing packages are skipped.
  Store, Camera, Notepad, Photos, and Snipping Tool are not in this list.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ids = @(
    'Microsoft.BingNews'
    'Microsoft.BingWeather'
    'Microsoft.GetHelp'
    'Microsoft.Getstarted'
    'Microsoft.MicrosoftOfficeHub'
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.People'
    'Microsoft.PowerAutomateDesktop'
    'Microsoft.Todos'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.WindowsMaps'
    'Microsoft.ZuneMusic'
    'Microsoft.ZuneVideo'
    'MicrosoftCorporationII.QuickAssist'
    'Microsoft.Copilot'
    'Microsoft.GamingApp'
    'Microsoft.Xbox.TCUI'
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxSpeechToTextOverlay'
)

foreach ($id in $ids) {
    Get-AppxPackage -AllUsers -Name $id -ErrorAction SilentlyContinue |
        Remove-AppxPackage -ErrorAction SilentlyContinue
    $provisioned = @(Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $id })
    foreach ($pkg in $provisioned) {
        Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Output $id
}

Write-Output 'Consumer app strip finished.'
