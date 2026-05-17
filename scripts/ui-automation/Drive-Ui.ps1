#Requires -Version 7.3
<#
<summary>
    Drive-Ui.ps1 — programmatic UI automation for the running WinWS WPF wizard.

    Subagents and humans invoke this to click controls, set text, navigate
    pages, set the ISO via the clipboard auto-detect path, and snapshot the
    window. All control identifiers are WPF `x:Name` values (which WPF
    auto-publishes as UI Automation `AutomationId`).

    The target window is discovered via UI Automation by title match
    ('WinMint' by default). UIA invocation requires the driver process to
    run at the same integrity level as the target window. Since WinMint-UI.ps1
    auto-elevates via UAC, run this script from an admin shell as well.

    Verbs:
        -Action Click       -Name <id>
        -Action SetText     -Name <id> -Value <string>
        -Action SetCheck    -Name <id> -Value true|false
        -Action GetText     -Name <id>
        -Action GetState    -Name <id>          # JSON: visible, enabled, checked
        -Action ListControls                    # JSON dump of all addressable elements
        -Action Next                            # click BtnNext, wait for transition
        -Action Back                            # click BtnBack, wait for transition
        -Action GoToPage    -Page <0-5>         # walk forward to target page
        -Action SetIso      -Path <iso path>    # uses Window.Activated clipboard listener
        -Action GetWindowInfo                   # JSON: hwnd, title, page
        -Action Snapshot    [-Label <text>] [-IncludePng]  # semantic JSON under output/ui-snapshots/; -IncludePng adds PNG via Capture-UiScreenshot.ps1

    Output: each invocation prints a single JSON object describing the result,
    so subagents can parse with ConvertFrom-Json or jq. Errors exit non-zero.

    Examples:
        pwsh scripts\ui-automation\Drive-Ui.ps1 -Action Click -Name BtnNext
        pwsh scripts\ui-automation\Drive-Ui.ps1 -Action SetText -Name TxtComputerName -Value 'test-pc'
        pwsh scripts\ui-automation\Drive-Ui.ps1 -Action SetCheck -Name ChkDiskWipeConfirm -Value true
        pwsh scripts\ui-automation\Drive-Ui.ps1 -Action SetIso -Path 'C:\path\Win11_Base.iso'
        pwsh scripts\ui-automation\Drive-Ui.ps1 -Action GoToPage -Page 3
        pwsh scripts\ui-automation\Drive-Ui.ps1 -Action Snapshot -Label page3-desktop
        pwsh scripts\ui-automation\Drive-Ui.ps1 -Action Snapshot -Label visual-regression -IncludePng
        pwsh scripts\ui-automation\Drive-Ui.ps1 -Action ListControls | ConvertFrom-Json | Where-Object Type -eq Button
</summary>
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Click', 'SetText', 'SetCheck', 'GetText', 'GetState',
                 'ListControls', 'Next', 'Back', 'GoToPage', 'SetIso', 'SetDriver',
                 'SetDriverFixture', 'GetUiState', 'GetCurrentPage', 'GetWindowInfo', 'Snapshot')]
    [string]$Action,

    [string]$Name,
    [string]$Value,
    [string]$Path,
    [int]$Page = -1,
    [string]$Label,
    [int]$WaitMs = 350,
    [string]$WindowTitle = 'WinMint',
    [Int64]$Hwnd = 0,

    # With -Action Snapshot: also capture a PNG (slower; semantic JSON is always written).
    [switch]$IncludePng
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName PresentationCore

if (-not ('WinWS.UiDriveNative' -as [Type])) {
    Add-Type -Namespace WinWS -Name UiDriveNative -MemberDefinition @'
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(System.IntPtr hWnd);

        [System.Runtime.InteropServices.DllImport("kernel32.dll")]
        public static extern System.IntPtr GetConsoleWindow();
'@
}

$AE   = [System.Windows.Automation.AutomationElement]
$Cond = [System.Windows.Automation.PropertyCondition]
$Tree = [System.Windows.Automation.TreeScope]
$Prop = [System.Windows.Automation.AutomationElement]

. (Join-Path (Split-Path -Parent $PSCommandPath) 'Drive-Ui.AuditHelpers.ps1')

function Write-Result {
    param([hashtable]$Body)
    $Body['ok'] = $true
    ConvertTo-Json $Body -Depth 6 -Compress
}

function Write-Failure {
    param([string]$Message, [hashtable]$Extra = @{})
    $Extra['ok']    = $false
    $Extra['error'] = $Message
    ConvertTo-Json $Extra -Depth 6 -Compress
    exit 1
}

function Find-WindowElement {
    param([string]$Title)
    $cond = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window),
        [System.Windows.Automation.PropertyCondition]::new($AE::IsContentElementProperty, $true)
    )
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        $candidates = $AE::RootElement.FindAll($Tree::Children, $cond)
        foreach ($c in $candidates) {
            try {
                $name = $c.Current.Name
                if ($name -and $name.IndexOf($Title, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    return $c
                }
            } catch { continue }
        }
        Start-Sleep -Milliseconds 200
    }
    Write-Failure "No visible window with title containing '$Title' found within 5s. Open WinMint-UI.ps1 first."
}

function Resolve-WindowElement {
    param(
        [string]$Title,
        [Int64]$Handle
    )

    if ($Handle -ne 0) {
        try {
            $element = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Handle)
            if ($null -ne $element) { return $element }
        } catch {}
        Write-Failure "Window handle 0x$('{0:X}' -f $Handle) was not accessible."
    }

    return Find-WindowElement -Title $Title
}

function Find-ByAutomationId {
    param([System.Windows.Automation.AutomationElement]$Root, [string]$AutomationId)
    if ([string]::IsNullOrWhiteSpace($AutomationId)) {
        Write-Failure "-Name is required for action '$Action'."
    }
    $cond = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, $AutomationId)
    $el = $Root.FindFirst($Tree::Descendants, $cond)
    if ($null -eq $el) {
        Write-Failure "No element with AutomationId='$AutomationId' under window."
    }
    return $el
}

function Invoke-Click {
    param([System.Windows.Automation.AutomationElement]$Element)
    $invokeP = [System.Windows.Automation.InvokePattern]::Pattern
    $togP    = [System.Windows.Automation.TogglePattern]::Pattern
    $selP    = [System.Windows.Automation.SelectionItemPattern]::Pattern
    $box = $null
    if ($Element.TryGetCurrentPattern($invokeP, [ref]$box))      { $box.Invoke();          return 'Invoke' }
    if ($Element.TryGetCurrentPattern($selP,    [ref]$box))      { $box.Select();          return 'Select' }
    if ($Element.TryGetCurrentPattern($togP,    [ref]$box))      { $box.Toggle();          return 'Toggle' }
    Write-Failure "Element '$($Element.Current.AutomationId)' supports no clickable pattern."
}

function Set-ElementText {
    param([System.Windows.Automation.AutomationElement]$Element, [string]$Text)
    $valP = [System.Windows.Automation.ValuePattern]::Pattern
    $box = $null
    if ($Element.TryGetCurrentPattern($valP, [ref]$box)) {
        if ($box.Current.IsReadOnly) {
            Write-Failure "Element '$($Element.Current.AutomationId)' is read-only."
        }
        $box.SetValue($Text)
        return
    }
    # Fallback: focus + clipboard paste for PasswordBox / controls without ValuePattern.
    $Element.SetFocus()
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    Start-Sleep -Milliseconds 30
    [System.Windows.Forms.Clipboard]::SetText($Text)
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    Start-Sleep -Milliseconds 60
}

function Set-ElementCheck {
    param([System.Windows.Automation.AutomationElement]$Element, [bool]$ShouldCheck)
    $togP = [System.Windows.Automation.TogglePattern]::Pattern
    $box  = $null
    if (-not $Element.TryGetCurrentPattern($togP, [ref]$box)) {
        Write-Failure "Element '$($Element.Current.AutomationId)' does not support Toggle (not a checkbox / togglable)."
    }
    $current = ($box.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On)
    if ($current -ne $ShouldCheck) { $box.Toggle() }
}

function Get-ElementText {
    param([System.Windows.Automation.AutomationElement]$Element)
    $valP = [System.Windows.Automation.ValuePattern]::Pattern
    $textP = [System.Windows.Automation.TextPattern]::Pattern
    $box = $null
    if ($Element.TryGetCurrentPattern($valP, [ref]$box))  { return [string]$box.Current.Value }
    if ($Element.TryGetCurrentPattern($textP, [ref]$box)) { return $box.DocumentRange.GetText(2048) }
    return [string]$Element.Current.Name
}

function Get-ElementState {
    param([System.Windows.Automation.AutomationElement]$Element)
    $togP = [System.Windows.Automation.TogglePattern]::Pattern
    $checked = $null
    $box = $null
    if ($Element.TryGetCurrentPattern($togP, [ref]$box)) {
        $checked = ($box.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On)
    }
    return @{
        automationId = [string]$Element.Current.AutomationId
        controlType  = [string]$Element.Current.ControlType.LocalizedControlType
        name         = [string]$Element.Current.Name
        enabled      = [bool]$Element.Current.IsEnabled
        offscreen    = [bool]$Element.Current.IsOffscreen
        checked      = $checked
    }
}

function Resolve-RepoRoot {
    Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
}

function Get-UiStateProbe {
    param([System.Windows.Automation.AutomationElement]$Window)
    # The wizard stamps state into AutomationProperties.HelpText on the Window
    # root via Update-UiStateProbe (Set-Page + window-load init).
    $text = $null
    try { $text = $Window.Current.HelpText } catch { $text = $null }
    $state = @{ page=-1; isoVerified=$false; driverSource='None'; driverPathSet=$false; raw=([string]$text) }
    if ([string]::IsNullOrWhiteSpace($text)) { return $state }
    if ($text -match 'page=(-?\d+)')             { $state['page']        = [int]$matches[1] }
    if ($text -match 'isoVerified=(true|false)') { $state['isoVerified'] = ($matches[1] -eq 'true') }
    if ($text -match 'driverSource=(\w+)')       { $state['driverSource']= $matches[1] }
    if ($text -match 'driverPathSet=(true|false)') { $state['driverPathSet'] = ($matches[1] -eq 'true') }
    return $state
}

function Get-UiAutomationControlInventory {
    param([System.Windows.Automation.AutomationElement]$Window)

    $items = [System.Collections.Generic.List[hashtable]]::new()
    $all = $Window.FindAll($Tree::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($el in $all) {
        try {
            $aid = [string]$el.Current.AutomationId
            if ([string]::IsNullOrWhiteSpace($aid)) { continue }
            $items.Add(@{
                automationId = $aid
                controlType  = [string]$el.Current.ControlType.LocalizedControlType
                name         = [string]$el.Current.Name
                enabled      = [bool]$el.Current.IsEnabled
                offscreen    = [bool]$el.Current.IsOffscreen
                focusable    = [bool]$el.Current.IsKeyboardFocusable
                bounds       = Get-ElementBounds -Element $el
                patterns     = @(Get-SupportedPatternNames -Element $el)
                text         = [string](Get-ElementText -Element $el)
            })
        } catch { continue }
    }
    return $items
}

function Resolve-DefaultInputFile {
    param([string]$Pattern)
    $repoRoot = Resolve-RepoRoot
    $inputDir = Join-Path $repoRoot 'input'
    if (-not (Test-Path -LiteralPath $inputDir)) { return $null }
    $files = @(Get-ChildItem -LiteralPath $inputDir -Filter $Pattern -File -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { return $null }
    return $files[0].FullName
}

function Invoke-FileDropActivation {
    <# <summary>Feeds a file path through the same clipboard file-drop path a
    user gets by copying a file in Explorer and activating WinWS. This avoids
    modal file pickers during unattended audits while still exercising the UI's
    Window.Activated auto-detect handler.</summary> #>
    param(
        [Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Window,
        [Parameter(Mandatory)][string]$Path
    )

    $col = [System.Collections.Specialized.StringCollection]::new()
    $null = $col.Add($Path)
    [System.Windows.Forms.Clipboard]::SetFileDropList($col)

    # Force a real activation edge. SetFocus alone is not enough when the WinWS
    # window is already foreground, and then the WPF Activated handler will not
    # run. Bounce focus to this driver console, then foreground the target.
    $console = [WinWS.UiDriveNative]::GetConsoleWindow()
    if ($console -ne [IntPtr]::Zero) {
        [WinWS.UiDriveNative]::SetForegroundWindow($console) | Out-Null
        Start-Sleep -Milliseconds 150
    }

    $hwnd = [IntPtr]$Window.Current.NativeWindowHandle
    if ($hwnd -ne [IntPtr]::Zero) {
        [WinWS.UiDriveNative]::SetForegroundWindow($hwnd) | Out-Null
    }
    try { $Window.SetFocus() } catch {}
    Start-Sleep -Milliseconds 500
}

# Resolve target window for every verb that touches the UI. Fixture automation
# can pass the exact HWND so background captures do not depend on z-order.
$window = Resolve-WindowElement -Title $WindowTitle -Handle $Hwnd

switch ($Action) {

    'Click' {
        $el = Find-ByAutomationId -Root $window -AutomationId $Name
        $pattern = Invoke-Click -Element $el
        Start-Sleep -Milliseconds $WaitMs
        Write-Result @{ action='Click'; name=$Name; pattern=$pattern }
    }

    'SetText' {
        $el = Find-ByAutomationId -Root $window -AutomationId $Name
        Set-ElementText -Element $el -Text $Value
        Write-Result @{ action='SetText'; name=$Name; value=$Value }
    }

    'SetCheck' {
        $bool = ($Value -ieq 'true' -or $Value -eq '1')
        $el = Find-ByAutomationId -Root $window -AutomationId $Name
        Set-ElementCheck -Element $el -ShouldCheck $bool
        Write-Result @{ action='SetCheck'; name=$Name; value=$bool }
    }

    'GetText' {
        $el = Find-ByAutomationId -Root $window -AutomationId $Name
        Write-Result @{ action='GetText'; name=$Name; text=(Get-ElementText -Element $el) }
    }

    'GetState' {
        $el = Find-ByAutomationId -Root $window -AutomationId $Name
        $state = Get-ElementState -Element $el
        $state['action'] = 'GetState'
        Write-Result $state
    }

    'ListControls' {
        $items = Get-UiAutomationControlInventory -Window $window
        ConvertTo-Json $items -Depth 8 -Compress
    }

    'Next' {
        # On page 0 the footer is hidden; use the splash's dual-purpose button
        $current = (Get-UiStateProbe -Window $window)['page']
        $btnId = if ($current -eq 0) { 'BtnBrowseIso' } else { 'BtnNext' }
        $el = Find-ByAutomationId -Root $window -AutomationId $btnId
        $null = Invoke-Click -Element $el
        Start-Sleep -Milliseconds $WaitMs
        Write-Result @{ action='Next' }
    }

    'Back' {
        $el = Find-ByAutomationId -Root $window -AutomationId 'BtnBack'
        $null = Invoke-Click -Element $el
        Start-Sleep -Milliseconds $WaitMs
        Write-Result @{ action='Back' }
    }

    'GoToPage' {
        if ($Page -lt 0 -or $Page -gt 5) {
            Write-Failure "-Page must be between 0 and 5."
        }
        # Read current page from the UiStateProbe and click Next/Back the right
        # number of times in the right direction. If validation blocks (BtnNext
        # disabled), we stop early and report what page we actually reached.
        # On page 0, the footer is hidden; use the splash's BtnBrowseIso instead.
        $hops = 0
        $current = (Get-UiStateProbe -Window $window)['page']
        while ($current -ne $Page -and $hops -lt 20) {
            if ($Page -gt $current) {
                # Advancing: on page 0, use the splash button; otherwise footer Next
                $btnId = if ($current -eq 0) { 'BtnBrowseIso' } else { 'BtnNext' }
            } else {
                $btnId = 'BtnBack'
            }
            $el = Find-ByAutomationId -Root $window -AutomationId $btnId
            if (-not $el.Current.IsEnabled) { break }
            $null = Invoke-Click -Element $el
            Start-Sleep -Milliseconds $WaitMs
            $hops++
            $next = (Get-UiStateProbe -Window $window)['page']
            if ($next -eq $current) { break }   # navigation blocked
            $current = $next
        }
        Write-Result @{ action='GoToPage'; requested=$Page; reached=$current; hops=$hops }
    }

    'SetIso' {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            $Path = Resolve-DefaultInputFile -Pattern '*.iso'
            if ([string]::IsNullOrWhiteSpace($Path)) {
                Write-Failure "No -Path given and no *.iso found in input/."
            }
        }
        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Failure "ISO not found: $Path"
        }
        $absPath = (Resolve-Path -LiteralPath $Path).Path

        Invoke-FileDropActivation -Window $window -Path $absPath
        Start-Sleep -Milliseconds 500
        Write-Result @{ action='SetIso'; path=$absPath }
    }

    'SetDriver' {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            $Path = Resolve-DefaultInputFile -Pattern '*.msi'
            if ([string]::IsNullOrWhiteSpace($Path)) {
                Write-Failure "No -Path given and no *.msi found in input/."
            }
        }
        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Failure "Driver file not found: $Path"
        }
        $absPath = (Resolve-Path -LiteralPath $Path).Path
        $custom = Find-ByAutomationId -Root $window -AutomationId 'RbDriverCustom'
        $null = Invoke-Click -Element $custom
        Start-Sleep -Milliseconds 250
        $pathField = Find-ByAutomationId -Root $window -AutomationId 'TxtDriverPath'
        Set-ElementText -Element $pathField -Text $absPath
        Start-Sleep -Milliseconds 500

        $state = Get-UiStateProbe -Window $window
        if ([string]$state['driverSource'] -ne 'Custom') {
            Write-Failure "Driver picker did not switch the UI to Custom." @{ path=$absPath; driverSource=$state['driverSource'] }
        }
        if (-not [bool]$state['driverPathSet']) {
            Write-Failure "Driver picker did not populate the selected path." @{ path=$absPath; driverSource=$state['driverSource']; driverPathSet=$state['driverPathSet'] }
        }
        Write-Result @{ action='SetDriver'; path=$absPath; driverSource=$state['driverSource']; driverPathSet=$state['driverPathSet'] }
    }

    'SetDriverFixture' {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            $Path = Resolve-DefaultInputFile -Pattern '*.msi'
            if ([string]::IsNullOrWhiteSpace($Path)) {
                Write-Failure "No -Path given and no *.msi found in input/."
            }
        }
        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Failure "Driver file not found: $Path"
        }
        $absPath = (Resolve-Path -LiteralPath $Path).Path
        $custom = Find-ByAutomationId -Root $window -AutomationId 'RbDriverCustom'
        $null = Invoke-Click -Element $custom
        $pathField = Find-ByAutomationId -Root $window -AutomationId 'TxtDriverPath'
        Set-ElementText -Element $pathField -Text $absPath
        Start-Sleep -Milliseconds 500
        $state = Get-UiStateProbe -Window $window
        if ([string]$state['driverSource'] -ne 'Custom') {
            Write-Failure "Fixture driver selection did not switch the UI to Custom." @{ path=$absPath; driverSource=$state['driverSource'] }
        }
        if (-not [bool]$state['driverPathSet']) {
            Write-Failure "Fixture driver selection did not populate TxtDriverPath." @{ path=$absPath; driverSource=$state['driverSource']; driverPathSet=$state['driverPathSet'] }
        }
        Write-Result @{ action='SetDriverFixture'; path=$absPath; driverSource=$state['driverSource']; driverPathSet=$state['driverPathSet'] }
    }

    'GetUiState' {
        $state = Get-UiStateProbe -Window $window
        $state['action'] = 'GetUiState'
        Write-Result $state
    }

    'GetCurrentPage' {
        $state = Get-UiStateProbe -Window $window
        Write-Result @{ action='GetCurrentPage'; page=$state['page'] }
    }

    'GetWindowInfo' {
        $state = Get-UiStateProbe -Window $window
        Write-Result @{
            action='GetWindowInfo'
            hwnd=[int64]$window.Current.NativeWindowHandle
            title=[string]$window.Current.Name
            page=$state['page']
            isoVerified=$state['isoVerified']
            driverSource=$state['driverSource']
        }
    }

    'Snapshot' {
        $repoRoot = Resolve-RepoRoot
        if ([string]::IsNullOrWhiteSpace($Label)) {
            $slug = 'snap-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
        } else {
            $slug = ($Label -replace '[^\w\-.]+', '_').Trim('_')
            if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'snap' }
        }

        $snapDir = Join-Path $repoRoot 'output\ui-snapshots'
        $null = New-Item -ItemType Directory -Path $snapDir -Force -ErrorAction SilentlyContinue

        $probe = Get-UiStateProbe -Window $window
        $inventory = @(Get-UiAutomationControlInventory -Window $window)
        $bundle = [ordered]@{
            schemaVersion = 1
            kind            = 'WinWS.UiAutomationSnapshot'
            capturedAt      = [DateTimeOffset]::Now.ToString('o')
            label           = [string]$Label
            window          = @{
                hwnd  = [int64]$window.Current.NativeWindowHandle
                title = [string]$window.Current.Name
            }
            probe           = $probe
            controls        = $inventory
        }

        $jsonPath = Join-Path $snapDir "$slug.json"
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        $jsonText = ($bundle | ConvertTo-Json -Depth 14)
        [System.IO.File]::WriteAllText($jsonPath, $jsonText + [Environment]::NewLine, $utf8NoBom)

        $out = [ordered]@{
            action   = 'Snapshot'
            semantic = $jsonPath
            label    = $slug
            page     = [int]$probe['page']
        }

        if ($IncludePng) {
            $captureScript = Join-Path $repoRoot 'scripts\ui-automation\Capture-UiScreenshot.ps1'
            $pwshHost = (Get-Process -Id $PID).Path
            $capArgs = @('-NoProfile', '-File', $captureScript)
            if ($Label) { $capArgs += @('-Page', $Label) }
            $hwnd = [int64]$window.Current.NativeWindowHandle
            if ($hwnd -ne 0) { $capArgs += @('-Hwnd', ([string]$hwnd)) }
            $proc = Start-Process -FilePath $pwshHost -ArgumentList $capArgs -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -ne 0) {
                Write-Failure "Capture-UiScreenshot.ps1 exited with code $($proc.ExitCode)."
            }
            $shotDir = Join-Path $repoRoot 'output\screenshots'
            $latest = Get-ChildItem -LiteralPath $shotDir -Filter '*.png' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($null -ne $latest) {
                $out['png'] = [string]$latest.FullName
            }
        }

        Write-Result ([hashtable]$out)
    }
}
