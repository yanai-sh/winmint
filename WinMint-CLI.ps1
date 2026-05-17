#Requires -Version 7.3

[CmdletBinding()]
param(
    [string]$ProfilePath,
    [string]$SourceIso,
    [string]$UupDumpZip,
    [string]$SourceIsoOverride,
    [ValidateSet('amd64', 'arm64', 'x86')]
    [string]$Architecture,
    [string]$ComputerName = 'WinWS',
    [string]$AccountName = 'dev',
    [ValidateSet('Local', 'MicrosoftOobe')]
    [string]$AccountMode = 'Local',
    [string]$Password = '',
    [string]$PasswordPath = '',
    [string]$PasswordEnvVar = '',
    [switch]$AutoLogon,
    [switch]$AutoWipeDisk,
    [ValidateSet('Minimal', 'CopilotPlus')]
    [string]$SetupOption = 'Minimal',
    [ValidateSet('TargetLicense', 'Fixed')]
    [string]$EditionMode = 'TargetLicense',
    [string]$Edition = '',
    [ValidateSet('None', 'Host', 'Custom')]
    [string]$DriverSource = 'None',
    [string]$DriverPath = '',
    [ValidateSet('ThisPC', 'DifferentPC')]
    [string]$TargetDevice = 'DifferentPC',
    [string]$DriverPack = '',
    [string]$TimeZoneId,
    [string]$InputLocale,
    [string]$SystemLocale,
    [string]$UILanguage,
    [string]$UILanguageFallback,
    [string]$UserLocale,
    [switch]$LocationServices,
    [switch]$NoLocationServices,
    [switch]$NonInteractive,
    [switch]$ExportHostDrivers,
    [switch]$Developer,
    [switch]$Copilot,
    [Alias('Desktop-UI')]
    [switch]$DesktopUI,
    [switch]$Gaming,
    [switch]$InstallWindhawk,
    [switch]$InstallYasb,
    [switch]$InstallKomorebi,
    [switch]$DryRun,
    [switch]$ValidateOnly,
    [switch]$Json,
    [switch]$NoProgress,
    [switch]$Quiet,
    [switch]$AllowElevate,
    [switch]$Yes,
    [switch]$ListWork,
    [string]$CleanWork
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 2.0

. "$PSScriptRoot\src\WinWS\WinWS.ps1"

Initialize-WinWSEngine -RepositoryRoot $PSScriptRoot -DryRun:$DryRun -ExportHostDrivers:$ExportHostDrivers

$headlessMode = $PSBoundParameters.ContainsKey('ProfilePath') -or
    $PSBoundParameters.ContainsKey('SourceIso') -or
    $PSBoundParameters.ContainsKey('UupDumpZip') -or
    $PSBoundParameters.ContainsKey('SourceIsoOverride') -or
    $PSBoundParameters.ContainsKey('PasswordPath') -or
    $PSBoundParameters.ContainsKey('PasswordEnvVar') -or
    $PSBoundParameters.ContainsKey('TargetDevice') -or
    $PSBoundParameters.ContainsKey('DriverPack') -or
    $PSBoundParameters.ContainsKey('Developer') -or
    $PSBoundParameters.ContainsKey('Copilot') -or
    $PSBoundParameters.ContainsKey('DesktopUI') -or
    $PSBoundParameters.ContainsKey('Gaming') -or
    $PSBoundParameters.ContainsKey('DryRun') -or
    $PSBoundParameters.ContainsKey('LocationServices') -or
    $PSBoundParameters.ContainsKey('NoLocationServices') -or
    $PSBoundParameters.ContainsKey('ValidateOnly') -or
    $PSBoundParameters.ContainsKey('Json') -or
    $PSBoundParameters.ContainsKey('NoProgress') -or
    $PSBoundParameters.ContainsKey('Quiet') -or
    $PSBoundParameters.ContainsKey('AllowElevate') -or
    $PSBoundParameters.ContainsKey('Yes') -or
    $PSBoundParameters.ContainsKey('ListWork') -or
    $PSBoundParameters.ContainsKey('CleanWork') -or
    $NonInteractive

if ($headlessMode) {
    $headlessResult = Invoke-WinWSHeadlessCli `
        -BoundParameters $PSBoundParameters `
        -ProfilePath $ProfilePath `
        -SourceIso $SourceIso `
        -UupDumpZip $UupDumpZip `
        -SourceIsoOverride $SourceIsoOverride `
        -Architecture $Architecture `
        -ComputerName $ComputerName `
        -AccountName $AccountName `
        -AccountMode $AccountMode `
        -Password $Password `
        -PasswordPath $PasswordPath `
        -PasswordEnvVar $PasswordEnvVar `
        -AutoLogon:$AutoLogon `
        -AutoWipeDisk:$AutoWipeDisk `
        -SetupOption $SetupOption `
        -EditionMode $EditionMode `
        -Edition $Edition `
        -DriverSource $DriverSource `
        -DriverPath $DriverPath `
        -TargetDevice $TargetDevice `
        -DriverPack $DriverPack `
        -TimeZoneId $TimeZoneId `
        -InputLocale $InputLocale `
        -SystemLocale $SystemLocale `
        -UILanguage $UILanguage `
        -UILanguageFallback $UILanguageFallback `
        -UserLocale $UserLocale `
        -LocationServices:$LocationServices `
        -NoLocationServices:$NoLocationServices `
        -ExportHostDrivers:$ExportHostDrivers `
        -Developer:$Developer `
        -Copilot:$Copilot `
        -DesktopUI:$DesktopUI `
        -Gaming:$Gaming `
        -InstallWindhawk:$InstallWindhawk `
        -InstallYasb:$InstallYasb `
        -InstallKomorebi:$InstallKomorebi `
        -DryRun:$DryRun `
        -ValidateOnly:$ValidateOnly `
        -Json:$Json `
        -NoProgress:$NoProgress `
        -Quiet:$Quiet `
        -AllowElevate:$AllowElevate `
        -Yes:$Yes `
        -ListWork:$ListWork `
        -CleanWork $CleanWork
    if ($headlessResult -and [string]$headlessResult.result -in @('failed', 'validation-failed')) {
        exit 1
    }
    return
}

Invoke-WinWSConsoleBuild `
    -ProfilePath $ProfilePath `
    -SourceIso $SourceIso `
    -Architecture $Architecture `
    -ComputerName $ComputerName `
    -AccountName $AccountName `
    -AccountMode $AccountMode `
    -Password $Password `
    -AutoLogon:$AutoLogon `
    -AutoWipeDisk:$AutoWipeDisk `
    -SetupOption $SetupOption `
    -EditionMode $EditionMode `
    -Edition $Edition `
    -DriverSource $DriverSource `
    -DriverPath $DriverPath `
    -TimeZoneId $TimeZoneId `
    -InputLocale $InputLocale `
    -SystemLocale $SystemLocale `
    -UILanguage $UILanguage `
    -UILanguageFallback $UILanguageFallback `
    -UserLocale $UserLocale `
    -NonInteractive:$NonInteractive `
    -DryRun:$DryRun `
    -ExportHostDrivers:$ExportHostDrivers `
    -InstallWindhawk:$InstallWindhawk `
    -InstallYasb:$InstallYasb `
    -InstallKomorebi:$InstallKomorebi
