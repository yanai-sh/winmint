#Requires -Version 7.3

function Invoke-WinWSUiStageHostEnterAnimation {
    param($HostElement)

    if ($null -eq $HostElement) { return }
    try {
        $duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(260))
        $anim = [System.Windows.Media.Animation.DoubleAnimation]::new(0.0, 1.0, $duration)
        $ease = [System.Windows.Media.Animation.CubicEase]::new()
        $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        $anim.EasingFunction = $ease
        $HostElement.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
        $HostElement.Opacity = 0.0
        $HostElement.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $anim)
    } catch {}
}

function Get-WinWSUiNextDisabledHint {
    $st = Get-WinWSUiAppStateOptional
    if ($null -eq $st) { return $null }
    if (Test-WinWSUiCanAdvanceCurrentStage) { return $null }

    switch ([WinWSUiStage]$st.Stage) {
        ([WinWSUiStage]::Start) { return 'Verify the selected ISO before continuing.' }
        ([WinWSUiStage]::Disk) { return 'Confirm disk erase before continuing.' }
        ([WinWSUiStage]::Profile) {
            $m = Get-WinWSUiProfileValidationMessage -State $st
            if ([string]::IsNullOrWhiteSpace($m)) { return 'Fix identity fields before continuing.' }
            return $m
        }
        default { return 'Complete this step before continuing.' }
    }
}

function Get-WinWSUiElement {
    param([Parameter(Mandatory)][string]$Name)

    $win = Get-WinWSUiAppWindowOptional
    if ($null -eq $win) { return $null }
    return $win.FindName($Name)
}

function Get-WinWSUiElementText {
    param([Parameter(Mandatory)][string]$Name)

    $element = Get-WinWSUiElement -Name $Name
    if ($null -eq $element) { return '' }
    if ($element -is [System.Windows.Controls.PasswordBox] -or $element -is [Wpf.Ui.Controls.PasswordBox]) { return [string]$element.Password }
    try { return [string]$element.Text } catch { return '' }
}

function Set-WinWSUiElementText {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][string]$Text
    )

    $element = Get-WinWSUiElement -Name $Name
    if ($null -eq $element) { return }
    try { $element.Text = [string]$Text } catch {}
}

function Set-WinWSUiElementContent {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][string]$Content
    )

    $element = Get-WinWSUiElement -Name $Name
    if ($null -eq $element) { return }
    try { $element.Content = [string]$Content } catch {}
}

function Get-WinWSUiElementChecked {
    param([Parameter(Mandatory)][string]$Name)

    $element = Get-WinWSUiElement -Name $Name
    if ($null -eq $element) { return $false }
    try { return [bool]$element.IsChecked } catch { return $false }
}

function Set-WinWSUiElementChecked {
    param(
        [Parameter(Mandatory)][string]$Name,
        [bool]$Checked
    )

    $element = Get-WinWSUiElement -Name $Name
    if ($null -eq $element) { return }
    try { $element.IsChecked = $Checked } catch {}
}

function Set-WinWSUiElementEnabled {
    param(
        [Parameter(Mandatory)][string]$Name,
        [bool]$Enabled
    )

    $element = Get-WinWSUiElement -Name $Name
    if ($null -eq $element) { return }
    try { $element.IsEnabled = $Enabled } catch {}
}

function Set-WinWSUiElementVisibility {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][System.Windows.Visibility]$Visibility
    )

    $element = Get-WinWSUiElement -Name $Name
    if ($null -eq $element) { return }
    try { $element.Visibility = $Visibility } catch {}
}

function Set-WinWSUiElementForeground {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()]$Brush
    )

    $element = Get-WinWSUiElement -Name $Name
    if ($null -eq $element -or $null -eq $Brush) { return }
    try { $element.Foreground = $Brush } catch {}
}

function Register-WinWSUiClickHandler {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Handler
    )

    $element = Get-WinWSUiElement -Name $Name
    if ($null -eq $element) { return }
    $routedSource = "Click.$Name"
    $bindingKey = "WinWS:Routed:Click:$Name"
    if (Get-Command Set-WinWSUiRoutedBinding -ErrorAction SilentlyContinue) {
        Set-WinWSUiRoutedBinding -BindingKey $bindingKey -Source $routedSource -Action $Handler
    }
    #region agent log
    try {
        if (Get-Command Write-WinWSUiDebugSessionNdjson -ErrorAction SilentlyContinue) {
            Write-WinWSUiDebugSessionNdjson -HypothesisId 'H1' -Location 'StartStage.ps1:Register-WinWSUiClickHandler' `
                -Message 'register_click' -Data @{
                controlName  = $Name
                routedSource = $routedSource
                bindingKey   = $bindingKey
                handlerKind  = if ($Handler -is [scriptblock]) { 'scriptblock' } else { $Handler.GetType().FullName }
            } -RunId 'pre'
        }
    } catch {}
    #endregion
    if ($element -is [System.Windows.FrameworkElement]) {
        try { $element.Tag = $bindingKey } catch {}
    }
    $wrapped = {
        param($clickSender, $e)
        [void]$e
        $key = ''
        if ($null -ne $clickSender -and $clickSender -is [System.Windows.FrameworkElement]) {
            $key = [string]$clickSender.Tag
        }
        #region agent log
        try {
            if (Get-Command Write-WinWSUiDebugSessionNdjson -ErrorAction SilentlyContinue) {
                Write-WinWSUiDebugSessionNdjson -HypothesisId 'H1' -Location 'StartStage.ps1:click_wrapped' `
                    -Message 'click_invoke' -Data @{ bindingKey = $key } -RunId 'pre'
            }
        } catch {}
        #endregion
        if (Get-Command Invoke-WinWSUiRoutedBinding -ErrorAction SilentlyContinue) {
            $null = Invoke-WinWSUiRoutedBinding -BindingKey $key
        }
    }
    $element.Add_Click($wrapped)
}

function Register-WinWSUiToggleHandler {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Handler
    )

    $element = Get-WinWSUiElement -Name $Name
    if ($null -eq $element) { return }
    $routedSource = "Toggle.$Name"
    $bindingKey = "WinWS:Routed:Toggle:$Name"
    if (Get-Command Set-WinWSUiRoutedBinding -ErrorAction SilentlyContinue) {
        Set-WinWSUiRoutedBinding -BindingKey $bindingKey -Source $routedSource -Action $Handler
    }
    if ($element -is [System.Windows.FrameworkElement]) {
        try { $element.Tag = $bindingKey } catch {}
    }
    $wrapped = {
        param($toggleSender, $e)
        [void]$e
        $key = ''
        if ($null -ne $toggleSender -and $toggleSender -is [System.Windows.FrameworkElement]) {
            $key = [string]$toggleSender.Tag
        }
        if (Get-Command Invoke-WinWSUiRoutedBinding -ErrorAction SilentlyContinue) {
            $null = Invoke-WinWSUiRoutedBinding -BindingKey $key
        }
    }
    $element.Add_Checked($wrapped)
    $element.Add_Unchecked($wrapped)
}

function Register-WinWSUiTextHandler {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Handler
    )

    $element = Get-WinWSUiElement -Name $Name
    if ($null -eq $element) { return }
    $routedSource = "Text.$Name"
    $bindingKey = "WinWS:Routed:Text:$Name"
    if (Get-Command Set-WinWSUiRoutedBinding -ErrorAction SilentlyContinue) {
        Set-WinWSUiRoutedBinding -BindingKey $bindingKey -Source $routedSource -Action $Handler
    }
    if ($element -is [System.Windows.FrameworkElement]) {
        try { $element.Tag = $bindingKey } catch {}
    }
    $wrapped = {
        param($textSender, $e)
        [void]$e
        $key = ''
        if ($null -ne $textSender -and $textSender -is [System.Windows.FrameworkElement]) {
            $key = [string]$textSender.Tag
        }
        if (Get-Command Invoke-WinWSUiRoutedBinding -ErrorAction SilentlyContinue) {
            $null = Invoke-WinWSUiRoutedBinding -BindingKey $key
        }
    }
    if ($element -is [System.Windows.Controls.PasswordBox] -or $element -is [Wpf.Ui.Controls.PasswordBox]) {
        $element.Add_PasswordChanged($wrapped)
    } else {
        $element.Add_TextChanged($wrapped)
    }
}

function Update-WinWSUiStateProbe {
    $app = Get-WinWSUiAppContextOptional
    if ($null -eq $app) { return }
    [System.Windows.Automation.AutomationProperties]::SetHelpText(
        $app.Window,
        (Get-WinWSUiStateProbeText -State $app.State))
}

function Update-WinWSUiShell {
    $app = Get-WinWSUiAppContextOptional
    if ($null -eq $app) { return }

    $previousStage = $app.ShellLastStage
    $currentStage = [WinWSUiStage]$app.State.Stage
    $stageHost = Get-WinWSUiElement -Name 'StageHost'
    $shouldFade = $app.ShellTransitionPrimed -and
        $null -ne $previousStage -and
        $previousStage -ne $currentStage
    if ($shouldFade -and $null -ne $stageHost) {
        $stageHost.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
        $stageHost.Opacity = 0.0
    }

    $stageNames = @('Start', 'Machine', 'Disk', 'Profile', 'Workstation', 'Launch')
    foreach ($stageName in $stageNames) {
        $visibility = ($currentStage -eq [WinWSUiStage]::$stageName) ?
            [System.Windows.Visibility]::Visible :
            [System.Windows.Visibility]::Collapsed
        Set-WinWSUiElementVisibility -Name "Stage$stageName" -Visibility $visibility
    }

    # Hide the entire footer bar on the cinematic Start splash
    $footerBar = Get-WinWSUiElement -Name 'FooterBar'
    if ($null -ne $footerBar) {
        $footerBar.Visibility = ($currentStage -eq [WinWSUiStage]::Start) ?
            [System.Windows.Visibility]::Collapsed :
            [System.Windows.Visibility]::Visible
    }
    # Collapse footer row height on splash so it doesn't reserve space
    $footerRowDef = Get-WinWSUiElement -Name 'FooterRowDef'
    if ($null -ne $footerRowDef) {
        $footerRowDef.Height = ($currentStage -eq [WinWSUiStage]::Start) ?
            [System.Windows.GridLength]::new(0) :
            [System.Windows.GridLength]::new(72)
    }

    # Title bar: hide breadcrumb + wordmark on splash, show inside wizard
    $isSplash = $currentStage -eq [WinWSUiStage]::Start
    Set-WinWSUiElementVisibility -Name 'TitleBarBreadcrumb' -Visibility (
        $isSplash ? [System.Windows.Visibility]::Collapsed : [System.Windows.Visibility]::Visible)
    Set-WinWSUiElementVisibility -Name 'TopWordmark' -Visibility (
        $isSplash ? [System.Windows.Visibility]::Collapsed : [System.Windows.Visibility]::Visible)

    Set-WinWSUiElementVisibility -Name 'BtnBack' -Visibility (
        ($currentStage -eq [WinWSUiStage]::Start -or $currentStage -eq [WinWSUiStage]::Machine) ?
        [System.Windows.Visibility]::Collapsed :
        [System.Windows.Visibility]::Visible
    )

    $stageLabels = @{
        Start       = 'Source'
        Machine     = 'Machine'
        Disk        = 'Disk'
        Profile     = 'Identity'
        Workstation = 'Workstation'
        Launch      = 'Launch'
    }
    Set-WinWSUiElementText -Name 'FooterStageNumber' -Text ([string](([int]$currentStage) + 1))
    Set-WinWSUiElementText -Name 'FooterStageName' -Text ([string]$stageLabels[[string]$currentStage])

    foreach ($stageName in $stageNames) {
        $dot = Get-WinWSUiElement -Name "StepDot$stageName"
        if ($null -ne $dot) {
            $dot.Fill = ($currentStage -eq [WinWSUiStage]::$stageName) ?
                $app.Window.Resources['AccentBrush'] :
                $app.Window.Resources['LineStrongBrush']
        }
        $label = Get-WinWSUiElement -Name "StepLabel$stageName"
        if ($null -ne $label) {
            $label.Foreground = ($currentStage -eq [WinWSUiStage]::$stageName) ?
                $app.Window.Resources['TextPrimaryBrush'] :
                $app.Window.Resources['TextMutedBrush']
        }
    }

    if ($currentStage -eq [WinWSUiStage]::Launch -and
        (Get-Command Sync-WinWSUiLaunchContract -ErrorAction SilentlyContinue)) {
        Sync-WinWSUiLaunchContract -State $app.State
    }

    if ($shouldFade -and $null -ne $stageHost) {
        Invoke-WinWSUiStageHostEnterAnimation -HostElement $stageHost
    }
    $app.ShellLastStage = $currentStage
    $app.ShellTransitionPrimed = $true

    Update-WinWSUiNavigationState
    Update-WinWSUiStateProbe
}

function Set-WinWSUiStageAndRefresh {
    param([Parameter(Mandatory)][WinWSUiStage]$Stage)

    Set-WinWSUiStage -State (Get-WinWSUiAppContext).State -Stage $Stage
    Update-WinWSUiShell
}

function Set-WinWSUiStartStatus {
    param([Parameter(Mandatory)][string]$Message)

    Set-WinWSUiElementText -Name 'TxtIsoStatus' -Text $Message
    Update-WinWSUiStateProbe
}

function Test-WinWSUiCanLeaveStart {
    $st = (Get-WinWSUiAppContext).State
    if ($st.Iso.State -eq [WinWSIsoState]::Verified) { return $true }

    if ([string]::IsNullOrWhiteSpace([string]$st.Iso.Path)) {
        Set-WinWSUiStartStatus -Message 'Select a Windows ISO before continuing.'
    } else {
        Set-WinWSUiStartStatus -Message 'ISO verification is required before continuing.'
    }
    return $false
}

function Test-WinWSUiCanLeaveDisk {
    $st = (Get-WinWSUiAppContext).State
    if ([string]$st.Disk.Mode -ne 'AutoWipeDisk0') { return $true }
    if ([bool]$st.Disk.WipeConfirmed) { return $true }

    Set-WinWSUiElementText -Name 'TxtDiskValidation' -Text 'Confirm erase behavior to continue.'
    Update-WinWSUiStateProbe
    return $false
}

function Get-WinWSUiProfileValidationMessage {
    param([Parameter(Mandatory)][object]$State)

    $computerName = [string]$State.Identity.ComputerName
    $accountName = [string]$State.Identity.AccountName
    $password = [string]$State.Identity.Password
    $confirmPassword = [string]$State.Identity.ConfirmPassword

    if ([string]::IsNullOrWhiteSpace($computerName)) {
        return 'Computer name is required.'
    }
    if ($computerName.Length -gt 15 -or $computerName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$') {
        return 'Use a Windows computer name: letters, numbers, hyphen, max 15.'
    }
    if ([string]::IsNullOrWhiteSpace($accountName)) {
        return 'Account name is required.'
    }
    if ($accountName -match '[\\/:*?"<>|@\[\];=,+]') {
        return 'Account name contains a character Windows does not allow.'
    }
    if (-not [string]::IsNullOrEmpty($password) -and $password -ne $confirmPassword) {
        return 'Password confirmation does not match.'
    }
    return ''
}

function Test-WinWSUiCanLeaveProfile {
    $message = Get-WinWSUiProfileValidationMessage -State (Get-WinWSUiAppContext).State
    Set-WinWSUiElementText -Name 'TxtProfileValidation' -Text $message
    return [string]::IsNullOrWhiteSpace($message)
}

function Test-WinWSUiCanAdvanceCurrentStage {
    $st = Get-WinWSUiAppStateOptional
    if ($null -eq $st) { return $false }

    switch ([WinWSUiStage]$st.Stage) {
        ([WinWSUiStage]::Start) {
            return $st.Iso.State -eq [WinWSIsoState]::Verified
        }
        ([WinWSUiStage]::Disk) {
            return ([string]$st.Disk.Mode -ne 'AutoWipeDisk0') -or
                [bool]$st.Disk.WipeConfirmed
        }
        ([WinWSUiStage]::Profile) {
            return [string]::IsNullOrWhiteSpace(
                (Get-WinWSUiProfileValidationMessage -State $st))
        }
        ([WinWSUiStage]::Launch) { return $false }
        default { return $true }
    }
}

function Update-WinWSUiNavigationState {
    $st = Get-WinWSUiAppStateOptional
    if ($null -eq $st) { return }

    $currentStage = [WinWSUiStage]$st.Stage
    $nextButton = Get-WinWSUiElement -Name 'BtnNext'
    if ($null -ne $nextButton) {
        if ($currentStage -eq [WinWSUiStage]::Launch) {
            $nextButton.IsEnabled = $false
            $nextButton.Visibility = [System.Windows.Visibility]::Collapsed
            $nextButton.ToolTip = $null
        } else {
            $nextButton.Visibility = [System.Windows.Visibility]::Visible
            $canAdvance = Test-WinWSUiCanAdvanceCurrentStage
            $nextButton.IsEnabled = $canAdvance
            $nextButton.Content = if ($currentStage -eq [WinWSUiStage]::Disk -and
                [string]$st.Disk.Mode -eq 'AutoWipeDisk0') {
                [bool]$st.Disk.WipeConfirmed ? 'Arm and continue' : 'Confirm erase behavior'
            } else {
                'Next'
            }
            $nextButton.ToolTip = if ($canAdvance) { $null } else { Get-WinWSUiNextDisabledHint }
        }
    }

    if ($currentStage -eq [WinWSUiStage]::Disk -and
        [string]$st.Disk.Mode -eq 'AutoWipeDisk0' -and
        -not [bool]$st.Disk.WipeConfirmed) {
        Set-WinWSUiElementText -Name 'TxtDiskValidation' -Text 'Confirm erase behavior to continue.'
    } else {
        Set-WinWSUiElementText -Name 'TxtDiskValidation' -Text ''
    }

    if ($currentStage -eq [WinWSUiStage]::Profile) {
        Set-WinWSUiElementText -Name 'TxtProfileValidation' -Text (
            Get-WinWSUiProfileValidationMessage -State $st)
    }
}

function Invoke-WinWSUiNextStage {
    $st = Get-WinWSUiAppStateOptional
    if ($null -eq $st) { return }

    switch ([WinWSUiStage]$st.Stage) {
        ([WinWSUiStage]::Start) {
            if (-not (Test-WinWSUiCanLeaveStart)) { return }
            Set-WinWSUiStageAndRefresh -Stage ([WinWSUiStage]::Machine)
        }
        ([WinWSUiStage]::Machine) {
            Set-WinWSUiStageAndRefresh -Stage ([WinWSUiStage]::Disk)
        }
        ([WinWSUiStage]::Disk) {
            if (-not (Test-WinWSUiCanLeaveDisk)) { return }
            Set-WinWSUiStageAndRefresh -Stage ([WinWSUiStage]::Profile)
        }
        ([WinWSUiStage]::Profile) {
            if (-not (Test-WinWSUiCanLeaveProfile)) { return }
            if (@($st.ProfileGroups) -contains 'Developer' -or @($st.ProfileGroups) -contains 'DesktopUI') {
                Set-WinWSUiStageAndRefresh -Stage ([WinWSUiStage]::Workstation)
            } else {
                Set-WinWSUiStageAndRefresh -Stage ([WinWSUiStage]::Launch)
            }
        }
        ([WinWSUiStage]::Workstation) {
            Set-WinWSUiStageAndRefresh -Stage ([WinWSUiStage]::Launch)
        }
        default {}
    }
}

function Invoke-WinWSUiPreviousStage {
    $st = Get-WinWSUiAppStateOptional
    if ($null -eq $st) { return }

    switch ([WinWSUiStage]$st.Stage) {
        ([WinWSUiStage]::Machine) { Set-WinWSUiStageAndRefresh -Stage ([WinWSUiStage]::Start) }
        ([WinWSUiStage]::Disk) { Set-WinWSUiStageAndRefresh -Stage ([WinWSUiStage]::Machine) }
        ([WinWSUiStage]::Profile) { Set-WinWSUiStageAndRefresh -Stage ([WinWSUiStage]::Disk) }
        ([WinWSUiStage]::Workstation) { Set-WinWSUiStageAndRefresh -Stage ([WinWSUiStage]::Profile) }
        ([WinWSUiStage]::Launch) {
            if (@($st.ProfileGroups) -contains 'Developer' -or @($st.ProfileGroups) -contains 'DesktopUI') {
                Set-WinWSUiStageAndRefresh -Stage ([WinWSUiStage]::Workstation)
            } else {
                Set-WinWSUiStageAndRefresh -Stage ([WinWSUiStage]::Profile)
            }
        }
        default {}
    }
}

function Set-WinWSUiFixtureIsoState {
    param([Parameter(Mandatory)][object]$State)

    $fixtureIso = Join-Path $State.RepositoryRoot 'input\Win11_Base.iso'
    if (-not (Test-Path -LiteralPath $fixtureIso)) {
        $fixtureIso = Join-Path $State.RepositoryRoot 'input\Win11_Base.iso'
    }

    $State.Iso.Path = $fixtureIso
    $State.Iso.Architecture = 'arm64'
    $State.Iso.State = [WinWSIsoState]::Verified
    $State.Iso.Error = ''
    $State.Iso.Editions = @(
        'Windows 11 Home',
        'Windows 11 Pro',
        'Windows 11 Home Single Language'
    )

    Set-WinWSUiElementText -Name 'TxtIsoPath' -Text $State.Iso.Path
    Set-WinWSUiElementText -Name 'TxtIsoStatus' -Text ''
    Set-WinWSUiElementText -Name 'TxtIsoArchitecture' -Text 'ARM64'
    Set-WinWSUiElementText -Name 'TxtIsoEditions' -Text 'Home, Pro, Single Language'

    # Show the metadata pills and morph button to Next
    Set-WinWSUiElementVisibility -Name 'SourceMetaPills' -Visibility ([System.Windows.Visibility]::Visible)
    Set-WinWSUiElementVisibility -Name 'SourceVerifySpinner' -Visibility ([System.Windows.Visibility]::Collapsed)
    Set-WinWSUiElementContent -Name 'BtnBrowseIso' -Content 'Next'
}

function Sync-WinWSUiStartControlsFromState {
    param([Parameter(Mandatory)][object]$State)

    Set-WinWSUiElementText -Name 'TxtIsoPath' -Text $State.Iso.Path

    $isoState = [WinWSIsoState]$State.Iso.State
    $browseBtn = Get-WinWSUiElement -Name 'BtnBrowseIso'
    $spinner = Get-WinWSUiElement -Name 'SourceVerifySpinner'
    $pills = Get-WinWSUiElement -Name 'SourceMetaPills'

    switch ($isoState) {
        ([WinWSIsoState]::Verified) {
            # Show metadata pills
            $architectureText = [string]$State.Iso.Architecture
            if ([string]::IsNullOrWhiteSpace($architectureText)) { $architectureText = 'Unknown' }
            Set-WinWSUiElementText -Name 'TxtIsoArchitecture' -Text $architectureText.ToUpperInvariant()

            $editions = @($State.Iso.Editions)
            $editionText = if ($editions.Count -gt 0) {
                ($editions | ForEach-Object { ([string]$_) -replace '^Windows 11 ', '' }) -join ', '
            } else { 'Detected' }
            Set-WinWSUiElementText -Name 'TxtIsoEditions' -Text $editionText

            if ($null -ne $pills) { $pills.Visibility = [System.Windows.Visibility]::Visible }
            if ($null -ne $spinner) { $spinner.Visibility = [System.Windows.Visibility]::Collapsed }
            Set-WinWSUiElementText -Name 'TxtIsoStatus' -Text ''

            # Morph button to Next
            if ($null -ne $browseBtn) {
                $browseBtn.Content = 'Next'
                $browseBtn.IsEnabled = $true
            }
        }
        ([WinWSIsoState]::Verifying) {
            if ($null -ne $pills) { $pills.Visibility = [System.Windows.Visibility]::Collapsed }
            if ($null -ne $spinner) { $spinner.Visibility = [System.Windows.Visibility]::Visible }
            Set-WinWSUiElementText -Name 'TxtIsoStatus' -Text 'Verifying ISO...'

            if ($null -ne $browseBtn) {
                $browseBtn.Content = 'Verifying...'
                $browseBtn.IsEnabled = $false
            }
        }
        ([WinWSIsoState]::Error) {
            if ($null -ne $pills) { $pills.Visibility = [System.Windows.Visibility]::Collapsed }
            if ($null -ne $spinner) { $spinner.Visibility = [System.Windows.Visibility]::Collapsed }
            $errorText = [string]$State.Iso.Error
            if ([string]::IsNullOrWhiteSpace($errorText)) { $errorText = 'ISO verification failed.' }
            Set-WinWSUiElementText -Name 'TxtIsoStatus' -Text $errorText

            if ($null -ne $browseBtn) {
                $browseBtn.Content = 'Browse ISO'
                $browseBtn.IsEnabled = $true
            }
        }
        default {
            # Idle — initial state
            if ($null -ne $pills) { $pills.Visibility = [System.Windows.Visibility]::Collapsed }
            if ($null -ne $spinner) { $spinner.Visibility = [System.Windows.Visibility]::Collapsed }
            Set-WinWSUiElementText -Name 'TxtIsoStatus' -Text ''

            if ($null -ne $browseBtn) {
                $browseBtn.Content = 'Browse ISO'
                $browseBtn.IsEnabled = $true
            }
        }
    }

    Set-WinWSUiElementText -Name 'TxtIsoArchitectureCaption' -Text ''
    Update-WinWSUiNavigationState
}

function Initialize-WinWSUiStartStage {
    param(
        [Parameter(Mandatory)][object]$State,
        [switch]$FixtureMode
    )

    if ($FixtureMode) {
        Set-WinWSUiFixtureIsoState -State $State
    } else {
        Sync-WinWSUiStartControlsFromState -State $State
    }

    # Dual-purpose click handler: Browse ISO or advance to next stage
    Register-WinWSUiClickHandler -Name 'BtnBrowseIso' -Handler {
        $app = Get-WinWSUiAppContext
        if ($app.State.Iso.State -eq [WinWSIsoState]::Verified) {
            # ISO is verified — act as "Next" button
            Invoke-WinWSUiNextStage
        } else {
            # Not verified — open the browse dialog
            Invoke-WinWSUiBrowseIso -State $app.State -Window $app.Window
        }
    }
}

function Initialize-WinWSUiShell {
    param(
        [System.Management.Automation.Runspaces.Runspace]$HostRunspace = $null
    )

    if ($null -eq $HostRunspace) {
        $HostRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
    }
    Set-WinWSUiHostRunspacePin -Runspace $HostRunspace

    $app = Get-WinWSUiAppContext
    $State = $app.State
    $Window = $app.Window

    Register-WinWSUiClickHandler -Name 'BtnBack' -Handler { Invoke-WinWSUiPreviousStage }
    Register-WinWSUiClickHandler -Name 'BtnNext' -Handler { Invoke-WinWSUiNextStage }

    if (-not $app.ClipboardIsoRegistered) {
        $app.ClipboardIsoRegistered = $true
        $Window.Add_Activated({
            $hr = Get-WinWSUiHostRunspacePin
            if (Get-Command Invoke-WinWSUiWithHostRunspace -ErrorAction SilentlyContinue) {
                Invoke-WinWSUiWithHostRunspace -HostRunspace $hr -Script {
                    $a = Get-WinWSUiAppContext
                    Invoke-WinWSUiClipboardIsoImport -State $a.State -Window $a.Window
                }
            } else {
                $a = Get-WinWSUiAppContext
                Invoke-WinWSUiClipboardIsoImport -State $a.State -Window $a.Window
            }
        })
    }

    Initialize-WinWSUiStartStage -State $State -FixtureMode:$app.FixtureMode
    if (Get-Command Initialize-WinWSUiMachineStage -ErrorAction SilentlyContinue) {
        Initialize-WinWSUiMachineStage -State $State -FixtureMode:$app.FixtureMode
    }
    if (Get-Command Initialize-WinWSUiDiskStage -ErrorAction SilentlyContinue) {
        Initialize-WinWSUiDiskStage -State $State
    }
    if (Get-Command Initialize-WinWSUiProfileStage -ErrorAction SilentlyContinue) {
        Initialize-WinWSUiProfileStage -State $State
    }
    if (Get-Command Initialize-WinWSUiWorkstationStage -ErrorAction SilentlyContinue) {
        Initialize-WinWSUiWorkstationStage -State $State
    }
    if (Get-Command Initialize-WinWSUiLaunchStage -ErrorAction SilentlyContinue) {
        Initialize-WinWSUiLaunchStage
    }

    Update-WinWSUiShell
}
