#Requires -Version 7.3
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$bootstrapPath = Join-Path $root 'winmint.ps1'
$bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($bootstrapPath, [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    $message = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
    throw "winmint.ps1 has parse errors: $message"
}

function Assert-BootstrapText {
    param(
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Description
    )

    if ($bootstrap -notmatch $Pattern) {
        throw "Bootstrap contract missing: $Description"
    }
}

Assert-BootstrapText -Pattern 'yanai-sh/winmint' -Description 'canonical GitHub repository'
Assert-BootstrapText -Pattern 'WinMint-\$tag\.zip' -Description 'WinMint release archive naming'
Assert-BootstrapText -Pattern 'WinMint-Bootstrap' -Description 'WinMint GitHub user agent'
Assert-BootstrapText -Pattern "\[ValidateSet\('Ui','Gui','Headless'\)\]" -Description 'explicit launcher mode set'
Assert-BootstrapText -Pattern '\[switch\]\$Gui' -Description 'WIP GUI launcher switch'
Assert-BootstrapText -Pattern '\[switch\]\$Headless' -Description 'headless launcher switch'
Assert-BootstrapText -Pattern 'WinMint-UI\.ps1' -Description 'default UI entry point'
Assert-BootstrapText -Pattern 'WinMint-CLI\.ps1' -Description 'headless entry point'
Assert-BootstrapText -Pattern 'scripts\\gpui\\Start-GpuiLab\.ps1' -Description 'WIP GPUI lab entry point'
Assert-BootstrapText -Pattern 'ProfilePath' -Description 'headless profile forwarding'
Assert-BootstrapText -Pattern 'UupDumpZip' -Description 'headless UUP Dump forwarding'
Assert-BootstrapText -Pattern 'NoLaunch requested; not starting WinMint' -Description 'mode-neutral NoLaunch text'

Write-Host 'Bootstrap contract tests passed.'
