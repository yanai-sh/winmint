#Requires -Version 7.3

function Set-WinWSUiLaunchStatus {
    param([Parameter(Mandatory)][string]$Message)

    Set-WinWSUiElementText -Name 'BuildStatusText' -Text $Message
    Update-WinWSUiStateProbe
}

function Add-WinWSUiLaunchLog {
    param([Parameter(Mandatory)][string]$Message)

    $panel = Get-WinWSUiElement -Name 'LogPanel'
    if ($null -eq $panel) { return }

    $textBlock = [System.Windows.Controls.TextBlock]::new()
    $textBlock.Text = $Message
    $textBlock.FontSize = 12
    $textBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
    try { $textBlock.Foreground = (Get-WinWSUiAppContext).Window.Resources['TextSecondaryBrush'] } catch {}
    $panel.Children.Add($textBlock) | Out-Null

    $maxLogLines = 400
    while ($panel.Children.Count -gt $maxLogLines) {
        $panel.Children.RemoveAt(0) | Out-Null
    }
}

function Set-WinWSUiContractSection {
    param(
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][object]$Summary
    )

    Set-WinWSUiElementText -Name "Contract$Prefix`Primary" -Text $Summary.Primary
    Set-WinWSUiElementText -Name "Contract$Prefix`Secondary" -Text $Summary.Secondary
    Set-WinWSUiElementText -Name "Contract$Prefix`Meta" -Text $Summary.Meta

    $panel = Get-WinWSUiElement -Name "Contract$Prefix`Panel"
    if ($null -ne $panel) {
        $win = (Get-WinWSUiAppContext).Window
        $panel.BorderBrush = [bool]$Summary.IsDanger ?
            $win.Resources['DangerBrush'] :
            $win.Resources['LineBrush']
        $panel.Background = [bool]$Summary.IsDanger ?
            $win.Resources['DangerSoftBrush'] :
            $win.Resources['PanelBrush']
    }
}

function Sync-WinWSUiLaunchContract {
    param([Parameter(Mandatory)][object]$State)

    $contract = Get-WinWSUiLaunchContractSummary -State $State
    Set-WinWSUiContractSection -Prefix 'Source' -Summary $contract.Source
    Set-WinWSUiContractSection -Prefix 'Target' -Summary $contract.Target
    Set-WinWSUiContractSection -Prefix 'Disk' -Summary $contract.Disk
    Set-WinWSUiContractSection -Prefix 'Identity' -Summary $contract.Identity
    Set-WinWSUiContractSection -Prefix 'Workstation' -Summary $contract.Workstation
    Set-WinWSUiContractSection -Prefix 'Output' -Summary $contract.Output

    $action = Get-WinWSUiElement -Name 'BtnStartBuild'
    if ($null -ne $action) {
        if ((Get-WinWSUiAppContext).DryRun) {
            $action.Content = 'Save profile'
            $action.IsEnabled = $true
        } else {
            $action.Content = 'Build ISO'
            $action.IsEnabled = $true
        }
    }
}

function Invoke-WinWSUiBuildFromLaunch {
    $app = Get-WinWSUiAppContextOptional
    if ($null -eq $app) { return }

    try {
        $app.State.Build.IsRunning = $true
        Set-WinWSUiLaunchStatus -Message 'Starting build…'
        Set-WinWSUiElementVisibility -Name 'LaunchContractPanel' -Visibility ([System.Windows.Visibility]::Collapsed)
        Set-WinWSUiElementVisibility -Name 'LaunchProgressPanel' -Visibility ([System.Windows.Visibility]::Visible)
        Start-WinWSUiBuild -State $app.State -Window $app.Window -DryRun:$app.DryRun
    } catch {
        $app.State.Build.IsRunning = $false
        $message = 'Build runner is not wired yet.'
        if (-not [string]::IsNullOrWhiteSpace([string]$_.Exception.Message)) {
            $message = [string]$_.Exception.Message
        }
        Set-WinWSUiLaunchStatus -Message $message
        Add-WinWSUiLaunchLog -Message $message
    }
}

function Initialize-WinWSUiLaunchStage {
    $State = (Get-WinWSUiAppContext).State

    Set-WinWSUiLaunchStatus -Message 'Review the build contract.'
    Sync-WinWSUiLaunchContract -State $State
    Register-WinWSUiClickHandler -Name 'BtnStartBuild' -Handler {
        Invoke-WinWSUiBuildFromLaunch
    }
}
