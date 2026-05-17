#Requires -Version 7.3

$script:WinWSUiFrameworkVersion = '4.3.0'
$script:WinWSUiFrameworkTarget = 'net8.0-windows7.0'

function Get-WinWSUiFrameworkAssemblyPath {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][ValidateSet('Wpf.Ui', 'Wpf.Ui.Abstractions')][string]$AssemblyName
    )

    return Join-Path $RepositoryRoot (
        'vendor\wpf-ui\{0}\{1}\{2}.dll' -f
        $script:WinWSUiFrameworkVersion,
        $script:WinWSUiFrameworkTarget,
        $AssemblyName)
}

function New-WinWSUiFrameworkResult {
    param(
        [bool]$IsLoaded,
        [string]$AssemblyPath,
        [string]$Message
    )

    [pscustomobject]@{
        IsLoaded     = $IsLoaded
        Package      = 'WPF-UI'
        Version      = $script:WinWSUiFrameworkVersion
        Target       = $script:WinWSUiFrameworkTarget
        AssemblyPath = $AssemblyPath
        Message      = $Message
    }
}

function Add-WinWSUiFrameworkAssembly {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AssemblyName
    )

    $loaded = [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq $AssemblyName } |
        Select-Object -First 1
    if ($null -ne $loaded) { return }

    Add-Type -Path $Path
}

function Initialize-WinWSUiFramework {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $abstractionsPath = Get-WinWSUiFrameworkAssemblyPath -RepositoryRoot $RepositoryRoot -AssemblyName 'Wpf.Ui.Abstractions'
    $wpfUiPath = Get-WinWSUiFrameworkAssemblyPath -RepositoryRoot $RepositoryRoot -AssemblyName 'Wpf.Ui'

    foreach ($path in @($abstractionsPath, $wpfUiPath)) {
        if (-not (Test-Path -LiteralPath $path)) {
            return New-WinWSUiFrameworkResult `
                -IsLoaded $false `
                -AssemblyPath $wpfUiPath `
                -Message "Missing WPF UI assembly: $path"
        }
    }

    try {
        Add-Type -AssemblyName WindowsBase
        Add-Type -AssemblyName PresentationCore
        Add-Type -AssemblyName PresentationFramework
        Add-WinWSUiFrameworkAssembly -Path $abstractionsPath -AssemblyName 'Wpf.Ui.Abstractions'
        Add-WinWSUiFrameworkAssembly -Path $wpfUiPath -AssemblyName 'Wpf.Ui'

        return New-WinWSUiFrameworkResult `
            -IsLoaded $true `
            -AssemblyPath $wpfUiPath `
            -Message "Loaded WPF UI $script:WinWSUiFrameworkVersion from '$wpfUiPath'."
    } catch {
        return New-WinWSUiFrameworkResult `
            -IsLoaded $false `
            -AssemblyPath $wpfUiPath `
            -Message "Failed to load WPF UI: $($_.Exception.Message)"
    }
}

function Remove-WinWSUiFrameworkDictionaries {
    param([Parameter(Mandatory)][string]$Xaml)

    $withoutTheme = $Xaml -replace '(?m)^\s*<ui:ThemesDictionary Theme="[^"]+" />\r?\n', ''
    return $withoutTheme -replace '(?m)^\s*<ui:ControlsDictionary />\r?\n', ''
}
