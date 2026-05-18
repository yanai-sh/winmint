#Requires -Version 7.3

function Invoke-WinMintUiStageHostEnterAnimation {
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

function Get-WinMintUiNextDisabledHint {
    $st = Get-WinMintUiAppStateOptional
    if ($null -eq $st) { return $null }
    if (Test-WinMintUiCanAdvanceCurrentStage) { return $null }

    switch ([WinMintUiStage]$st.Stage) {
        ([WinMintUiStage]::Start) { return 'Verify the selected ISO before continuing.' }
        ([WinMintUiStage]::Disk) { return 'Confirm disk erase before continuing.' }
        ([WinMintUiStage]::Profile) {
            $m = Get-WinMintUiProfileValidationMessage -State $st
            if ([string]::IsNullOrWhiteSpace($m)) { return 'Fix identity fields before continuing.' }
            return $m
        }
        default { return 'Complete this step before continuing.' }
    }
}

function Get-WinMintUiElement {
    param([Parameter(Mandatory)][string]$Name)

    $win = Get-WinMintUiAppWindowOptional
    if ($null -eq $win) { return $null }
    return $win.FindName($Name)
}

function Get-WinMintUiElementText {
    param([Parameter(Mandatory)][string]$Name)

    $element = Get-WinMintUiElement -Name $Name
    if ($null -eq $element) { return '' }
    if ($element -is [System.Windows.Controls.PasswordBox] -or $element -is [Wpf.Ui.Controls.PasswordBox]) { return [string]$element.Password }
    try { return [string]$element.Text } catch { return '' }
}

function Set-WinMintUiElementText {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][string]$Text
    )

    $element = Get-WinMintUiElement -Name $Name
    if ($null -eq $element) { return }
    try { $element.Text = [string]$Text } catch {}
}

function Set-WinMintUiElementContent {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][string]$Content
    )

    $element = Get-WinMintUiElement -Name $Name
    if ($null -eq $element) { return }
    try { $element.Content = [string]$Content } catch {}
}

function Get-WinMintUiElementChecked {
    param([Parameter(Mandatory)][string]$Name)

    $element = Get-WinMintUiElement -Name $Name
    if ($null -eq $element) { return $false }
    try { return [bool]$element.IsChecked } catch { return $false }
}

function Set-WinMintUiElementChecked {
    param(
        [Parameter(Mandatory)][string]$Name,
        [bool]$Checked
    )

    $element = Get-WinMintUiElement -Name $Name
    if ($null -eq $element) { return }
    try { $element.IsChecked = $Checked } catch {}
}

function Set-WinMintUiElementEnabled {
    param(
        [Parameter(Mandatory)][string]$Name,
        [bool]$Enabled
    )

    $element = Get-WinMintUiElement -Name $Name
    if ($null -eq $element) { return }
    try { $element.IsEnabled = $Enabled } catch {}
}

function Set-WinMintUiElementVisibility {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][System.Windows.Visibility]$Visibility
    )

    $element = Get-WinMintUiElement -Name $Name
    if ($null -eq $element) { return }
    try { $element.Visibility = $Visibility } catch {}
}

function Set-WinMintUiElementForeground {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()]$Brush
    )

    $element = Get-WinMintUiElement -Name $Name
    if ($null -eq $element -or $null -eq $Brush) { return }
    try { $element.Foreground = $Brush } catch {}
}

function Register-WinMintUiClickHandler {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Handler
    )

    $element = Get-WinMintUiElement -Name $Name
    if ($null -eq $element) { return }
    $routedSource = "Click.$Name"
    $bindingKey = "WinMint:Routed:Click:$Name"
    if (Get-Command Set-WinMintUiRoutedBinding -ErrorAction SilentlyContinue) {
        Set-WinMintUiRoutedBinding -BindingKey $bindingKey -Source $routedSource -Action $Handler
    }
    #region agent log
    try {
        if (Get-Command Write-WinMintUiDebugSessionNdjson -ErrorAction SilentlyContinue) {
            Write-WinMintUiDebugSessionNdjson -HypothesisId 'H1' -Location 'StartStage.ps1:Register-WinMintUiClickHandler' `
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
            if (Get-Command Write-WinMintUiDebugSessionNdjson -ErrorAction SilentlyContinue) {
                Write-WinMintUiDebugSessionNdjson -HypothesisId 'H1' -Location 'StartStage.ps1:click_wrapped' `
                    -Message 'click_invoke' -Data @{ bindingKey = $key } -RunId 'pre'
            }
        } catch {}
        #endregion
        if (Get-Command Invoke-WinMintUiRoutedBinding -ErrorAction SilentlyContinue) {
            $null = Invoke-WinMintUiRoutedBinding -BindingKey $key
        }
    }
    $element.Add_Click($wrapped)
}

function Register-WinMintUiToggleHandler {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Handler
    )

    $element = Get-WinMintUiElement -Name $Name
    if ($null -eq $element) { return }
    $routedSource = "Toggle.$Name"
    $bindingKey = "WinMint:Routed:Toggle:$Name"
    if (Get-Command Set-WinMintUiRoutedBinding -ErrorAction SilentlyContinue) {
        Set-WinMintUiRoutedBinding -BindingKey $bindingKey -Source $routedSource -Action $Handler
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
        if (Get-Command Invoke-WinMintUiRoutedBinding -ErrorAction SilentlyContinue) {
            $null = Invoke-WinMintUiRoutedBinding -BindingKey $key
        }
    }
    $element.Add_Checked($wrapped)
    $element.Add_Unchecked($wrapped)
}

function Register-WinMintUiTextHandler {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Handler
    )

    $element = Get-WinMintUiElement -Name $Name
    if ($null -eq $element) { return }
    $routedSource = "Text.$Name"
    $bindingKey = "WinMint:Routed:Text:$Name"
    if (Get-Command Set-WinMintUiRoutedBinding -ErrorAction SilentlyContinue) {
        Set-WinMintUiRoutedBinding -BindingKey $bindingKey -Source $routedSource -Action $Handler
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
        if (Get-Command Invoke-WinMintUiRoutedBinding -ErrorAction SilentlyContinue) {
            $null = Invoke-WinMintUiRoutedBinding -BindingKey $key
        }
    }
    if ($element -is [System.Windows.Controls.PasswordBox] -or $element -is [Wpf.Ui.Controls.PasswordBox]) {
        $element.Add_PasswordChanged($wrapped)
    } else {
        $element.Add_TextChanged($wrapped)
    }
}

function Update-WinMintUiStateProbe {
    $app = Get-WinMintUiAppContextOptional
    if ($null -eq $app) { return }
    [System.Windows.Automation.AutomationProperties]::SetHelpText(
        $app.Window,
        (Get-WinMintUiStateProbeText -State $app.State))
}

function Update-WinMintUiShell {
    $app = Get-WinMintUiAppContextOptional
    if ($null -eq $app) { return }

    $previousStage = $app.ShellLastStage
    $currentStage = [WinMintUiStage]$app.State.Stage
    $stageHost = Get-WinMintUiElement -Name 'StageHost'
    $shouldFade = $app.ShellTransitionPrimed -and
        $null -ne $previousStage -and
        $previousStage -ne $currentStage
    if ($shouldFade -and $null -ne $stageHost) {
        $stageHost.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
        $stageHost.Opacity = 0.0
    }

    $stageNames = @('Start', 'Machine', 'Disk', 'Profile', 'Workstation', 'Launch')
    foreach ($stageName in $stageNames) {
        $visibility = ($currentStage -eq [WinMintUiStage]::$stageName) ?
            [System.Windows.Visibility]::Visible :
            [System.Windows.Visibility]::Collapsed
        Set-WinMintUiElementVisibility -Name "Stage$stageName" -Visibility $visibility
    }

    # Hide the entire footer bar on the cinematic Start splash
    $footerBar = Get-WinMintUiElement -Name 'FooterBar'
    if ($null -ne $footerBar) {
        $footerBar.Visibility = ($currentStage -eq [WinMintUiStage]::Start) ?
            [System.Windows.Visibility]::Collapsed :
            [System.Windows.Visibility]::Visible
    }
    # Collapse footer row height on splash so it doesn't reserve space
    $footerRowDef = Get-WinMintUiElement -Name 'FooterRowDef'
    if ($null -ne $footerRowDef) {
        $footerRowDef.Height = ($currentStage -eq [WinMintUiStage]::Start) ?
            [System.Windows.GridLength]::new(0) :
            [System.Windows.GridLength]::new(72)
    }

    # Title bar: hide breadcrumb + wordmark on splash, show inside wizard
    $isSplash = $currentStage -eq [WinMintUiStage]::Start
    Set-WinMintUiElementVisibility -Name 'TitleBarBreadcrumb' -Visibility (
        $isSplash ? [System.Windows.Visibility]::Collapsed : [System.Windows.Visibility]::Visible)
    Set-WinMintUiElementVisibility -Name 'TopWordmark' -Visibility (
        $isSplash ? [System.Windows.Visibility]::Collapsed : [System.Windows.Visibility]::Visible)

    Set-WinMintUiElementVisibility -Name 'BtnBack' -Visibility (
        ($currentStage -eq [WinMintUiStage]::Start -or $currentStage -eq [WinMintUiStage]::Machine) ?
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
    Set-WinMintUiElementText -Name 'FooterStageNumber' -Text ([string](([int]$currentStage) + 1))
    Set-WinMintUiElementText -Name 'FooterStageName' -Text ([string]$stageLabels[[string]$currentStage])

    foreach ($stageName in $stageNames) {
        $dot = Get-WinMintUiElement -Name "StepDot$stageName"
        if ($null -ne $dot) {
            $dot.Fill = ($currentStage -eq [WinMintUiStage]::$stageName) ?
                $app.Window.Resources['AccentBrush'] :
                $app.Window.Resources['LineStrongBrush']
        }
        $label = Get-WinMintUiElement -Name "StepLabel$stageName"
        if ($null -ne $label) {
            $label.Foreground = ($currentStage -eq [WinMintUiStage]::$stageName) ?
                $app.Window.Resources['TextPrimaryBrush'] :
                $app.Window.Resources['TextMutedBrush']
        }
    }

    if ($currentStage -eq [WinMintUiStage]::Launch -and
        (Get-Command Sync-WinMintUiLaunchContract -ErrorAction SilentlyContinue)) {
        Sync-WinMintUiLaunchContract -State $app.State
    }

    if ($shouldFade -and $null -ne $stageHost) {
        Invoke-WinMintUiStageHostEnterAnimation -HostElement $stageHost
    }
    $app.ShellLastStage = $currentStage
    $app.ShellTransitionPrimed = $true

    Update-WinMintUiNavigationState
    Update-WinMintUiStateProbe
}

function Set-WinMintUiStageAndRefresh {
    param([Parameter(Mandatory)][WinMintUiStage]$Stage)

    Set-WinMintUiStage -State (Get-WinMintUiAppContext).State -Stage $Stage
    Update-WinMintUiShell
}

function Set-WinMintUiStartStatus {
    param([Parameter(Mandatory)][string]$Message)

    Set-WinMintUiElementText -Name 'TxtIsoStatus' -Text $Message
    Update-WinMintUiStateProbe
}

function Test-WinMintUiCanLeaveStart {
    $st = (Get-WinMintUiAppContext).State
    if ($st.Iso.State -eq [WinMintIsoState]::Verified) { return $true }

    if ([string]::IsNullOrWhiteSpace([string]$st.Iso.Path)) {
        Set-WinMintUiStartStatus -Message 'Select a Windows ISO before continuing.'
    } else {
        Set-WinMintUiStartStatus -Message 'ISO verification is required before continuing.'
    }
    return $false
}

function Test-WinMintUiCanLeaveDisk {
    $st = (Get-WinMintUiAppContext).State
    if ([string]$st.Disk.Mode -ne 'AutoWipeDisk0') { return $true }
    if ([bool]$st.Disk.WipeConfirmed) { return $true }

    Set-WinMintUiElementText -Name 'TxtDiskValidation' -Text 'Confirm erase behavior to continue.'
    Update-WinMintUiStateProbe
    return $false
}

function Get-WinMintUiProfileValidationMessage {
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

function Test-WinMintUiCanLeaveProfile {
    $message = Get-WinMintUiProfileValidationMessage -State (Get-WinMintUiAppContext).State
    Set-WinMintUiElementText -Name 'TxtProfileValidation' -Text $message
    return [string]::IsNullOrWhiteSpace($message)
}

function Test-WinMintUiCanAdvanceCurrentStage {
    $st = Get-WinMintUiAppStateOptional
    if ($null -eq $st) { return $false }

    switch ([WinMintUiStage]$st.Stage) {
        ([WinMintUiStage]::Start) {
            return $st.Iso.State -eq [WinMintIsoState]::Verified
        }
        ([WinMintUiStage]::Disk) {
            return ([string]$st.Disk.Mode -ne 'AutoWipeDisk0') -or
                [bool]$st.Disk.WipeConfirmed
        }
        ([WinMintUiStage]::Profile) {
            return [string]::IsNullOrWhiteSpace(
                (Get-WinMintUiProfileValidationMessage -State $st))
        }
        ([WinMintUiStage]::Launch) { return $false }
        default { return $true }
    }
}

function Update-WinMintUiNavigationState {
    $st = Get-WinMintUiAppStateOptional
    if ($null -eq $st) { return }

    $currentStage = [WinMintUiStage]$st.Stage
    $nextButton = Get-WinMintUiElement -Name 'BtnNext'
    if ($null -ne $nextButton) {
        if ($currentStage -eq [WinMintUiStage]::Launch) {
            $nextButton.IsEnabled = $false
            $nextButton.Visibility = [System.Windows.Visibility]::Collapsed
            $nextButton.ToolTip = $null
        } else {
            $nextButton.Visibility = [System.Windows.Visibility]::Visible
            $canAdvance = Test-WinMintUiCanAdvanceCurrentStage
            $nextButton.IsEnabled = $canAdvance
            $nextButton.Content = if ($currentStage -eq [WinMintUiStage]::Disk -and
                [string]$st.Disk.Mode -eq 'AutoWipeDisk0') {
                [bool]$st.Disk.WipeConfirmed ? 'Arm and continue' : 'Confirm erase behavior'
            } else {
                'Next'
            }
            $nextButton.ToolTip = if ($canAdvance) { $null } else { Get-WinMintUiNextDisabledHint }
        }
    }

    if ($currentStage -eq [WinMintUiStage]::Disk -and
        [string]$st.Disk.Mode -eq 'AutoWipeDisk0' -and
        -not [bool]$st.Disk.WipeConfirmed) {
        Set-WinMintUiElementText -Name 'TxtDiskValidation' -Text 'Confirm erase behavior to continue.'
    } else {
        Set-WinMintUiElementText -Name 'TxtDiskValidation' -Text ''
    }

    if ($currentStage -eq [WinMintUiStage]::Profile) {
        Set-WinMintUiElementText -Name 'TxtProfileValidation' -Text (
            Get-WinMintUiProfileValidationMessage -State $st)
    }
}

function Invoke-WinMintUiNextStage {
    $st = Get-WinMintUiAppStateOptional
    if ($null -eq $st) { return }

    switch ([WinMintUiStage]$st.Stage) {
        ([WinMintUiStage]::Start) {
            if (-not (Test-WinMintUiCanLeaveStart)) { return }
            Set-WinMintUiStageAndRefresh -Stage ([WinMintUiStage]::Machine)
        }
        ([WinMintUiStage]::Machine) {
            Set-WinMintUiStageAndRefresh -Stage ([WinMintUiStage]::Disk)
        }
        ([WinMintUiStage]::Disk) {
            if (-not (Test-WinMintUiCanLeaveDisk)) { return }
            Set-WinMintUiStageAndRefresh -Stage ([WinMintUiStage]::Profile)
        }
        ([WinMintUiStage]::Profile) {
            if (-not (Test-WinMintUiCanLeaveProfile)) { return }
            if (@($st.ProfileGroups) -contains 'Developer' -or @($st.ProfileGroups) -contains 'DesktopUI') {
                Set-WinMintUiStageAndRefresh -Stage ([WinMintUiStage]::Workstation)
            } else {
                Set-WinMintUiStageAndRefresh -Stage ([WinMintUiStage]::Launch)
            }
        }
        ([WinMintUiStage]::Workstation) {
            Set-WinMintUiStageAndRefresh -Stage ([WinMintUiStage]::Launch)
        }
        default {}
    }
}

function Invoke-WinMintUiPreviousStage {
    $st = Get-WinMintUiAppStateOptional
    if ($null -eq $st) { return }

    switch ([WinMintUiStage]$st.Stage) {
        ([WinMintUiStage]::Machine) { Set-WinMintUiStageAndRefresh -Stage ([WinMintUiStage]::Start) }
        ([WinMintUiStage]::Disk) { Set-WinMintUiStageAndRefresh -Stage ([WinMintUiStage]::Machine) }
        ([WinMintUiStage]::Profile) { Set-WinMintUiStageAndRefresh -Stage ([WinMintUiStage]::Disk) }
        ([WinMintUiStage]::Workstation) { Set-WinMintUiStageAndRefresh -Stage ([WinMintUiStage]::Profile) }
        ([WinMintUiStage]::Launch) {
            if (@($st.ProfileGroups) -contains 'Developer' -or @($st.ProfileGroups) -contains 'DesktopUI') {
                Set-WinMintUiStageAndRefresh -Stage ([WinMintUiStage]::Workstation)
            } else {
                Set-WinMintUiStageAndRefresh -Stage ([WinMintUiStage]::Profile)
            }
        }
        default {}
    }
}

function Set-WinMintUiFixtureIsoState {
    param([Parameter(Mandatory)][object]$State)

    $fixtureIso = Join-Path $State.RepositoryRoot 'input\Win11_Base.iso'
    if (-not (Test-Path -LiteralPath $fixtureIso)) {
        $fixtureIso = Join-Path $State.RepositoryRoot 'input\Win11_Base.iso'
    }

    $State.Iso.Path = $fixtureIso
    $State.Iso.Architecture = 'arm64'
    $State.Iso.State = [WinMintIsoState]::Verified
    $State.Iso.Error = ''
    $State.Iso.Editions = @(
        'Windows 11 Home',
        'Windows 11 Pro',
        'Windows 11 Home Single Language'
    )

    Set-WinMintUiElementText -Name 'TxtIsoPath' -Text $State.Iso.Path
    Set-WinMintUiElementText -Name 'TxtIsoStatus' -Text ''
    Set-WinMintUiElementText -Name 'TxtIsoArchitecture' -Text 'ARM64'
    Set-WinMintUiElementText -Name 'TxtIsoEditions' -Text 'Home, Pro, Single Language'

    # Show the metadata pills and morph button to Next
    Set-WinMintUiElementVisibility -Name 'SourceMetaPills' -Visibility ([System.Windows.Visibility]::Visible)
    Set-WinMintUiElementVisibility -Name 'SourceVerifySpinner' -Visibility ([System.Windows.Visibility]::Collapsed)
    Set-WinMintUiElementContent -Name 'BtnBrowseIso' -Content 'Next'
}

function Sync-WinMintUiStartControlsFromState {
    param([Parameter(Mandatory)][object]$State)

    Set-WinMintUiElementText -Name 'TxtIsoPath' -Text $State.Iso.Path

    $isoState = [WinMintIsoState]$State.Iso.State
    $browseBtn = Get-WinMintUiElement -Name 'BtnBrowseIso'
    $spinner = Get-WinMintUiElement -Name 'SourceVerifySpinner'
    $pills = Get-WinMintUiElement -Name 'SourceMetaPills'

    switch ($isoState) {
        ([WinMintIsoState]::Verified) {
            # Show metadata pills
            $architectureText = [string]$State.Iso.Architecture
            if ([string]::IsNullOrWhiteSpace($architectureText)) { $architectureText = 'Unknown' }
            Set-WinMintUiElementText -Name 'TxtIsoArchitecture' -Text $architectureText.ToUpperInvariant()

            $editions = @($State.Iso.Editions)
            $editionText = if ($editions.Count -gt 0) {
                ($editions | ForEach-Object { ([string]$_) -replace '^Windows 11 ', '' }) -join ', '
            } else { 'Detected' }
            Set-WinMintUiElementText -Name 'TxtIsoEditions' -Text $editionText

            if ($null -ne $pills) { $pills.Visibility = [System.Windows.Visibility]::Visible }
            if ($null -ne $spinner) { $spinner.Visibility = [System.Windows.Visibility]::Collapsed }
            Set-WinMintUiElementText -Name 'TxtIsoStatus' -Text ''

            # Morph button to Next
            if ($null -ne $browseBtn) {
                $browseBtn.Content = 'Next'
                $browseBtn.IsEnabled = $true
            }
        }
        ([WinMintIsoState]::Verifying) {
            if ($null -ne $pills) { $pills.Visibility = [System.Windows.Visibility]::Collapsed }
            if ($null -ne $spinner) { $spinner.Visibility = [System.Windows.Visibility]::Visible }
            Set-WinMintUiElementText -Name 'TxtIsoStatus' -Text 'Verifying ISO...'

            if ($null -ne $browseBtn) {
                $browseBtn.Content = 'Verifying...'
                $browseBtn.IsEnabled = $false
            }
        }
        ([WinMintIsoState]::Error) {
            if ($null -ne $pills) { $pills.Visibility = [System.Windows.Visibility]::Collapsed }
            if ($null -ne $spinner) { $spinner.Visibility = [System.Windows.Visibility]::Collapsed }
            $errorText = [string]$State.Iso.Error
            if ([string]::IsNullOrWhiteSpace($errorText)) { $errorText = 'ISO verification failed.' }
            Set-WinMintUiElementText -Name 'TxtIsoStatus' -Text $errorText

            if ($null -ne $browseBtn) {
                $browseBtn.Content = 'Browse ISO'
                $browseBtn.IsEnabled = $true
            }
        }
        default {
            # Idle — initial state
            if ($null -ne $pills) { $pills.Visibility = [System.Windows.Visibility]::Collapsed }
            if ($null -ne $spinner) { $spinner.Visibility = [System.Windows.Visibility]::Collapsed }
            Set-WinMintUiElementText -Name 'TxtIsoStatus' -Text ''

            if ($null -ne $browseBtn) {
                $browseBtn.Content = 'Browse ISO'
                $browseBtn.IsEnabled = $true
            }
        }
    }

    Set-WinMintUiElementText -Name 'TxtIsoArchitectureCaption' -Text ''
    Update-WinMintUiNavigationState
}

function Initialize-WinMintUiStartStage {
    param(
        [Parameter(Mandatory)][object]$State,
        [switch]$FixtureMode
    )

    if ($FixtureMode) {
        Set-WinMintUiFixtureIsoState -State $State
    } else {
        Sync-WinMintUiStartControlsFromState -State $State
    }

    # Dual-purpose click handler: Browse ISO or advance to next stage
    Register-WinMintUiClickHandler -Name 'BtnBrowseIso' -Handler {
        $app = Get-WinMintUiAppContext
        if ($app.State.Iso.State -eq [WinMintIsoState]::Verified) {
            # ISO is verified — act as "Next" button
            Invoke-WinMintUiNextStage
        } else {
            # Not verified — open the browse dialog
            Invoke-WinMintUiBrowseIso -State $app.State -Window $app.Window
        }
    }
}

function Initialize-WinMintUiShell {
    param(
        [System.Management.Automation.Runspaces.Runspace]$HostRunspace = $null
    )

    if ($null -eq $HostRunspace) {
        $HostRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
    }
    Set-WinMintUiHostRunspacePin -Runspace $HostRunspace

    $app = Get-WinMintUiAppContext
    $State = $app.State
    $Window = $app.Window

    Register-WinMintUiClickHandler -Name 'BtnBack' -Handler { Invoke-WinMintUiPreviousStage }
    Register-WinMintUiClickHandler -Name 'BtnNext' -Handler { Invoke-WinMintUiNextStage }

    if (-not $app.ClipboardIsoRegistered) {
        $app.ClipboardIsoRegistered = $true
        $Window.Add_Activated({
            $hr = Get-WinMintUiHostRunspacePin
            if (Get-Command Invoke-WinMintUiWithHostRunspace -ErrorAction SilentlyContinue) {
                Invoke-WinMintUiWithHostRunspace -HostRunspace $hr -Script {
                    $a = Get-WinMintUiAppContext
                    Invoke-WinMintUiClipboardIsoImport -State $a.State -Window $a.Window
                }
            } else {
                $a = Get-WinMintUiAppContext
                Invoke-WinMintUiClipboardIsoImport -State $a.State -Window $a.Window
            }
        })
    }

    Initialize-WinMintUiStartStage -State $State -FixtureMode:$app.FixtureMode
    if (Get-Command Initialize-WinMintUiMachineStage -ErrorAction SilentlyContinue) {
        Initialize-WinMintUiMachineStage -State $State -FixtureMode:$app.FixtureMode
    }
    if (Get-Command Initialize-WinMintUiDiskStage -ErrorAction SilentlyContinue) {
        Initialize-WinMintUiDiskStage -State $State
    }
    if (Get-Command Initialize-WinMintUiProfileStage -ErrorAction SilentlyContinue) {
        Initialize-WinMintUiProfileStage -State $State
    }
    if (Get-Command Initialize-WinMintUiWorkstationStage -ErrorAction SilentlyContinue) {
        Initialize-WinMintUiWorkstationStage -State $State
    }
    if (Get-Command Initialize-WinMintUiLaunchStage -ErrorAction SilentlyContinue) {
        Initialize-WinMintUiLaunchStage
    }

    Update-WinMintUiShell
}
