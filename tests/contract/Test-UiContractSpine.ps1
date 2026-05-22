#Requires -Version 7.3
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)

    $failures.Add($Message) | Out-Null
    Write-Error $Message -ErrorAction Continue
}

function Assert-Equal {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
    )

    if ([string]$Actual -ne [string]$Expected) {
        Add-Failure "$Message Expected '$Expected', got '$Actual'."
    }
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) { Add-Failure $Message }
}

. (Join-Path $root 'apps\legacy-wpf\State\WinMintUiState.ps1')
. (Join-Path $root 'apps\legacy-wpf\Services\Summary.ps1')
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')

$state = New-WinMintUiState -RepositoryRoot $root
$state.Iso.Path = Get-WinMintTestIsoFixturePath
$state.Iso.Architecture = 'arm64'
$state.Iso.State = [WinMintIsoState]::Verified
$state.Iso.Editions = @('Windows 11 Pro', 'Windows 11 Enterprise')
$state.Machine.TargetDevice = 'DifferentPC'
$state.Machine.EditionMode = 'TargetLicense'
$state.Drivers.Source = 'Custom'
$state.Drivers.Path = 'C:\Users\Yanai\Documents\ISO\input\Intel_NUC_LAN_WiFi.msi'
$state.Machine.HardwareBypass = $true
$state.Disk.Mode = 'AutoWipeDisk0'
$state.Disk.WipeConfirmed = $true
$state.Identity.ComputerName = 'WINMINT-LAB'
$state.Identity.AccountName = 'yanai'
$state.Desktop.Layers = @('standard', 'windhawk', 'yasb', 'komorebi')
$state.Development.Editors = @('cursor', 'zed')
$state.Development.WslDistros = @('Ubuntu', 'Debian')

$contract = Get-WinMintUiLaunchContractSummary -State $state
Assert-Equal $contract.Source.Primary 'Windows 11 ISO - arm64' 'Source primary summary mismatch.'
Assert-Equal $contract.Source.Secondary ([IO.Path]::GetFileName($state.Iso.Path)) 'Source filename summary mismatch.'
Assert-Equal $contract.Target.Primary 'Another PC' 'Target primary summary mismatch.'
Assert-True ($contract.Target.Badges -contains 'Custom drivers') 'Target summary should flag custom drivers.'
Assert-Equal $contract.Disk.Primary 'Erase disk 0 during Windows Setup' 'Disk summary should name disk 0 explicitly.'
Assert-True $contract.Disk.IsDanger 'Disk summary should mark erase mode as danger.'
Assert-Equal $contract.Identity.Primary 'WINMINT-LAB / yanai' 'Identity summary mismatch.'
Assert-Equal $contract.Identity.Secondary 'Passwordless local admin' 'Identity passwordless summary mismatch.'
Assert-Equal $contract.Workstation.Primary 'Windhawk, YASB, Komorebi' 'Workstation shell summary mismatch.'
Assert-Equal $contract.Workstation.Secondary 'Cursor, Zed + Ubuntu, Debian' 'Workstation tool summary mismatch.'
Assert-True ($contract.Output.Primary -like 'WinMint-Slim-WINMINT-LAB.iso') 'Output name should include computer name.'

$manual = New-WinMintUiState -RepositoryRoot $root
$manual.Disk.Mode = 'Manual'
$manualContract = Get-WinMintUiLaunchContractSummary -State $manual
Assert-Equal $manualContract.Disk.Primary 'Manual disk selection in Windows Setup' 'Manual disk summary mismatch.'
Assert-True (-not $manualContract.Disk.IsDanger) 'Manual disk mode must not be danger.'

$thisPc = New-WinMintUiState -RepositoryRoot $root
$thisPc.Machine.TargetDevice = 'ThisPC'
$thisPc.Drivers.Source = 'Host'
$thisPc.Drivers.ExportHostDrivers = $true
$thisPcContract = Get-WinMintUiLaunchContractSummary -State $thisPc
Assert-Equal $thisPcContract.Target.Primary 'This PC' 'This PC target summary mismatch.'
Assert-True ($thisPcContract.Target.Badges -contains 'Host drivers') 'This PC target summary should include host drivers.'
Assert-Equal $thisPc.Regional.InputLocale ([string]$thisPc.Regional.InputLocale) 'This PC regional input locale should be present.'

$fixedPro = New-WinMintUiState -RepositoryRoot $root
$fixedPro.Machine.EditionMode = 'Fixed'
$fixedPro.Machine.Edition = 'Windows 11 Pro'
$fixedProContract = Get-WinMintUiLaunchContractSummary -State $fixedPro
Assert-True ($fixedProContract.Target.Badges -contains 'Single edition') 'Fixed edition summary should include single-edition badge.'
Assert-True ($fixedProContract.Target.Secondary -match 'Windows 11 Pro') 'Fixed edition summary should name Windows 11 Pro.'

$xamlPath = Join-Path $root 'apps\legacy-wpf\Views\MainWindow.xaml'
$xaml = Get-Content -LiteralPath $xamlPath -Raw
foreach ($requiredName in @(
        'StepLabelStart',
        'StepLabelMachine',
        'StepLabelDisk',
        'StepLabelProfile',
        'StepLabelWorkstation',
        'StepLabelLaunch',
        'DriverPackPanel',
        'FirstBootComputerName',
        'FirstBootAccountName',
        'FirstBootPasswordState',
        'WorkstationPreviewYasb',
        'WorkstationPreviewKomorebi',
        'WorkstationPreviewWindhawk',
        'TxtWorkstationShellCount',
        'ContractSourcePrimary',
        'ContractTargetPrimary',
        'ContractDiskPrimary',
        'ContractIdentityPrimary',
        'ContractWorkstationPrimary',
        'ContractOutputPrimary',
        'TxtMachineDriversSummary',
        'TxtMachineEditionSummary',
        'TxtMachineRegionSummary',
        'TxtMachineActivationSummary',
        'BtnChangeDrivers',
        'BtnChangeEdition',
        'BtnChangeRegion',
        'AdvancedDriverPanel',
        'AdvancedEditionPanel',
        'AdvancedRegionPanel',
        'RbEditionTargetLicense',
        'RbEditionHome',
        'RbEditionPro',
        'RbEditionHomeSingleLanguage',
        'LaunchContractPanel',
        'LaunchProgressPanel'
    )) {
    Assert-True ($xaml -match "x:Name=`"$requiredName`"") "MainWindow.xaml missing x:Name '$requiredName'."
}

Assert-True ($xaml -match 'AutomationProperties\.Name="Choose ISO"') 'ISO browse button needs accessible name.'
Assert-True ($xaml -match 'AutomationProperties\.Name="Browse driver folder"') 'Driver folder browse needs accessible name.'
Assert-True ($xaml -match 'AutomationProperties\.Name="Browse driver INF or MSI"') 'Driver file browse needs accessible name.'
Assert-True ($xaml -match 'MinHeight="(40|44)"') 'Primary controls should use at least 40px minimum height on key buttons.'
Assert-True ($xaml -match 'xmlns:ui="http://schemas\.lepo\.co/wpfui/2022/xaml"') 'MainWindow.xaml should declare the WPF UI namespace.'
Assert-True ($xaml -match '<ui:ThemesDictionary Theme="Dark" />') 'MainWindow.xaml should merge the WPF UI dark theme dictionary.'
Assert-True ($xaml -match '<ui:ControlsDictionary />') 'MainWindow.xaml should merge the WPF UI controls dictionary.'
Assert-True ($xaml -match 'assets\\brand\\WinMint\.svg') 'MainWindow.xaml should preserve the WinMint SVG brand path.'
Assert-True ($xaml -match '<ui:FluentWindow') 'MainWindow.xaml should use WPF UI FluentWindow (custom chrome / Mica).'
Assert-True ($xaml -match 'Review, then build\.') 'Launch stage should headline the build review.'

if ($failures.Count -gt 0) {
    throw "UI contract spine tests failed with $($failures.Count) failure(s)."
}

Write-Host 'UI contract spine tests passed.'
