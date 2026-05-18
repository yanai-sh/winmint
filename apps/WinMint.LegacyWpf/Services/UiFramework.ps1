#Requires -Version 7.3

$script:WinMintUiFrameworkVersion = '4.3.0'
$script:WinMintUiFrameworkTarget = 'net8.0-windows7.0'

function Get-WinMintUiFrameworkAssemblyPath {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][ValidateSet('Wpf.Ui', 'Wpf.Ui.Abstractions')][string]$AssemblyName
    )

    return Join-Path $RepositoryRoot (
        'vendor\wpf-ui\{0}\{1}\{2}.dll' -f
        $script:WinMintUiFrameworkVersion,
        $script:WinMintUiFrameworkTarget,
        $AssemblyName)
}

function New-WinMintUiFrameworkResult {
    param(
        [bool]$IsLoaded,
        [string]$AssemblyPath,
        [string]$Message
    )

    [pscustomobject]@{
        IsLoaded     = $IsLoaded
        Package      = 'WPF-UI'
        Version      = $script:WinMintUiFrameworkVersion
        Target       = $script:WinMintUiFrameworkTarget
        AssemblyPath = $AssemblyPath
        Message      = $Message
    }
}

function Add-WinMintUiFrameworkAssembly {
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

function Initialize-WinMintUiFramework {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $abstractionsPath = Get-WinMintUiFrameworkAssemblyPath -RepositoryRoot $RepositoryRoot -AssemblyName 'Wpf.Ui.Abstractions'
    $wpfUiPath = Get-WinMintUiFrameworkAssemblyPath -RepositoryRoot $RepositoryRoot -AssemblyName 'Wpf.Ui'

    foreach ($path in @($abstractionsPath, $wpfUiPath)) {
        if (-not (Test-Path -LiteralPath $path)) {
            return New-WinMintUiFrameworkResult `
                -IsLoaded $false `
                -AssemblyPath $wpfUiPath `
                -Message "Missing WPF UI assembly: $path"
        }
    }

    try {
        Add-Type -AssemblyName WindowsBase
        Add-Type -AssemblyName PresentationCore
        Add-Type -AssemblyName PresentationFramework
        Add-WinMintUiFrameworkAssembly -Path $abstractionsPath -AssemblyName 'Wpf.Ui.Abstractions'
        Add-WinMintUiFrameworkAssembly -Path $wpfUiPath -AssemblyName 'Wpf.Ui'

        return New-WinMintUiFrameworkResult `
            -IsLoaded $true `
            -AssemblyPath $wpfUiPath `
            -Message "Loaded WPF UI $script:WinMintUiFrameworkVersion from '$wpfUiPath'."
    } catch {
        return New-WinMintUiFrameworkResult `
            -IsLoaded $false `
            -AssemblyPath $wpfUiPath `
            -Message "Failed to load WPF UI: $($_.Exception.Message)"
    }
}

function Remove-WinMintUiFrameworkDictionaries {
    param([Parameter(Mandatory)][string]$Xaml)

    $withoutTheme = $Xaml -replace '(?m)^\s*<ui:ThemesDictionary Theme="[^"]+" />\r?\n', ''
    return $withoutTheme -replace '(?m)^\s*<ui:ControlsDictionary />\r?\n', ''
}
