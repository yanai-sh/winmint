#Requires -Version 7.3

function Sync-WinMintUiDiskControlsFromState {
    param([Parameter(Mandatory)][object]$State)

    $isAuto = [string]$State.Disk.Mode -eq 'AutoWipeDisk0'
    Set-WinMintUiElementChecked -Name 'RbDiskAuto' -Checked $isAuto
    Set-WinMintUiElementChecked -Name 'RbDiskManual' -Checked (-not $isAuto)
    Set-WinMintUiElementChecked -Name 'ChkDiskWipeConfirm' -Checked ($isAuto -and [bool]$State.Disk.WipeConfirmed)
    Update-WinMintUiDiskVisuals -State $State
}

function Update-WinMintUiDiskVisuals {
    param([Parameter(Mandatory)][object]$State)

    $isAuto = [string]$State.Disk.Mode -eq 'AutoWipeDisk0'
    $window = Get-WinMintUiAppWindowOptional
    if ($null -eq $window) { return }

    Set-WinMintUiElementText -Name 'TxtDiskTitle' -Text ($isAuto ?
        'Erase disk 0 automatically.' :
        'Keep install disk selection manual.')
    Set-WinMintUiElementText -Name 'TxtDiskSubtitle' -Text ($isAuto ?
        'Windows Setup will delete existing partitions on disk 0.' :
        'Windows Setup asks where to install. This is the default path.')
    Set-WinMintUiElementText -Name 'TxtDiskManualHint' -Text ($isAuto ?
        'Switch back to the Windows Setup disk picker.' :
        'No unattended wipe command is added.')

    $panel = Get-WinMintUiElement -Name 'AutoWipePanel'
    if ($null -ne $panel) {
        $panel.Background = $isAuto ? $window.Resources['DangerSoftBrush'] : $window.Resources['PanelBrush']
        $panel.BorderBrush = $isAuto ? $window.Resources['DangerBrush'] : $window.Resources['LineBrush']
    }

    $title = Get-WinMintUiElement -Name 'AutoWipeTitle'
    if ($null -ne $title) {
        $title.Foreground = $isAuto ? $window.Resources['DangerBrush'] : $window.Resources['TextSecondaryBrush']
    }

    $detail = Get-WinMintUiElement -Name 'AutoWipeDetail'
    if ($null -ne $detail) {
        $detail.Foreground = $isAuto ? $window.Resources['TextPrimaryBrush'] : $window.Resources['TextSecondaryBrush']
    }

    $confirm = Get-WinMintUiElement -Name 'ChkDiskWipeConfirm'
    if ($null -ne $confirm) {
        $confirm.Visibility = $isAuto ?
            [System.Windows.Visibility]::Visible :
            [System.Windows.Visibility]::Collapsed
        $confirm.IsEnabled = $isAuto
    }

    Set-WinMintUiElementText -Name 'TxtDiskValidation' -Text (
        ($isAuto -and -not [bool]$State.Disk.WipeConfirmed) ?
            'Confirm erase behavior to continue.' :
            '')
}

function Sync-WinMintUiDiskStateFromControls {
    param([Parameter(Mandatory)][object]$State)

    $isAuto = Get-WinMintUiElementChecked -Name 'RbDiskAuto'
    $State.Disk.Mode = $isAuto ? 'AutoWipeDisk0' : 'Manual'
    $State.Disk.WipeConfirmed = $isAuto ? (Get-WinMintUiElementChecked -Name 'ChkDiskWipeConfirm') : $false

    if (-not $isAuto) {
        Set-WinMintUiElementChecked -Name 'ChkDiskWipeConfirm' -Checked $false
    }
    Set-WinMintUiElementContent -Name 'ChkDiskWipeConfirm' -Content (
        'I understand disk 0 will be erased')

    Update-WinMintUiDiskVisuals -State $State
    Update-WinMintUiNavigationState

    Update-WinMintUiStateProbe
}

function Initialize-WinMintUiDiskStage {
    param([Parameter(Mandatory)][object]$State)

    Sync-WinMintUiDiskControlsFromState -State $State
    Sync-WinMintUiDiskStateFromControls -State $State

    foreach ($name in @('RbDiskManual', 'RbDiskAuto', 'ChkDiskWipeConfirm')) {
        Register-WinMintUiToggleHandler -Name $name -Handler {
            Sync-WinMintUiDiskStateFromControls -State (Get-WinMintUiAppContext).State
        }
    }
}
