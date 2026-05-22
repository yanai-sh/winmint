#Requires -Version 7.3
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)

    $failures.Add($Message) | Out-Null
    Write-Error $Message -ErrorAction Continue
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) { Add-Failure $Message }
}

function Assert-Equal {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
    )

    if ([string]$Actual -ne [string]$Expected) {
        Add-Failure "$Message Expected '$Expected', got '$Actual'."
    }
}

$frameworkScript = Join-Path $root 'apps\legacy-wpf\Services\UiFramework.ps1'
$appScript = Join-Path $root 'apps\legacy-wpf\App\Start-WinMintUI.ps1'
Assert-True (Test-Path -LiteralPath $frameworkScript) 'UiFramework service script is missing.'
Assert-True (Test-Path -LiteralPath $appScript) 'Start-WinMintUI app loader is missing.'

if (Test-Path -LiteralPath $frameworkScript) {
    . $frameworkScript
}

Assert-True ([bool](Get-Command Initialize-WinMintUiFramework -ErrorAction SilentlyContinue)) 'Initialize-WinMintUiFramework is missing.'

if (Get-Command Initialize-WinMintUiFramework -ErrorAction SilentlyContinue) {
    $result = Initialize-WinMintUiFramework -RepositoryRoot $root
    Assert-True ([bool]$result.IsLoaded) "WPF UI should load successfully. Message: $($result.Message)"
    Assert-Equal $result.Package 'WPF-UI' 'Framework package mismatch.'
    Assert-Equal $result.Version '4.3.0' 'Framework version mismatch.'
    Assert-True (Test-Path -LiteralPath ([string]$result.AssemblyPath)) 'Loaded Wpf.Ui assembly path should exist.'

    $loaded = [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Wpf.Ui' } |
        Select-Object -First 1
    Assert-True ($null -ne $loaded) 'Wpf.Ui assembly is not loaded in the current AppDomain.'
}

if (Test-Path -LiteralPath $appScript) {
    $appSource = Get-Content -LiteralPath $appScript -Raw
    Assert-True ($appSource -match "'Foundation\\FileSystemLiterals\.ps1'") 'Start-WinMintUI.ps1 must dot-source Foundation\FileSystemLiterals.ps1.'
    Assert-True ($appSource -match "'Foundation\\UiSession\.ps1'") 'Start-WinMintUI.ps1 must dot-source Foundation\UiSession.ps1.'
    Assert-True ($appSource -match "'Services\\UiInteraction\.ps1'") 'Start-WinMintUI.ps1 must dot-source Services\UiInteraction.ps1.'
    Assert-True ($appSource -match "'Services\\UiFramework\.ps1'") 'Start-WinMintUI.ps1 must dot-source Services\UiFramework.ps1.'
    Assert-True ($appSource -match "'Services/Theme\.ps1'") 'Start-WinMintUI.ps1 must dot-source Services/Theme.ps1.'
    $frameworkCall = $appSource.IndexOf('Initialize-WinMintUiFramework')
    $xamlParse = $appSource.IndexOf('[System.Windows.Markup.XamlReader]::Parse')
    Assert-True ($frameworkCall -ge 0) 'Start-WinMintUI.ps1 must call Initialize-WinMintUiFramework.'
    Assert-True ($xamlParse -ge 0) 'Start-WinMintUI.ps1 must parse MainWindow.xaml.'
    Assert-True ($frameworkCall -lt $xamlParse) 'WPF UI framework must initialize before XamlReader.Parse.'
}

if ($failures.Count -gt 0) {
    throw "WPF UI framework tests failed with $($failures.Count) failure(s)."
}

Write-Host 'WPF UI framework tests passed.'
