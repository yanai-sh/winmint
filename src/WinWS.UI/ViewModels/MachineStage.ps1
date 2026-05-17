#Requires -Version 7.3

function Invoke-WinWSUiBrowseDriver {
    param([Parameter(Mandatory)][object]$State)

    if (Test-WinWSUiAppFixtureMode) { return }
    $win = Get-WinWSUiAppWindowOptional
    if ($null -eq $win) { return }
    $btn = $win.FindName('BtnDriverBrowse')
    if ($null -eq $btn) { return }

    $cm = $btn.ContextMenu
    if ($null -eq $cm) { return }
    $cm.PlacementTarget = $btn
    $cm.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
    $cm.IsOpen = $true
}

function Invoke-WinWSUiBrowseDriverFolder {
    param([Parameter(Mandatory)][object]$State)

    if (Test-WinWSUiAppFixtureMode) { return }
    if ($null -eq (Get-WinWSUiAppWindowOptional)) { return }
    try { Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop } catch { return }

    $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dlg.Description = 'Select a folder that contains driver .inf files or .msi packages (subfolders are scanned).'
    $dlg.UseDescriptionForTitle = $true
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $sel = [string]$dlg.SelectedPath
    if ([string]::IsNullOrWhiteSpace($sel)) { return }

    Set-WinWSUiElementText -Name 'TxtDriverPath' -Text $sel
    Sync-WinWSUiMachineStateFromControls -State $State
}

function Invoke-WinWSUiBrowseDriverFile {
    param([Parameter(Mandatory)][object]$State)

    if (Test-WinWSUiAppFixtureMode) { return }
    $win = Get-WinWSUiAppWindowOptional
    if ($null -eq $win) { return }

    $dialog = [Microsoft.Win32.OpenFileDialog]::new()
    $dialog.Title = 'Select driver INF or MSI'
    $dialog.Filter = 'Driver files (*.inf;*.msi)|*.inf;*.msi|All files (*.*)|*.*'
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false

    if ($dialog.ShowDialog($win) -ne $true) { return }
    $file = [string]$dialog.FileName
    if ([string]::IsNullOrWhiteSpace($file)) { return }

    Set-WinWSUiElementText -Name 'TxtDriverPath' -Text $file
    Sync-WinWSUiMachineStateFromControls -State $State
}

function Sync-WinWSUiMachineControlsFromState {
    param([Parameter(Mandatory)][object]$State)

    Set-WinWSUiElementChecked -Name 'RbTargetThisPc' -Checked ([string]$State.Machine.TargetDevice -eq 'ThisPC')
    Set-WinWSUiElementChecked -Name 'RbTargetDifferentPc' -Checked ([string]$State.Machine.TargetDevice -ne 'ThisPC')




    Set-WinWSUiElementChecked -Name 'RbDriverDefault' -Checked ([string]$State.Drivers.Source -eq 'None')
    Set-WinWSUiElementChecked -Name 'RbDriverThisPc' -Checked ([string]$State.Drivers.Source -eq 'Host')
    Set-WinWSUiElementChecked -Name 'RbDriverCustom' -Checked ([string]$State.Drivers.Source -eq 'Custom')
    Set-WinWSUiElementText -Name 'TxtDriverPath' -Text $State.Drivers.Path
    $driverPathVisibility = ([string]$State.Drivers.Source -eq 'Custom') ?
        [System.Windows.Visibility]::Visible :
        [System.Windows.Visibility]::Collapsed
    Set-WinWSUiElementVisibility -Name 'TxtDriverPath' -Visibility $driverPathVisibility
    Set-WinWSUiElementVisibility -Name 'BtnDriverBrowse' -Visibility $driverPathVisibility
    Set-WinWSUiElementVisibility -Name 'DriverPackPanel' -Visibility $driverPathVisibility
    Sync-WinWSUiMachineSummary -State $State
}

function Sync-WinWSUiMachineSummary {
    param([Parameter(Mandatory)][object]$State)

    $summary = Get-WinWSUiMachineSummary -State $State
    Set-WinWSUiElementText -Name 'TxtMachineTargetSummary' -Text $summary.Primary
    Set-WinWSUiElementText -Name 'TxtMachineDetailSummary' -Text $summary.Secondary

    $driverPath = [string]$State.Drivers.Path
    $driverName = Get-WinWSUiDisplayFileName -Path $driverPath
    if ([string]::IsNullOrWhiteSpace($driverPath)) {
        $driverName = 'No driver pack selected'
    }
    Set-WinWSUiElementText -Name 'TxtDriverPackName' -Text $driverName
    Set-WinWSUiElementText -Name 'TxtDriverPackPath' -Text (Get-WinWSUiDisplayParentPath -Path $driverPath)
}

function Sync-WinWSUiMachineStateFromControls {
    param([Parameter(Mandatory)][object]$State)

    $State.Machine.TargetDevice = (Get-WinWSUiElementChecked -Name 'RbTargetThisPc') ? 'ThisPC' : 'DifferentPC'

    $State.Machine.EditionMode = 'TargetLicense'
    $State.Machine.Edition = ''

    $State.Machine.HardwareBypass = $false

    if (Get-WinWSUiElementChecked -Name 'RbDriverCustom') {
        $State.Drivers.Source = 'Custom'
    } elseif (Get-WinWSUiElementChecked -Name 'RbDriverThisPc') {
        $State.Drivers.Source = 'Host'
    } else {
        $State.Drivers.Source = 'None'
    }
    $State.Drivers.ExportHostDrivers = ([string]$State.Drivers.Source -eq 'Host')
    $State.Drivers.Path = Get-WinWSUiElementText -Name 'TxtDriverPath'

    $driverPathVisibility = ([string]$State.Drivers.Source -eq 'Custom') ?
        [System.Windows.Visibility]::Visible :
        [System.Windows.Visibility]::Collapsed
    Set-WinWSUiElementVisibility -Name 'TxtDriverPath' -Visibility $driverPathVisibility
    Set-WinWSUiElementVisibility -Name 'BtnDriverBrowse' -Visibility $driverPathVisibility
    Set-WinWSUiElementVisibility -Name 'DriverPackPanel' -Visibility $driverPathVisibility
    Sync-WinWSUiMachineSummary -State $State

    Update-WinWSUiStateProbe
}

function Initialize-WinWSUiMachineStage {
    param(
        [Parameter(Mandatory)][object]$State,
        [switch]$FixtureMode
    )

    Sync-WinWSUiMachineControlsFromState -State $State
    Sync-WinWSUiMachineStateFromControls -State $State

    foreach ($name in @(
        'RbTargetThisPc',
        'RbTargetDifferentPc',

        'RbDriverDefault',
        'RbDriverThisPc',
        'RbDriverCustom'
    )) {
        Register-WinWSUiToggleHandler -Name $name -Handler {
            Sync-WinWSUiMachineStateFromControls -State (Get-WinWSUiAppContext).State
        }
    }

    Register-WinWSUiTextHandler -Name 'TxtDriverPath' -Handler {
        Sync-WinWSUiMachineStateFromControls -State (Get-WinWSUiAppContext).State
    }

    Register-WinWSUiClickHandler -Name 'BtnDriverBrowse' -Handler {
        Invoke-WinWSUiBrowseDriver -State (Get-WinWSUiAppContext).State
    }
    Register-WinWSUiClickHandler -Name 'MenuBrowseDriverFolder' -Handler {
        Invoke-WinWSUiBrowseDriverFolder -State (Get-WinWSUiAppContext).State
    }
    Register-WinWSUiClickHandler -Name 'MenuBrowseDriverFile' -Handler {
        Invoke-WinWSUiBrowseDriverFile -State (Get-WinWSUiAppContext).State
    }
}
