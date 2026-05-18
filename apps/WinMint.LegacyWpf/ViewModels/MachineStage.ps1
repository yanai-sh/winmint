#Requires -Version 7.3

function Invoke-WinMintUiBrowseDriver {
    param([Parameter(Mandatory)][object]$State)

    if (Test-WinMintUiAppFixtureMode) { return }
    $win = Get-WinMintUiAppWindowOptional
    if ($null -eq $win) { return }
    $btn = $win.FindName('BtnDriverBrowse')
    if ($null -eq $btn) { return }

    $cm = $btn.ContextMenu
    if ($null -eq $cm) { return }
    $cm.PlacementTarget = $btn
    $cm.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
    $cm.IsOpen = $true
}

function Invoke-WinMintUiBrowseDriverFolder {
    param([Parameter(Mandatory)][object]$State)

    if (Test-WinMintUiAppFixtureMode) { return }
    if ($null -eq (Get-WinMintUiAppWindowOptional)) { return }
    try { Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop } catch { return }

    $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dlg.Description = 'Select a folder that contains driver .inf files or .msi packages (subfolders are scanned).'
    $dlg.UseDescriptionForTitle = $true
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $sel = [string]$dlg.SelectedPath
    if ([string]::IsNullOrWhiteSpace($sel)) { return }

    Set-WinMintUiElementText -Name 'TxtDriverPath' -Text $sel
    Sync-WinMintUiMachineStateFromControls -State $State
}

function Invoke-WinMintUiBrowseDriverFile {
    param([Parameter(Mandatory)][object]$State)

    if (Test-WinMintUiAppFixtureMode) { return }
    $win = Get-WinMintUiAppWindowOptional
    if ($null -eq $win) { return }

    $dialog = [Microsoft.Win32.OpenFileDialog]::new()
    $dialog.Title = 'Select driver INF or MSI'
    $dialog.Filter = 'Driver files (*.inf;*.msi)|*.inf;*.msi|All files (*.*)|*.*'
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false

    if ($dialog.ShowDialog($win) -ne $true) { return }
    $file = [string]$dialog.FileName
    if ([string]::IsNullOrWhiteSpace($file)) { return }

    Set-WinMintUiElementText -Name 'TxtDriverPath' -Text $file
    Sync-WinMintUiMachineStateFromControls -State $State
}

function Sync-WinMintUiMachineControlsFromState {
    param([Parameter(Mandatory)][object]$State)

    Set-WinMintUiElementChecked -Name 'RbTargetThisPc' -Checked ([string]$State.Machine.TargetDevice -eq 'ThisPC')
    Set-WinMintUiElementChecked -Name 'RbTargetDifferentPc' -Checked ([string]$State.Machine.TargetDevice -ne 'ThisPC')

    Set-WinMintUiElementChecked -Name 'RbEditionTargetLicense' -Checked ([string]$State.Machine.EditionMode -ne 'Fixed')
    Set-WinMintUiElementChecked -Name 'RbEditionHome' -Checked ([string]$State.Machine.Edition -eq 'Windows 11 Home')
    Set-WinMintUiElementChecked -Name 'RbEditionPro' -Checked ([string]$State.Machine.Edition -eq 'Windows 11 Pro')
    Set-WinMintUiElementChecked -Name 'RbEditionHomeSingleLanguage' -Checked ([string]$State.Machine.Edition -eq 'Windows 11 Home Single Language')

    Set-WinMintUiElementChecked -Name 'RbDriverDefault' -Checked ([string]$State.Drivers.Source -eq 'None')
    Set-WinMintUiElementChecked -Name 'RbDriverThisPc' -Checked ([string]$State.Drivers.Source -eq 'Host')
    Set-WinMintUiElementChecked -Name 'RbDriverCustom' -Checked ([string]$State.Drivers.Source -eq 'Custom')
    Set-WinMintUiElementText -Name 'TxtDriverPath' -Text $State.Drivers.Path
    Set-WinMintUiElementText -Name 'TxtMachineTimeZone' -Text $State.Regional.TimeZoneId
    Set-WinMintUiElementText -Name 'TxtMachineUserLocale' -Text $State.Regional.UserLocale
    Set-WinMintUiElementText -Name 'TxtMachineInputLocale' -Text $State.Regional.InputLocale
    $driverPathVisibility = ([string]$State.Drivers.Source -eq 'Custom') ?
        [System.Windows.Visibility]::Visible :
        [System.Windows.Visibility]::Collapsed
    Set-WinMintUiElementVisibility -Name 'TxtDriverPath' -Visibility $driverPathVisibility
    Set-WinMintUiElementVisibility -Name 'BtnDriverBrowse' -Visibility $driverPathVisibility
    Set-WinMintUiElementVisibility -Name 'DriverPackPanel' -Visibility $driverPathVisibility
    Sync-WinMintUiMachineSummary -State $State
}

function Sync-WinMintUiMachineSummary {
    param([Parameter(Mandatory)][object]$State)

    $summary = Get-WinMintUiMachineSummary -State $State
    Set-WinMintUiElementText -Name 'TxtMachineTargetSummary' -Text $summary.Primary
    Set-WinMintUiElementText -Name 'TxtMachineDetailSummary' -Text $summary.Secondary

    $editionSummary = if ([string]$State.Machine.EditionMode -eq 'Fixed') { [string]$State.Machine.Edition } else { 'Target license' }
    $editionDetail = if ([string]$State.Machine.EditionMode -eq 'Fixed') {
        'Single-edition ISO. Activation is the user responsibility if the target license differs.'
    } else {
        'Keeps all editions so firmware or Setup can choose the target license edition.'
    }
    Set-WinMintUiElementText -Name 'TxtMachineEditionSummary' -Text $editionSummary
    Set-WinMintUiElementText -Name 'TxtMachineEditionDetail' -Text $editionDetail

    $driverSummary = switch ([string]$State.Drivers.Source) {
        'Host' { 'Host drivers from this PC' }
        'Custom' { 'OEM driver pack' }
        default { 'Windows inbox drivers' }
    }
    $driverDetail = switch ([string]$State.Drivers.Source) {
        'Host' { 'Best for reinstalling this same machine.' }
        'Custom' {
            $path = [string]$State.Drivers.Path
            if ([string]::IsNullOrWhiteSpace($path)) { 'Select an OEM .msi, .zip, .inf, or folder.' } else { Get-WinMintUiDisplayFileName -Path $path }
        }
        default { 'Best portable default for another PC.' }
    }
    Set-WinMintUiElementText -Name 'TxtMachineDriversSummary' -Text $driverSummary
    Set-WinMintUiElementText -Name 'TxtMachineDriversDetail' -Text $driverDetail

    $regionSummary = [string]$State.Regional.TimeZoneId
    if ([string]::IsNullOrWhiteSpace($regionSummary)) { $regionSummary = 'Target timezone pending' }
    $regionDetail = '{0}; {1}' -f ([string]$State.Regional.UserLocale), ([string]$State.Regional.InputLocale)
    Set-WinMintUiElementText -Name 'TxtMachineRegionSummary' -Text $regionSummary
    Set-WinMintUiElementText -Name 'TxtMachineRegionDetail' -Text $regionDetail

    $activationSummary = if ([string]$State.Machine.EditionMode -eq 'Fixed') {
        'User activates if license differs'
    } else {
        'Automatic when target license matches'
    }
    $activationDetail = if ([string]$State.Machine.TargetDevice -eq 'ThisPC') {
        'Same-hardware installs can use the existing entitlement when the installed edition matches.'
    } else {
        'WinMint writes no product keys; target hardware or the user provides activation.'
    }
    Set-WinMintUiElementText -Name 'TxtMachineActivationSummary' -Text $activationSummary
    Set-WinMintUiElementText -Name 'TxtMachineActivationDetail' -Text $activationDetail

    $driverPath = [string]$State.Drivers.Path
    $driverName = Get-WinMintUiDisplayFileName -Path $driverPath
    if ([string]::IsNullOrWhiteSpace($driverPath)) {
        $driverName = 'No driver pack selected'
    }
    Set-WinMintUiElementText -Name 'TxtDriverPackName' -Text $driverName
    Set-WinMintUiElementText -Name 'TxtDriverPackPath' -Text (Get-WinMintUiDisplayParentPath -Path $driverPath)
}

function Sync-WinMintUiMachineStateFromControls {
    param([Parameter(Mandatory)][object]$State)

    $previousTargetDevice = [string]$State.Machine.TargetDevice
    $State.Machine.TargetDevice = (Get-WinMintUiElementChecked -Name 'RbTargetThisPc') ? 'ThisPC' : 'DifferentPC'

    if ($previousTargetDevice -ne [string]$State.Machine.TargetDevice) {
        if ([string]$State.Machine.TargetDevice -eq 'ThisPC') {
            Set-WinMintUiElementChecked -Name 'RbDriverThisPc' -Checked $true
        } elseif ([string]$State.Drivers.Source -eq 'Host') {
            Set-WinMintUiElementChecked -Name 'RbDriverDefault' -Checked $true
        }
    }

    if (Get-WinMintUiElementChecked -Name 'RbEditionHome') {
        $State.Machine.EditionMode = 'Fixed'
        $State.Machine.Edition = 'Windows 11 Home'
    } elseif (Get-WinMintUiElementChecked -Name 'RbEditionPro') {
        $State.Machine.EditionMode = 'Fixed'
        $State.Machine.Edition = 'Windows 11 Pro'
    } elseif (Get-WinMintUiElementChecked -Name 'RbEditionHomeSingleLanguage') {
        $State.Machine.EditionMode = 'Fixed'
        $State.Machine.Edition = 'Windows 11 Home Single Language'
    } else {
        $State.Machine.EditionMode = 'TargetLicense'
        $State.Machine.Edition = ''
    }

    $State.Machine.HardwareBypass = $false

    if (Get-WinMintUiElementChecked -Name 'RbDriverCustom') {
        $State.Drivers.Source = 'Custom'
    } elseif (Get-WinMintUiElementChecked -Name 'RbDriverThisPc') {
        $State.Drivers.Source = 'Host'
    } else {
        $State.Drivers.Source = 'None'
    }
    $State.Drivers.ExportHostDrivers = ([string]$State.Drivers.Source -eq 'Host')
    $State.Drivers.Path = Get-WinMintUiElementText -Name 'TxtDriverPath'
    $State.Regional.TimeZoneId = Get-WinMintUiElementText -Name 'TxtMachineTimeZone'
    $State.Regional.UserLocale = Get-WinMintUiElementText -Name 'TxtMachineUserLocale'
    $State.Regional.InputLocale = Get-WinMintUiElementText -Name 'TxtMachineInputLocale'

    $driverPathVisibility = ([string]$State.Drivers.Source -eq 'Custom') ?
        [System.Windows.Visibility]::Visible :
        [System.Windows.Visibility]::Collapsed
    Set-WinMintUiElementVisibility -Name 'TxtDriverPath' -Visibility $driverPathVisibility
    Set-WinMintUiElementVisibility -Name 'BtnDriverBrowse' -Visibility $driverPathVisibility
    Set-WinMintUiElementVisibility -Name 'DriverPackPanel' -Visibility $driverPathVisibility
    Sync-WinMintUiMachineSummary -State $State

    Update-WinMintUiStateProbe
}

function Switch-WinMintUiMachineAdvancedPanel {
    param([Parameter(Mandatory)][string]$PanelName)

    $panel = Get-WinMintUiElement -Name $PanelName
    $next = if ($panel.Visibility -eq [System.Windows.Visibility]::Visible) {
        [System.Windows.Visibility]::Collapsed
    } else {
        [System.Windows.Visibility]::Visible
    }
    Set-WinMintUiElementVisibility -Name $PanelName -Visibility $next
}

function Initialize-WinMintUiMachineStage {
    param(
        [Parameter(Mandatory)][object]$State,
        [switch]$FixtureMode
    )

    Sync-WinMintUiMachineControlsFromState -State $State
    Sync-WinMintUiMachineStateFromControls -State $State

    foreach ($name in @(
        'RbTargetThisPc',
        'RbTargetDifferentPc',

        'RbEditionTargetLicense',
        'RbEditionHome',
        'RbEditionPro',
        'RbEditionHomeSingleLanguage',

        'RbDriverDefault',
        'RbDriverThisPc',
        'RbDriverCustom'
    )) {
        Register-WinMintUiToggleHandler -Name $name -Handler {
            Sync-WinMintUiMachineStateFromControls -State (Get-WinMintUiAppContext).State
        }
    }

    Register-WinMintUiTextHandler -Name 'TxtDriverPath' -Handler {
        Sync-WinMintUiMachineStateFromControls -State (Get-WinMintUiAppContext).State
    }
    foreach ($name in @('TxtMachineTimeZone', 'TxtMachineUserLocale', 'TxtMachineInputLocale')) {
        Register-WinMintUiTextHandler -Name $name -Handler {
            Sync-WinMintUiMachineStateFromControls -State (Get-WinMintUiAppContext).State
        }
    }

    Register-WinMintUiClickHandler -Name 'BtnDriverBrowse' -Handler {
        Invoke-WinMintUiBrowseDriver -State (Get-WinMintUiAppContext).State
    }
    Register-WinMintUiClickHandler -Name 'BtnChangeDrivers' -Handler {
        Switch-WinMintUiMachineAdvancedPanel -PanelName 'AdvancedDriverPanel'
    }
    Register-WinMintUiClickHandler -Name 'BtnChangeEdition' -Handler {
        Switch-WinMintUiMachineAdvancedPanel -PanelName 'AdvancedEditionPanel'
    }
    Register-WinMintUiClickHandler -Name 'BtnChangeRegion' -Handler {
        Switch-WinMintUiMachineAdvancedPanel -PanelName 'AdvancedRegionPanel'
    }
    Register-WinMintUiClickHandler -Name 'MenuBrowseDriverFolder' -Handler {
        Invoke-WinMintUiBrowseDriverFolder -State (Get-WinMintUiAppContext).State
    }
    Register-WinMintUiClickHandler -Name 'MenuBrowseDriverFile' -Handler {
        Invoke-WinMintUiBrowseDriverFile -State (Get-WinMintUiAppContext).State
    }
}
