#Requires -Version 7.3

function Sync-WinWSUiWorkstationControlsFromState {
    param([Parameter(Mandatory)][object]$State)

    $developerEnabled = @($State.ProfileGroups) -contains 'Developer'
    $desktopEnabled = @($State.ProfileGroups) -contains 'DesktopUI'
    Set-WinWSUiElementVisibility -Name 'PanelShellLayers' -Visibility (
        $desktopEnabled ? [System.Windows.Visibility]::Visible : [System.Windows.Visibility]::Collapsed)
    Set-WinWSUiElementVisibility -Name 'PanelWsl' -Visibility (
        $developerEnabled ? [System.Windows.Visibility]::Visible : [System.Windows.Visibility]::Collapsed)
    Set-WinWSUiElementVisibility -Name 'PanelEditors' -Visibility (
        $developerEnabled ? [System.Windows.Visibility]::Visible : [System.Windows.Visibility]::Collapsed)

    Set-WinWSUiElementChecked -Name 'ChkShellWindhawk' -Checked (@($State.Desktop.Layers) -contains 'windhawk')
    Set-WinWSUiElementChecked -Name 'ChkShellYasb' -Checked (@($State.Desktop.Layers) -contains 'yasb')
    Set-WinWSUiElementChecked -Name 'ChkShellKomorebi' -Checked (@($State.Desktop.Layers) -contains 'komorebi')

    Set-WinWSUiElementChecked -Name 'ChkWslUbuntu' -Checked (@($State.Development.WslDistros) -contains 'Ubuntu')
    Set-WinWSUiElementChecked -Name 'ChkWslDebian' -Checked (@($State.Development.WslDistros) -contains 'Debian')
    Set-WinWSUiElementChecked -Name 'ChkWslArch' -Checked (@($State.Development.WslDistros) -contains 'Arch')
    Set-WinWSUiElementChecked -Name 'ChkWslFedora' -Checked (@($State.Development.WslDistros) -contains 'Fedora')

    Set-WinWSUiElementChecked -Name 'ChkEditorNeovim' -Checked (@($State.Development.Editors) -contains 'neovim')
    Set-WinWSUiElementChecked -Name 'ChkEditorVSCodium' -Checked (@($State.Development.Editors) -contains 'vscodium')
    Set-WinWSUiElementChecked -Name 'ChkEditorCursor' -Checked (@($State.Development.Editors) -contains 'cursor')
    Set-WinWSUiElementChecked -Name 'ChkEditorZed' -Checked (@($State.Development.Editors) -contains 'zed')
    Sync-WinWSUiWorkstationPreview -State $State
}

function Set-WinWSUiPreviewVisibility {
    param(
        [Parameter(Mandatory)][string]$Name,
        [bool]$Visible
    )

    Set-WinWSUiElementVisibility -Name $Name -Visibility (
        $Visible ? [System.Windows.Visibility]::Visible : [System.Windows.Visibility]::Collapsed)
}

function Sync-WinWSUiWorkstationPreview {
    param([Parameter(Mandatory)][object]$State)

    $layers = @($State.Desktop.Layers)
    Set-WinWSUiPreviewVisibility -Name 'WorkstationPreviewYasb' -Visible ($layers -contains 'yasb')
    Set-WinWSUiPreviewVisibility -Name 'WorkstationPreviewKomorebi' -Visible ($layers -contains 'komorebi')
    Set-WinWSUiPreviewVisibility -Name 'WorkstationPreviewWindhawk' -Visible ($layers -contains 'windhawk')

    $shellCount = @($layers | Where-Object { [string]$_ -ne 'standard' }).Count
    $editorCount = @($State.Development.Editors).Count
    $wslCount = @($State.Development.WslDistros).Count
    Set-WinWSUiElementText -Name 'TxtWorkstationShellCount' -Text ("{0} shell layer{1}" -f
        $shellCount,
        ($shellCount -eq 1 ? '' : 's'))
    Set-WinWSUiElementText -Name 'TxtWorkstationEditorCount' -Text ("{0} editor{1}" -f
        $editorCount,
        ($editorCount -eq 1 ? '' : 's'))
    Set-WinWSUiElementText -Name 'TxtWorkstationWslCount' -Text ("{0} distro{1}" -f
        $wslCount,
        ($wslCount -eq 1 ? '' : 's'))
}

function Sync-WinWSUiWorkstationStateFromControls {
    param([Parameter(Mandatory)][object]$State)

    $developerEnabled = @($State.ProfileGroups) -contains 'Developer'
    $desktopEnabled = @($State.ProfileGroups) -contains 'DesktopUI'

    $layers = [System.Collections.Generic.List[string]]::new()
    $layers.Add('standard')
    if ($desktopEnabled) {
        if (Get-WinWSUiElementChecked -Name 'ChkShellWindhawk') { $layers.Add('windhawk') }
        if (Get-WinWSUiElementChecked -Name 'ChkShellYasb') { $layers.Add('yasb') }
        if (Get-WinWSUiElementChecked -Name 'ChkShellKomorebi') { $layers.Add('komorebi') }
    }
    $State.Desktop.Layers = $layers.ToArray()

    $distros = [System.Collections.Generic.List[string]]::new()
    if ($developerEnabled) {
        if (Get-WinWSUiElementChecked -Name 'ChkWslUbuntu') { $distros.Add('Ubuntu') }
        if (Get-WinWSUiElementChecked -Name 'ChkWslDebian') { $distros.Add('Debian') }
        if (Get-WinWSUiElementChecked -Name 'ChkWslArch') { $distros.Add('Arch') }
        if (Get-WinWSUiElementChecked -Name 'ChkWslFedora') { $distros.Add('Fedora') }
    }
    $State.Development.WslDistros = $distros.ToArray()

    $editors = [System.Collections.Generic.List[string]]::new()
    if ($developerEnabled) {
        if (Get-WinWSUiElementChecked -Name 'ChkEditorCursor') { $editors.Add('cursor') }
        if (Get-WinWSUiElementChecked -Name 'ChkEditorVSCodium') { $editors.Add('vscodium') }
        if (Get-WinWSUiElementChecked -Name 'ChkEditorNeovim') { $editors.Add('neovim') }
        if (Get-WinWSUiElementChecked -Name 'ChkEditorZed') { $editors.Add('zed') }
    }
    $State.Development.Editors = $editors.ToArray()

    Sync-WinWSUiWorkstationPreview -State $State
    Update-WinWSUiStateProbe
}

function Initialize-WinWSUiWorkstationStage {
    param([Parameter(Mandatory)][object]$State)

    Sync-WinWSUiWorkstationControlsFromState -State $State
    Sync-WinWSUiWorkstationStateFromControls -State $State

    foreach ($name in @(
            'ChkShellWindhawk',
            'ChkShellYasb',
            'ChkShellKomorebi',
            'ChkWslUbuntu',
            'ChkWslDebian',
            'ChkWslArch',
            'ChkWslFedora',
            'ChkEditorNeovim',
            'ChkEditorVSCodium',
            'ChkEditorCursor',
            'ChkEditorZed'
        )) {
        Register-WinWSUiToggleHandler -Name $name -Handler {
            Sync-WinWSUiWorkstationStateFromControls -State (Get-WinWSUiAppContext).State
        }
    }
}
