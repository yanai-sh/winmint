#Requires -Version 7.3

function Sync-WinWSUiProfileControlsFromState {
    param([Parameter(Mandatory)][object]$State)

    Set-WinWSUiElementText -Name 'TxtComputerName' -Text $State.Identity.ComputerName
    Set-WinWSUiElementText -Name 'TxtAccountName' -Text $State.Identity.AccountName
    Set-WinWSUiElementChecked -Name 'ChkGroupDeveloper' -Checked (@($State.ProfileGroups) -contains 'Developer')
    Set-WinWSUiElementChecked -Name 'ChkGroupCopilot' -Checked (@($State.ProfileGroups) -contains 'CopilotPlus')
    Set-WinWSUiElementChecked -Name 'ChkGroupGaming' -Checked (@($State.ProfileGroups) -contains 'Gaming')
    Set-WinWSUiElementChecked -Name 'ChkGroupDesktopUI' -Checked (@($State.ProfileGroups) -contains 'DesktopUI')
    Sync-WinWSUiIdentityPreview -State $State
}

function Sync-WinWSUiIdentityPreview {
    param([Parameter(Mandatory)][object]$State)

    $summary = Get-WinWSUiIdentitySummary -State $State
    $computerName = [string]$State.Identity.ComputerName
    $accountName = [string]$State.Identity.AccountName
    if ([string]::IsNullOrWhiteSpace($computerName)) { $computerName = 'WINWS-PC' }
    if ([string]::IsNullOrWhiteSpace($accountName)) { $accountName = 'first user' }

    Set-WinWSUiElementText -Name 'FirstBootComputerName' -Text $computerName
    Set-WinWSUiElementText -Name 'FirstBootAccountName' -Text $accountName
    Set-WinWSUiElementText -Name 'FirstBootPasswordState' -Text $summary.Secondary
    $message = Get-WinWSUiProfileValidationMessage -State $State
    Set-WinWSUiElementText -Name 'TxtProfileValidation' -Text $message
    Set-WinWSUiElementVisibility -Name 'ProfileValidationPanel' -Visibility (
        [string]::IsNullOrWhiteSpace($message) ?
            [System.Windows.Visibility]::Collapsed :
            [System.Windows.Visibility]::Visible)
}

function Sync-WinWSUiProfileStateFromControls {
    param([Parameter(Mandatory)][object]$State)

    $previousGroups = @($State.ProfileGroups)
    $groups = [System.Collections.Generic.List[string]]::new()
    $groups.Add('Minimal') | Out-Null
    if (Get-WinWSUiElementChecked -Name 'ChkGroupDeveloper') { $groups.Add('Developer') | Out-Null }
    if (Get-WinWSUiElementChecked -Name 'ChkGroupCopilot') { $groups.Add('CopilotPlus') | Out-Null }
    if (Get-WinWSUiElementChecked -Name 'ChkGroupGaming') { $groups.Add('Gaming') | Out-Null }
    if (Get-WinWSUiElementChecked -Name 'ChkGroupDesktopUI') { $groups.Add('DesktopUI') | Out-Null }
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

    $State.Identity.ComputerName = Get-WinWSUiElementText -Name 'TxtComputerName'
    $State.Identity.AccountName = Get-WinWSUiElementText -Name 'TxtAccountName'
    $State.Identity.Password = Get-WinWSUiElementText -Name 'PwdPassword'
    $State.Identity.ConfirmPassword = Get-WinWSUiElementText -Name 'PwdConfirm'
    $State.Identity.AutoLogon = -not [string]::IsNullOrWhiteSpace([string]$State.Identity.Password)

    Sync-WinWSUiIdentityPreview -State $State
    Update-WinWSUiNavigationState
    Update-WinWSUiStateProbe
}

function Initialize-WinWSUiProfileStage {
    param([Parameter(Mandatory)][object]$State)

    Sync-WinWSUiProfileControlsFromState -State $State
    Sync-WinWSUiProfileStateFromControls -State $State

    foreach ($name in @('TxtComputerName', 'TxtAccountName', 'PwdPassword', 'PwdConfirm')) {
        Register-WinWSUiTextHandler -Name $name -Handler {
            Sync-WinWSUiProfileStateFromControls -State (Get-WinWSUiAppContext).State
        }
    }
    foreach ($name in @('ChkGroupDeveloper', 'ChkGroupCopilot', 'ChkGroupGaming', 'ChkGroupDesktopUI')) {
        Register-WinWSUiToggleHandler -Name $name -Handler {
            Sync-WinWSUiProfileStateFromControls -State (Get-WinWSUiAppContext).State
            if (Get-Command Sync-WinWSUiWorkstationControlsFromState -ErrorAction SilentlyContinue) {
                Sync-WinWSUiWorkstationControlsFromState -State (Get-WinWSUiAppContext).State
            }
        }
    }
}
