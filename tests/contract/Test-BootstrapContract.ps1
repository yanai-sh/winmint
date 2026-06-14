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

function Assert-BootstrapTextAbsent {
    param(
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Description
    )

    if ($bootstrap -match $Pattern) {
        throw "Bootstrap contract violation: $Description"
    }
}

Assert-BootstrapText -Pattern 'yanai-sh/winmint' -Description 'canonical GitHub repository'
Assert-BootstrapText -Pattern 'WinMint-\$tag\.zip' -Description 'WinMint release archive naming'
Assert-BootstrapText -Pattern 'WinMint-Bootstrap' -Description 'WinMint GitHub user agent'
Assert-BootstrapText -Pattern "\[ValidateSet\('Gui','Headless'\)\]" -Description 'explicit launcher mode set'
Assert-BootstrapText -Pattern '\[switch\]\$Gui' -Description 'primary GUI launcher switch'
Assert-BootstrapText -Pattern '\[switch\]\$Headless' -Description 'headless launcher switch'
Assert-BootstrapText -Pattern 'WinMint-GUI\.ps1' -Description 'default GUI entry point'
Assert-BootstrapText -Pattern 'WinMint-CLI\.ps1' -Description 'headless entry point'
Assert-BootstrapText -Pattern 'ProfilePath' -Description 'headless profile forwarding'
Assert-BootstrapText -Pattern "if \(\`$ValidateOnly\) \{ 'validate' \} else \{ 'build' \}" -Description 'headless dispatches the build/validate verb'
Assert-BootstrapText -Pattern 'SourceIso' -Description 'headless source-ISO override forwarding'
Assert-BootstrapText -Pattern "Add\('-AllowElevate'\)" -Description 'headless elevation forwarding'
Assert-BootstrapText -Pattern 'NoLaunch requested; not starting WinMint' -Description 'mode-neutral NoLaunch text'
Assert-BootstrapText -Pattern 'missing required checksum asset' -Description 'release checksum asset is mandatory'
Assert-BootstrapText -Pattern 'Refusing to install without release integrity verification' -Description 'missing checksum fails hard'
Assert-BootstrapText -Pattern 'Resolve-WinMintBootstrapReleasePayload' -Description 'bootstrap release payload resolution is centralized'
Assert-BootstrapText -Pattern 'Save-WinMintBootstrapReleasePayload' -Description 'bootstrap release payload download and verification are centralized'
Assert-BootstrapText -Pattern 'Test-WinMintArchiveHash -ArchivePath \$archivePath -ChecksumPath \$checksumPath' -Description 'downloaded release archive is hash-verified'
Assert-BootstrapTextAbsent -Pattern 'hash verification skipped' -Description 'bootstrap must not downgrade to unverified release installs'

Write-Host 'Bootstrap contract tests passed.'
