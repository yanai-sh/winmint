#Requires -Version 7.3

function Set-WinMintUiLaunchStatus {
    param([Parameter(Mandatory)][string]$Message)

    Set-WinMintUiElementText -Name 'BuildStatusText' -Text $Message
    Update-WinMintUiStateProbe
}

function Add-WinMintUiLaunchLog {
    param([Parameter(Mandatory)][string]$Message)

    $panel = Get-WinMintUiElement -Name 'LogPanel'
    if ($null -eq $panel) { return }

    $textBlock = [System.Windows.Controls.TextBlock]::new()
    $textBlock.Text = $Message
    $textBlock.FontSize = 12
    $textBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
    try { $textBlock.Foreground = (Get-WinMintUiAppContext).Window.Resources['TextSecondaryBrush'] } catch {}
    $panel.Children.Add($textBlock) | Out-Null

    $maxLogLines = 400
    while ($panel.Children.Count -gt $maxLogLines) {
        $panel.Children.RemoveAt(0) | Out-Null
    }
}

function Set-WinMintUiContractSection {
    param(
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][object]$Summary
    )

    Set-WinMintUiElementText -Name "Contract$Prefix`Primary" -Text $Summary.Primary
    Set-WinMintUiElementText -Name "Contract$Prefix`Secondary" -Text $Summary.Secondary
    Set-WinMintUiElementText -Name "Contract$Prefix`Meta" -Text $Summary.Meta

    $panel = Get-WinMintUiElement -Name "Contract$Prefix`Panel"
    if ($null -ne $panel) {
        $win = (Get-WinMintUiAppContext).Window
        $panel.BorderBrush = [bool]$Summary.IsDanger ?
            $win.Resources['DangerBrush'] :
            $win.Resources['LineBrush']
        $panel.Background = [bool]$Summary.IsDanger ?
            $win.Resources['DangerSoftBrush'] :
            $win.Resources['PanelBrush']
    }
}

function Sync-WinMintUiLaunchContract {
    param([Parameter(Mandatory)][object]$State)

    $contract = Get-WinMintUiLaunchContractSummary -State $State
    Set-WinMintUiContractSection -Prefix 'Source' -Summary $contract.Source
    Set-WinMintUiContractSection -Prefix 'Target' -Summary $contract.Target
    Set-WinMintUiContractSection -Prefix 'Disk' -Summary $contract.Disk
    Set-WinMintUiContractSection -Prefix 'Identity' -Summary $contract.Identity
    Set-WinMintUiContractSection -Prefix 'Workstation' -Summary $contract.Workstation
    Set-WinMintUiContractSection -Prefix 'Output' -Summary $contract.Output

    $action = Get-WinMintUiElement -Name 'BtnStartBuild'
    if ($null -ne $action) {
        if ((Get-WinMintUiAppContext).DryRun) {
            $action.Content = 'Save profile'
            $action.IsEnabled = $true
        } else {
            $action.Content = 'Build ISO'
            $action.IsEnabled = $true
        }
    }
}

function Invoke-WinMintUiBuildFromLaunch {
    $app = Get-WinMintUiAppContextOptional
    if ($null -eq $app) { return }

    try {
        $app.State.Build.IsRunning = $true
        Set-WinMintUiLaunchStatus -Message 'Starting build…'
        Set-WinMintUiElementVisibility -Name 'LaunchContractPanel' -Visibility ([System.Windows.Visibility]::Collapsed)
        Set-WinMintUiElementVisibility -Name 'LaunchProgressPanel' -Visibility ([System.Windows.Visibility]::Visible)
        Start-WinMintUiBuild -State $app.State -Window $app.Window -DryRun:$app.DryRun
    } catch {
        $app.State.Build.IsRunning = $false
        $message = 'Build runner is not wired yet.'
        if (-not [string]::IsNullOrWhiteSpace([string]$_.Exception.Message)) {
            $message = [string]$_.Exception.Message
        }
        Set-WinMintUiLaunchStatus -Message $message
        Add-WinMintUiLaunchLog -Message $message
    }
}

function Initialize-WinMintUiLaunchStage {
    $State = (Get-WinMintUiAppContext).State

    Set-WinMintUiLaunchStatus -Message 'Review the build contract.'
    Sync-WinMintUiLaunchContract -State $State
    Register-WinMintUiClickHandler -Name 'BtnStartBuild' -Handler {
        Invoke-WinMintUiBuildFromLaunch
    }
}
