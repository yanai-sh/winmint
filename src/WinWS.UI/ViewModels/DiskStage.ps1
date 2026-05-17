#Requires -Version 7.3

function Sync-WinWSUiDiskControlsFromState {
    param([Parameter(Mandatory)][object]$State)

    $isAuto = [string]$State.Disk.Mode -eq 'AutoWipeDisk0'
    Set-WinWSUiElementChecked -Name 'RbDiskAuto' -Checked $isAuto
    Set-WinWSUiElementChecked -Name 'RbDiskManual' -Checked (-not $isAuto)
    Set-WinWSUiElementChecked -Name 'ChkDiskWipeConfirm' -Checked ($isAuto -and [bool]$State.Disk.WipeConfirmed)
    Update-WinWSUiDiskVisuals -State $State
}

function Update-WinWSUiDiskVisuals {
    param([Parameter(Mandatory)][object]$State)

    $isAuto = [string]$State.Disk.Mode -eq 'AutoWipeDisk0'
    $window = Get-WinWSUiAppWindowOptional
    if ($null -eq $window) { return }

    Set-WinWSUiElementText -Name 'TxtDiskTitle' -Text ($isAuto ?
        'Erase disk 0 automatically.' :
        'Keep install disk selection manual.')
    Set-WinWSUiElementText -Name 'TxtDiskSubtitle' -Text ($isAuto ?
        'Windows Setup will delete existing partitions on disk 0.' :
        'Windows Setup asks where to install. This is the default path.')
    Set-WinWSUiElementText -Name 'TxtDiskManualHint' -Text ($isAuto ?
        'Switch back to the Windows Setup disk picker.' :
        'No unattended wipe command is added.')

    $panel = Get-WinWSUiElement -Name 'AutoWipePanel'
    if ($null -ne $panel) {
        $panel.Background = $isAuto ? $window.Resources['DangerSoftBrush'] : $window.Resources['PanelBrush']
        $panel.BorderBrush = $isAuto ? $window.Resources['DangerBrush'] : $window.Resources['LineBrush']
    }

    $title = Get-WinWSUiElement -Name 'AutoWipeTitle'
    if ($null -ne $title) {
        $title.Foreground = $isAuto ? $window.Resources['DangerBrush'] : $window.Resources['TextSecondaryBrush']
    }

    $detail = Get-WinWSUiElement -Name 'AutoWipeDetail'
    if ($null -ne $detail) {
        $detail.Foreground = $isAuto ? $window.Resources['TextPrimaryBrush'] : $window.Resources['TextSecondaryBrush']
    }

    $confirm = Get-WinWSUiElement -Name 'ChkDiskWipeConfirm'
    if ($null -ne $confirm) {
        $confirm.Visibility = $isAuto ?
            [System.Windows.Visibility]::Visible :
            [System.Windows.Visibility]::Collapsed
        $confirm.IsEnabled = $isAuto
    }

    Set-WinWSUiElementText -Name 'TxtDiskValidation' -Text (
        ($isAuto -and -not [bool]$State.Disk.WipeConfirmed) ?
            'Confirm erase behavior to continue.' :
            '')
}

function Sync-WinWSUiDiskStateFromControls {
    param([Parameter(Mandatory)][object]$State)

    $isAuto = Get-WinWSUiElementChecked -Name 'RbDiskAuto'
    $State.Disk.Mode = $isAuto ? 'AutoWipeDisk0' : 'Manual'
    $State.Disk.WipeConfirmed = $isAuto ? (Get-WinWSUiElementChecked -Name 'ChkDiskWipeConfirm') : $false

    if (-not $isAuto) {
        Set-WinWSUiElementChecked -Name 'ChkDiskWipeConfirm' -Checked $false
    }
    Set-WinWSUiElementContent -Name 'ChkDiskWipeConfirm' -Content (
        'I understand disk 0 will be erased')

    Update-WinWSUiDiskVisuals -State $State
    Update-WinWSUiNavigationState

    Update-WinWSUiStateProbe
}

function Initialize-WinWSUiDiskStage {
    param([Parameter(Mandatory)][object]$State)

    Sync-WinWSUiDiskControlsFromState -State $State
    Sync-WinWSUiDiskStateFromControls -State $State

    foreach ($name in @('RbDiskManual', 'RbDiskAuto', 'ChkDiskWipeConfirm')) {
        Register-WinWSUiToggleHandler -Name $name -Handler {
            Sync-WinWSUiDiskStateFromControls -State (Get-WinWSUiAppContext).State
        }
    }
}
