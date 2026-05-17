#Requires -Version 7.3

function Update-WinWSUiRegionalFromPrefetch {
    param([Parameter(Mandatory)][object]$State)

    $jobVariable = Get-Variable -Name RegionalRefreshJob -Scope Script -ErrorAction SilentlyContinue
    if ($null -eq $jobVariable) { return }
    if ($null -eq $script:RegionalRefreshJob -or $script:RegionalRefreshJob.State -eq 'Running') {
        return
    }

    $tips = @(Receive-Job -Job $script:RegionalRefreshJob -ErrorAction SilentlyContinue)
    if ($null -ne $tips -and $tips.Count -gt 0) {
        $State.Regional.InputLocale = $tips -join ';'
        $State.Regional.KeyboardLayouts = @($tips)
    }
    Remove-Job -Job $script:RegionalRefreshJob -Force -ErrorAction SilentlyContinue
    $script:RegionalRefreshJob = $null
}

function Set-WinWSUiBrandImages {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][System.Windows.Window]$Window
    )

    $brandPath = Get-WinWSAssetPath -State $State -RelativePath 'assets\brand\WinMint.svg'
    if (-not (Test-Path -LiteralPath $brandPath)) { return }

    foreach ($name in @('TopWordmark', 'HeroWordmark')) {
        $element = $Window.FindName($name)
        if ($null -eq $element) { continue }
        if ($element -is [System.Windows.FrameworkElement]) {
            $element.Tag = 'assets\brand\WinMint.svg'
        }
    }
}

function Set-WinWSUiImageAssets {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][System.Windows.Window]$Window
    )

    $imageMap = [ordered]@{
        ShellIconWindhawk  = 'assets\shell\windhawk.png'
        ShellIconYasb      = 'assets\shell\yasb.png'
        ShellIconKomorebi  = 'assets\shell\komorebi.png'
    }

    foreach ($name in $imageMap.Keys) {
        $image = $Window.FindName($name)
        if ($null -eq $image) { continue }

        $assetPath = Get-WinWSAssetPath -State $State -RelativePath $imageMap[$name]
        if (-not (Test-Path -LiteralPath $assetPath)) { continue }

        try {
            $image.Source = Import-WinWSFrozenBitmap -Path $assetPath
        } catch {
            Write-WinWSUiLog "Image asset '$name' load failed: $_" 'WARN'
        }
    }
}

function Set-WinWSUiVectorIconAssets {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][System.Windows.Window]$Window
    )

    $iconMap = [ordered]@{
        WslIconUbuntu      = 'assets\wsl\ubuntu.svg'
        WslIconDebian      = 'assets\wsl\debian.svg'
        WslIconArch        = 'assets\wsl\archlinux.svg'
        WslIconFedora      = 'assets\wsl\fedora.svg'
        EditorIconNeovim   = 'assets\editors\neovim.svg'
        EditorIconVSCodium = 'assets\editors\vscodium.svg'
        EditorIconCursor   = 'assets\editors\cursor.svg'
        EditorIconZed      = 'assets\editors\zedindustries.svg'
    }

    foreach ($name in $iconMap.Keys) {
        $icon = $Window.FindName($name)
        if ($null -eq $icon) { continue }

        $assetPath = Get-WinWSAssetPath -State $State -RelativePath $iconMap[$name]
        if (-not (Test-Path -LiteralPath $assetPath)) { continue }

        try {
            $icon.Data = Import-WinWSSvgPathGeometry -Path $assetPath
        } catch {
            Write-WinWSUiLog "Vector icon asset '$name' load failed: $_" 'WARN'
        }
    }
}


function Start-WinWSUIApp {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [switch]$DryRun,
        [switch]$FixtureMode,
        [string]$ResumeProfile = ''
    )

    $uiRoot = Join-Path $RepositoryRoot 'src\WinWS.UI'
    foreach ($module in @(
        'Foundation\FileSystemLiterals.ps1',
        'Foundation\UiSession.ps1',
        'Services\MountCleanup.ps1',
        'Services/Theme.ps1',
        'State\WinWSUiState.ps1',
        'Services\Assets.ps1',
        'Services\UiFramework.ps1',
        'Services\Summary.ps1',
        'Services\ProfileAdapter.ps1',
        'Services\UiInteraction.ps1',
        'Services\IsoService.ps1',
        'Services\BuildRunner.ps1',
        'ViewModels\StartStage.ps1',
        'ViewModels\MachineStage.ps1',
        'ViewModels\DiskStage.ps1',
        'ViewModels\ProfileStage.ps1',
        'ViewModels\WorkstationStage.ps1',
        'ViewModels\LaunchStage.ps1'
    )) {
        $path = Join-Path $uiRoot $module
        if (Test-Path -LiteralPath $path) { . $path }
    }

    $state = New-WinWSUiState -RepositoryRoot $RepositoryRoot
    Update-WinWSUiRegionalFromPrefetch -State $state
    $xamlPath = Join-Path $uiRoot 'Views\MainWindow.xaml'
    $framework = $null
    if (Get-Command Initialize-WinWSUiFramework -ErrorAction SilentlyContinue) {
        $framework = Initialize-WinWSUiFramework -RepositoryRoot $RepositoryRoot
        if ($framework.IsLoaded) {
            Write-WinWSUiLog $framework.Message
        } else {
            Write-WinWSUiLog $framework.Message 'WARN'
        }
    }

    $xamlText = [System.IO.File]::ReadAllText($xamlPath)
    if ($null -ne $framework -and -not $framework.IsLoaded -and
        (Get-Command Remove-WinWSUiFrameworkDictionaries -ErrorAction SilentlyContinue)) {
        $xamlText = Remove-WinWSUiFrameworkDictionaries -Xaml $xamlText
    }
    $initialTheme = 'Dark'
    if (Get-Command Get-SystemTheme -ErrorAction SilentlyContinue) {
        $initialTheme = Get-SystemTheme
    }
    $xamlText = $xamlText -replace '<ui:ThemesDictionary Theme="Dark" />', (
        '<ui:ThemesDictionary Theme="{0}" />' -f $initialTheme)
    Write-WinWSUiLog 'Parsing MainWindow.xaml (WPF-UI first load may take several seconds)...'
    $window = [System.Windows.Markup.XamlReader]::Parse($xamlText)
    Write-WinWSUiLog 'MainWindow.xaml parsed.'

    if (Get-Command Register-WinWSUiWpfDispatcherFaultHandling -ErrorAction SilentlyContinue) {
        Register-WinWSUiWpfDispatcherFaultHandling -Dispatcher $window.Dispatcher
    }

    # Pin once for WPF handlers (Activated/Closing). Event scriptblocks may not see the caller's
    # function parameters under StrictMode — use Foundation\UiSession.ps1 (Get/Set-WinWSUiHostRunspacePin).
    $psHostRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace

    $script:WinWSRepositoryRoot = $RepositoryRoot
    $script:UiScriptDir = $RepositoryRoot
    $script:WinWSFixtureMode = [bool]$FixtureMode

    Register-WinWSUiAppContext -State $state -Window $window -UiRoot $uiRoot `
        -RepositoryRoot $RepositoryRoot -DryRun:$DryRun -FixtureMode:$FixtureMode -ResumeProfile $ResumeProfile

    if (Get-Command Initialize-WinWSUiMountHygiene -ErrorAction SilentlyContinue) {
        Write-WinWSUiLog 'Scheduling background DISM mount cleanup (does not block the wizard).'
        Initialize-WinWSUiMountHygiene -RepositoryRoot $RepositoryRoot -Async
    }
    if (Get-Command Register-WinWSUiMountHygieneWindowHooks -ErrorAction SilentlyContinue) {
        Register-WinWSUiMountHygieneWindowHooks -Window $window -HostRunspace $psHostRunspace
    }

    Set-WinWSUiBrandImages -State $state -Window $window
    Set-WinWSUiImageAssets -State $state -Window $window
    Set-WinWSUiVectorIconAssets -State $state -Window $window
    Set-Theme -Mode $initialTheme -Win $window


    Write-WinWSUiLog 'Loaded main window XAML.'
    Write-WinWSUiLog "Detected host regional defaults: timezone='$($state.Regional.TimeZoneId)' language='$($state.Regional.UILanguage)' input='$($state.Regional.InputLocale)'"

    if (Get-Command Initialize-WinWSUiShell -ErrorAction SilentlyContinue) {
        Initialize-WinWSUiShell -HostRunspace $psHostRunspace
    }

    Write-WinWSUiLog 'Showing window.'
    try {
        if ($FixtureMode) {
            $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
            $window.Left = -10000
            $window.Top = -10000
            $window.ShowActivated = $false
        }
        if ($FixtureMode) {
            $window.Add_Closed({
                try { [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() } catch {}
            })
            $window.Show()
            [System.Windows.Threading.Dispatcher]::Run()
        } else {
            $null = $window.ShowDialog()
        }
    }
    finally {
        Get-Job -Name 'WinWSMountHygiene' -ErrorAction SilentlyContinue |
            ForEach-Object {
                Stop-Job -Job $_ -ErrorAction SilentlyContinue
                Remove-Job -Job $_ -Force -ErrorAction SilentlyContinue
            }
        if (Get-Command Stop-WinWSUiIsoVerification -ErrorAction SilentlyContinue) {
            Stop-WinWSUiIsoVerification
        }
        if (Get-Command Set-WinWSUiHostRunspacePin -ErrorAction SilentlyContinue) {
            Set-WinWSUiHostRunspacePin -Runspace $null
        }
    }
    Write-WinWSUiLog 'Window closed.'

    try { [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() } catch {}
}
