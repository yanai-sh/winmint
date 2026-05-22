#Requires -Version 7.3

function Sync-WinMintUiWorkstationControlsFromState {
    param([Parameter(Mandatory)][object]$State)

    $developerEnabled = @($State.ProfileGroups) -contains 'Developer'
    $desktopEnabled = @($State.ProfileGroups) -contains 'DesktopUI'
    Set-WinMintUiElementVisibility -Name 'PanelShellLayers' -Visibility (
        $desktopEnabled ? [System.Windows.Visibility]::Visible : [System.Windows.Visibility]::Collapsed)
    Set-WinMintUiElementVisibility -Name 'PanelWsl' -Visibility (
        $developerEnabled ? [System.Windows.Visibility]::Visible : [System.Windows.Visibility]::Collapsed)
    Set-WinMintUiElementVisibility -Name 'PanelEditors' -Visibility (
        $developerEnabled ? [System.Windows.Visibility]::Visible : [System.Windows.Visibility]::Collapsed)

    Set-WinMintUiElementChecked -Name 'ChkShellWindhawk' -Checked (@($State.Desktop.Layers) -contains 'windhawk')
    Set-WinMintUiElementChecked -Name 'ChkShellYasb' -Checked (@($State.Desktop.Layers) -contains 'yasb')
    Set-WinMintUiElementChecked -Name 'ChkShellKomorebi' -Checked (@($State.Desktop.Layers) -contains 'komorebi')

    Set-WinMintUiElementChecked -Name 'ChkWslUbuntu' -Checked (@($State.Development.WslDistros) -contains 'Ubuntu')
    Set-WinMintUiElementChecked -Name 'ChkWslDebian' -Checked (@($State.Development.WslDistros) -contains 'Debian')
    Set-WinMintUiElementChecked -Name 'ChkWslArch' -Checked (@($State.Development.WslDistros) -contains 'Arch')
    Set-WinMintUiElementChecked -Name 'ChkWslFedora' -Checked (@($State.Development.WslDistros) -contains 'Fedora')

    Set-WinMintUiElementChecked -Name 'ChkEditorNeovim' -Checked (@($State.Development.Editors) -contains 'neovim')
    Set-WinMintUiElementChecked -Name 'ChkEditorVSCodium' -Checked (@($State.Development.Editors) -contains 'vscodium')
    Set-WinMintUiElementChecked -Name 'ChkEditorCursor' -Checked (@($State.Development.Editors) -contains 'cursor')
    Set-WinMintUiElementChecked -Name 'ChkEditorZed' -Checked (@($State.Development.Editors) -contains 'zed')
    Sync-WinMintUiWorkstationPreview -State $State
}

function Set-WinMintUiPreviewVisibility {
    param(
        [Parameter(Mandatory)][string]$Name,
        [bool]$Visible
    )

    Set-WinMintUiElementVisibility -Name $Name -Visibility (
        $Visible ? [System.Windows.Visibility]::Visible : [System.Windows.Visibility]::Collapsed)
}

function Sync-WinMintUiWorkstationPreview {
    param([Parameter(Mandatory)][object]$State)

    $layers = @($State.Desktop.Layers)
    Set-WinMintUiPreviewVisibility -Name 'WorkstationPreviewYasb' -Visible ($layers -contains 'yasb')
    Set-WinMintUiPreviewVisibility -Name 'WorkstationPreviewKomorebi' -Visible ($layers -contains 'komorebi')
    Set-WinMintUiPreviewVisibility -Name 'WorkstationPreviewWindhawk' -Visible ($layers -contains 'windhawk')

    $shellCount = @($layers | Where-Object { [string]$_ -ne 'standard' }).Count
    $editorCount = @($State.Development.Editors).Count
    $wslCount = @($State.Development.WslDistros).Count
    Set-WinMintUiElementText -Name 'TxtWorkstationShellCount' -Text ("{0} shell layer{1}" -f
        $shellCount,
        ($shellCount -eq 1 ? '' : 's'))
    Set-WinMintUiElementText -Name 'TxtWorkstationEditorCount' -Text ("{0} editor{1}" -f
        $editorCount,
        ($editorCount -eq 1 ? '' : 's'))
    Set-WinMintUiElementText -Name 'TxtWorkstationWslCount' -Text ("{0} distro{1}" -f
        $wslCount,
        ($wslCount -eq 1 ? '' : 's'))
}

function Sync-WinMintUiWorkstationStateFromControls {
    param([Parameter(Mandatory)][object]$State)

    $developerEnabled = @($State.ProfileGroups) -contains 'Developer'
    $desktopEnabled = @($State.ProfileGroups) -contains 'DesktopUI'

    $layers = [System.Collections.Generic.List[string]]::new()
    $layers.Add('standard')
    if ($desktopEnabled) {
        if (Get-WinMintUiElementChecked -Name 'ChkShellWindhawk') { $layers.Add('windhawk') }
        if (Get-WinMintUiElementChecked -Name 'ChkShellYasb') { $layers.Add('yasb') }
        if (Get-WinMintUiElementChecked -Name 'ChkShellKomorebi') { $layers.Add('komorebi') }
    }
    $State.Desktop.Layers = $layers.ToArray()

    $distros = [System.Collections.Generic.List[string]]::new()
    if ($developerEnabled) {
        if (Get-WinMintUiElementChecked -Name 'ChkWslUbuntu') { $distros.Add('Ubuntu') }
        if (Get-WinMintUiElementChecked -Name 'ChkWslDebian') { $distros.Add('Debian') }
        if (Get-WinMintUiElementChecked -Name 'ChkWslArch') { $distros.Add('Arch') }
        if (Get-WinMintUiElementChecked -Name 'ChkWslFedora') { $distros.Add('Fedora') }
    }
    $State.Development.WslDistros = $distros.ToArray()

    $editors = [System.Collections.Generic.List[string]]::new()
    if ($developerEnabled) {
        if (Get-WinMintUiElementChecked -Name 'ChkEditorCursor') { $editors.Add('cursor') }
        if (Get-WinMintUiElementChecked -Name 'ChkEditorVSCodium') { $editors.Add('vscodium') }
        if (Get-WinMintUiElementChecked -Name 'ChkEditorNeovim') { $editors.Add('neovim') }
        if (Get-WinMintUiElementChecked -Name 'ChkEditorZed') { $editors.Add('zed') }
    }
    $State.Development.Editors = $editors.ToArray()

    Sync-WinMintUiWorkstationPreview -State $State
    Update-WinMintUiStateProbe
}

function Initialize-WinMintUiWorkstationStage {
    param([Parameter(Mandatory)][object]$State)

    Sync-WinMintUiWorkstationControlsFromState -State $State
    Sync-WinMintUiWorkstationStateFromControls -State $State

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
        Register-WinMintUiToggleHandler -Name $name -Handler {
            Sync-WinMintUiWorkstationStateFromControls -State (Get-WinMintUiAppContext).State
        }
    }
}
