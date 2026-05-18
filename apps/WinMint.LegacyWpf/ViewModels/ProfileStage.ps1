#Requires -Version 7.3

function Sync-WinMintUiProfileControlsFromState {
    param([Parameter(Mandatory)][object]$State)

    Set-WinMintUiElementText -Name 'TxtComputerName' -Text $State.Identity.ComputerName
    Set-WinMintUiElementText -Name 'TxtAccountName' -Text $State.Identity.AccountName
    Set-WinMintUiElementChecked -Name 'ChkGroupDeveloper' -Checked (@($State.ProfileGroups) -contains 'Developer')
    Set-WinMintUiElementChecked -Name 'ChkGroupCopilot' -Checked (@($State.ProfileGroups) -contains 'CopilotPlus')
    Set-WinMintUiElementChecked -Name 'ChkGroupGaming' -Checked (@($State.ProfileGroups) -contains 'Gaming')
    Set-WinMintUiElementChecked -Name 'ChkGroupDesktopUI' -Checked (@($State.ProfileGroups) -contains 'DesktopUI')
    Sync-WinMintUiIdentityPreview -State $State
}

function Sync-WinMintUiIdentityPreview {
    param([Parameter(Mandatory)][object]$State)

    $summary = Get-WinMintUiIdentitySummary -State $State
    $computerName = [string]$State.Identity.ComputerName
    $accountName = [string]$State.Identity.AccountName
    if ([string]::IsNullOrWhiteSpace($computerName)) { $computerName = 'WINMINT-PC' }
    if ([string]::IsNullOrWhiteSpace($accountName)) { $accountName = 'first user' }

    Set-WinMintUiElementText -Name 'FirstBootComputerName' -Text $computerName
    Set-WinMintUiElementText -Name 'FirstBootAccountName' -Text $accountName
    Set-WinMintUiElementText -Name 'FirstBootPasswordState' -Text $summary.Secondary
    $message = Get-WinMintUiProfileValidationMessage -State $State
    Set-WinMintUiElementText -Name 'TxtProfileValidation' -Text $message
    Set-WinMintUiElementVisibility -Name 'ProfileValidationPanel' -Visibility (
        [string]::IsNullOrWhiteSpace($message) ?
            [System.Windows.Visibility]::Collapsed :
            [System.Windows.Visibility]::Visible)
}

function Sync-WinMintUiProfileStateFromControls {
    param([Parameter(Mandatory)][object]$State)

    $previousGroups = @($State.ProfileGroups)
    $groups = [System.Collections.Generic.List[string]]::new()
    $groups.Add('Minimal') | Out-Null
    if (Get-WinMintUiElementChecked -Name 'ChkGroupDeveloper') { $groups.Add('Developer') | Out-Null }
    if (Get-WinMintUiElementChecked -Name 'ChkGroupCopilot') { $groups.Add('CopilotPlus') | Out-Null }
    if (Get-WinMintUiElementChecked -Name 'ChkGroupGaming') { $groups.Add('Gaming') | Out-Null }
    if (Get-WinMintUiElementChecked -Name 'ChkGroupDesktopUI') { $groups.Add('DesktopUI') | Out-Null }
    $State.ProfileGroups = @($groups.ToArray() | Select-Object -Unique)

    $developerWasEnabled = $previousGroups -contains 'Developer'
    $developerIsEnabled = @($State.ProfileGroups) -contains 'Developer'
    if (-not $developerIsEnabled -and $developerWasEnabled) {
        $State.Development.Editors = @()
        $State.Development.WslDistros = @()
    }

    $desktopWasEnabled = $previousGroups -contains 'DesktopUI'
    $desktopIsEnabled = @($State.ProfileGroups) -contains 'DesktopUI'
    if ($desktopIsEnabled -and -not $desktopWasEnabled) {
        $State.Desktop.Layers = @('windhawk', 'yasb', 'komorebi')
    }
    elseif (-not $desktopIsEnabled -and $desktopWasEnabled) {
        $State.Desktop.Layers = @('standard')
    }

    $State.Identity.ComputerName = Get-WinMintUiElementText -Name 'TxtComputerName'
    $State.Identity.AccountName = Get-WinMintUiElementText -Name 'TxtAccountName'
    $State.Identity.Password = Get-WinMintUiElementText -Name 'PwdPassword'
    $State.Identity.ConfirmPassword = Get-WinMintUiElementText -Name 'PwdConfirm'
    $State.Identity.AutoLogon = -not [string]::IsNullOrWhiteSpace([string]$State.Identity.Password)

    Sync-WinMintUiIdentityPreview -State $State
    Update-WinMintUiNavigationState
    Update-WinMintUiStateProbe
}

function Initialize-WinMintUiProfileStage {
    param([Parameter(Mandatory)][object]$State)

    Sync-WinMintUiProfileControlsFromState -State $State
    Sync-WinMintUiProfileStateFromControls -State $State

    foreach ($name in @('TxtComputerName', 'TxtAccountName', 'PwdPassword', 'PwdConfirm')) {
        Register-WinMintUiTextHandler -Name $name -Handler {
            Sync-WinMintUiProfileStateFromControls -State (Get-WinMintUiAppContext).State
        }
    }
    foreach ($name in @('ChkGroupDeveloper', 'ChkGroupCopilot', 'ChkGroupGaming', 'ChkGroupDesktopUI')) {
        Register-WinMintUiToggleHandler -Name $name -Handler {
            Sync-WinMintUiProfileStateFromControls -State (Get-WinMintUiAppContext).State
            if (Get-Command Sync-WinMintUiWorkstationControlsFromState -ErrorAction SilentlyContinue) {
                Sync-WinMintUiWorkstationControlsFromState -State (Get-WinMintUiAppContext).State
            }
        }
    }
}
