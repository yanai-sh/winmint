#Requires -Version 7.3

if (-not (Get-Command Get-WinMintPath -ErrorAction SilentlyContinue)) {
    $candidateRoot = $PSScriptRoot
    while (-not [string]::IsNullOrWhiteSpace($candidateRoot)) {
        $corePath = Join-Path $candidateRoot 'src\WinMint\Core.ps1'
        if (Test-Path -LiteralPath $corePath -PathType Leaf) {
            . $corePath
            break
        }
        $parent = Split-Path -Parent $candidateRoot
        if ($parent -eq $candidateRoot) { break }
        $candidateRoot = $parent
    }
    if (-not (Get-Command Get-WinMintPath -ErrorAction SilentlyContinue)) {
        throw 'Could not locate src\WinMint\Core.ps1 from the legacy WPF app path.'
    }
}

function Update-WinMintUiRegionalFromPrefetch {
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

function Set-WinMintUiBrandImages {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][System.Windows.Window]$Window
    )

    $brandPath = Get-WinMintAssetPath -State $State -RelativePath 'assets\brand\WinMint.svg'
    if (-not (Test-Path -LiteralPath $brandPath)) { return }

    foreach ($name in @('TopWordmark', 'HeroWordmark')) {
        $element = $Window.FindName($name)
        if ($null -eq $element) { continue }
        if ($element -is [System.Windows.FrameworkElement]) {
            $element.Tag = 'assets\brand\WinMint.svg'
        }
    }
}

function Set-WinMintUiImageAssets {
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

        $assetPath = Get-WinMintAssetPath -State $State -RelativePath $imageMap[$name]
        if (-not (Test-Path -LiteralPath $assetPath)) { continue }

        try {
            $image.Source = Import-WinMintFrozenBitmap -Path $assetPath
        } catch {
            Write-WinMintUiLog "Image asset '$name' load failed: $_" 'WARN'
        }
    }
}

function Set-WinMintUiVectorIconAssets {
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

        $assetPath = Get-WinMintAssetPath -State $State -RelativePath $iconMap[$name]
        if (-not (Test-Path -LiteralPath $assetPath)) { continue }

        try {
            $icon.Data = Import-WinMintSvgPathGeometry -Path $assetPath
        } catch {
            Write-WinMintUiLog "Vector icon asset '$name' load failed: $_" 'WARN'
        }
    }
}


function Start-WinMintUIApp {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [switch]$DryRun,
        [switch]$FixtureMode,
        [string]$ResumeProfile = ''
    )

    $script:WinMintRepositoryRoot = $RepositoryRoot
    $uiRoot = Get-WinMintPath -Name LegacyWpfApp
    foreach ($module in @(
        'Foundation\FileSystemLiterals.ps1',
        'Foundation\UiSession.ps1',
        'Services\MountCleanup.ps1',
        'Services/Theme.ps1',
        'State\WinMintUiState.ps1',
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

    $state = New-WinMintUiState -RepositoryRoot $RepositoryRoot
    Update-WinMintUiRegionalFromPrefetch -State $state
    $xamlPath = Join-Path $uiRoot 'Views\MainWindow.xaml'
    $framework = $null
    if (Get-Command Initialize-WinMintUiFramework -ErrorAction SilentlyContinue) {
        $framework = Initialize-WinMintUiFramework -RepositoryRoot $RepositoryRoot
        if ($framework.IsLoaded) {
            Write-WinMintUiLog $framework.Message
        } else {
            Write-WinMintUiLog $framework.Message 'WARN'
        }
    }

    $xamlText = [System.IO.File]::ReadAllText($xamlPath)
    if ($null -ne $framework -and -not $framework.IsLoaded -and
        (Get-Command Remove-WinMintUiFrameworkDictionaries -ErrorAction SilentlyContinue)) {
        $xamlText = Remove-WinMintUiFrameworkDictionaries -Xaml $xamlText
    }
    $initialTheme = 'Dark'
    if (Get-Command Get-SystemTheme -ErrorAction SilentlyContinue) {
        $initialTheme = Get-SystemTheme
    }
    $xamlText = $xamlText -replace '<ui:ThemesDictionary Theme="Dark" />', (
        '<ui:ThemesDictionary Theme="{0}" />' -f $initialTheme)
    Write-WinMintUiLog 'Parsing MainWindow.xaml (WPF-UI first load may take several seconds)...'
    $window = [System.Windows.Markup.XamlReader]::Parse($xamlText)
    Write-WinMintUiLog 'MainWindow.xaml parsed.'

    if (Get-Command Register-WinMintUiWpfDispatcherFaultHandling -ErrorAction SilentlyContinue) {
        Register-WinMintUiWpfDispatcherFaultHandling -Dispatcher $window.Dispatcher
    }

    # Pin once for WPF handlers (Activated/Closing). Event scriptblocks may not see the caller's
    # function parameters under StrictMode — use Foundation\UiSession.ps1 (Get/Set-WinMintUiHostRunspacePin).
    $psHostRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace

    $script:WinMintRepositoryRoot = $RepositoryRoot
    $script:UiScriptDir = $RepositoryRoot
    $script:WinMintFixtureMode = [bool]$FixtureMode

    Register-WinMintUiAppContext -State $state -Window $window -UiRoot $uiRoot `
        -RepositoryRoot $RepositoryRoot -DryRun:$DryRun -FixtureMode:$FixtureMode -ResumeProfile $ResumeProfile

    if (Get-Command Initialize-WinMintUiMountHygiene -ErrorAction SilentlyContinue) {
        Write-WinMintUiLog 'Scheduling background DISM mount cleanup (does not block the wizard).'
        Initialize-WinMintUiMountHygiene -RepositoryRoot $RepositoryRoot -Async
    }
    if (Get-Command Register-WinMintUiMountHygieneWindowHooks -ErrorAction SilentlyContinue) {
        Register-WinMintUiMountHygieneWindowHooks -Window $window -HostRunspace $psHostRunspace
    }

    Set-WinMintUiBrandImages -State $state -Window $window
    Set-WinMintUiImageAssets -State $state -Window $window
    Set-WinMintUiVectorIconAssets -State $state -Window $window
    Set-Theme -Mode $initialTheme -Win $window


    Write-WinMintUiLog 'Loaded main window XAML.'
    Write-WinMintUiLog "Detected host regional defaults: timezone='$($state.Regional.TimeZoneId)' language='$($state.Regional.UILanguage)' input='$($state.Regional.InputLocale)'"

    if (Get-Command Initialize-WinMintUiShell -ErrorAction SilentlyContinue) {
        Initialize-WinMintUiShell -HostRunspace $psHostRunspace
    }

    Write-WinMintUiLog 'Showing window.'
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
        Get-Job -Name 'WinMintMountHygiene' -ErrorAction SilentlyContinue |
            ForEach-Object {
                Stop-Job -Job $_ -ErrorAction SilentlyContinue
                Remove-Job -Job $_ -Force -ErrorAction SilentlyContinue
            }
        if (Get-Command Stop-WinMintUiIsoVerification -ErrorAction SilentlyContinue) {
            Stop-WinMintUiIsoVerification
        }
        if (Get-Command Set-WinMintUiHostRunspacePin -ErrorAction SilentlyContinue) {
            Set-WinMintUiHostRunspacePin -Runspace $null
        }
    }
    Write-WinMintUiLog 'Window closed.'

    try { [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() } catch {}
}
