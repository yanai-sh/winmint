#Requires -Version 5.1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'WinMint.ModuleLoader.ps1')

function Get-WinMintMinimumPowerShellVersion {
    [CmdletBinding()]
    param()

    [version]'7.6.2'
}

function Test-WinMintSupportedPowerShell {
    [CmdletBinding()]
    param(
        [version]$Version = $PSVersionTable.PSVersion
    )

    return ($Version -ge (Get-WinMintMinimumPowerShellVersion))
}

function Resolve-WinMintPreferredPowerShell {
    [CmdletBinding()]
    param()

    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($path in @(
            (Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
            (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'PowerShell\7\pwsh.exe')
        )) {
        if ([string]::IsNullOrWhiteSpace([string]$path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        try {
            $versionText = & $path -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null | Select-Object -First 1
            $version = [version]([string]$versionText).Trim()
            $candidates.Add([pscustomobject]@{
                    Path = $path
                    Version = $version
                }) | Out-Null
        }
        catch { }
    }

    return @($candidates | Sort-Object Version -Descending | Select-Object -First 1)
}

function Install-WinMintPowerShellRuntime {
    [CmdletBinding()]
    param()

    $minimum = Get-WinMintMinimumPowerShellVersion
    $winget = Get-Command 'winget.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $winget) {
        throw "PowerShell $minimum or newer is required, and WinGet was not available for automatic installation."
    }

    & $winget.Source install `
        --id Microsoft.PowerShell `
        --source winget `
        --accept-package-agreements `
        --accept-source-agreements `
        --disable-interactivity `
        --silent | Out-Null
}

function Invoke-WinMintRuntimeBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Entrypoint,
        [string[]]$Arguments = @()
    )

    if (Test-WinMintSupportedPowerShell) {
        return [pscustomobject]@{
            Relaunched = $false
            ExitCode = 0
            Runtime = $PSVersionTable.PSVersion.ToString()
        }
    }

    $candidate = Resolve-WinMintPreferredPowerShell
    if (-not $candidate -or -not (Test-WinMintSupportedPowerShell -Version $candidate.Version)) {
        Install-WinMintPowerShellRuntime
        $candidate = Resolve-WinMintPreferredPowerShell
    }
    if (-not $candidate -or -not (Test-WinMintSupportedPowerShell -Version $candidate.Version)) {
        throw "PowerShell $(Get-WinMintMinimumPowerShellVersion) or newer is required, but an eligible runtime could not be located after installation."
    }

    $argumentList = [System.Collections.Generic.List[string]]::new()
    foreach ($value in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Entrypoint)) {
        $argumentList.Add($value) | Out-Null
    }
    foreach ($arg in @($Arguments)) {
        $argumentList.Add([string]$arg) | Out-Null
    }

    & $candidate.Path @($argumentList.ToArray())
    return [pscustomobject]@{
        Relaunched = $true
        ExitCode = $LASTEXITCODE
        Runtime = $candidate.Version.ToString()
    }
}

Export-ModuleMember -Function @(
    'Get-WinMintMinimumPowerShellVersion',
    'Test-WinMintSupportedPowerShell',
    'Resolve-WinMintPreferredPowerShell',
    'Install-WinMintPowerShellRuntime',
    'Invoke-WinMintRuntimeBootstrap'
)
