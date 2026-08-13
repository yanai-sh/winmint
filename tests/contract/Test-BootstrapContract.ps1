#Requires -Version 7.6
# Bootstrap contract: keep winmint.ps1 aligned with no-clone release assets.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path -LiteralPath (Join-Path $root 'winmint.ps1'))) {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
}
$bootstrapPath = Join-Path $root 'winmint.ps1'
$bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($bootstrapPath, [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    $message = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
    throw "winmint.ps1 has parse errors: $message"
}

function Assert-BootstrapText {
    param([Parameter(Mandatory)][string]$Pattern, [Parameter(Mandatory)][string]$Description)
    if ($bootstrap -notmatch $Pattern) {
        throw "Bootstrap contract missing: $Description"
    }
}

function Assert-BootstrapTextAbsent {
    param([Parameter(Mandatory)][string]$Pattern, [Parameter(Mandatory)][string]$Description)
    if ($bootstrap -match $Pattern) {
        throw "Bootstrap contract violation: $Description"
    }
}

Assert-BootstrapText -Pattern 'yanai-sh/winmint' -Description 'canonical GitHub repository'
Assert-BootstrapText -Pattern "ReleaseApiRoot = 'https://api\.github\.com'" -Description 'canonical GitHub API root default'
Assert-BootstrapText -Pattern 'WinMint-\$tag\.zip' -Description 'WinMint release archive naming'
Assert-BootstrapText -Pattern 'WinMint-Bootstrap' -Description 'WinMint GitHub user agent'
Assert-BootstrapText -Pattern 'PowerShell 7\.6' -Description 'bootstrap minimum runtime pin'
Assert-BootstrapText -Pattern 'Casey\.Just' -Description 'Just install via winget'
Assert-BootstrapText -Pattern "\[ValidateSet\('Gui', 'Headless'\)\]" -Description 'explicit launcher mode set'
Assert-BootstrapText -Pattern '\[switch\]\$Gui' -Description 'primary GUI launcher switch'
Assert-BootstrapText -Pattern '\[switch\]\$Headless' -Description 'headless launcher switch'
Assert-BootstrapText -Pattern '\[switch\]\$CacheRelease' -Description 'durable release caching is explicit opt-in'
Assert-BootstrapText -Pattern '\[switch\]\$PrimaryGate' -Description 'one-shot Gate B wipe ISO switch'
Assert-BootstrapText -Pattern 'Wipe ISO while Wizard is open' -Description 'ephemeral live-session wipe hint'
Assert-BootstrapText -Pattern 'Ephemeral toolkit left at' -Description 'NoLaunch leaves TEMP toolkit for disposable job'
Assert-BootstrapText -Pattern 'bin\\wizard\\WinMint\.Wizard\.exe' -Description 'Wizard toolkit path'
Assert-BootstrapText -Pattern 'bin\\cli\\WinMint\.Cli\.exe' -Description 'Cli toolkit path'
Assert-BootstrapText -Pattern 'missing required checksum asset' -Description 'release checksum asset is mandatory'
Assert-BootstrapText -Pattern 'Refusing to install without release integrity verification' -Description 'missing checksum fails hard'
Assert-BootstrapText -Pattern 'New-WinMintBootstrapSessionRoot' -Description 'default bootstrap creates a unique temporary session'
Assert-BootstrapText -Pattern 'Remove-WinMintBootstrapSessionRoot' -Description 'default bootstrap cleans the temporary session'
Assert-BootstrapText -Pattern 'Failure kind:' -Description 'bootstrap failure output includes a category'
Assert-BootstrapText -Pattern 'Safe to retry:' -Description 'bootstrap failure output explains retry safety'
Assert-BootstrapTextAbsent -Pattern 'hash verification skipped' -Description 'bootstrap must not downgrade to unverified release installs'

$releasePath = Join-Path $root 'tools\release\Publish-WinMintRelease.ps1'
$release = Get-Content -LiteralPath $releasePath -Raw
$payloadStage = "Copy-Item -LiteralPath (Join-Path `$repoRoot 'payload') -Destination (Join-Path `$StageRoot 'payload') -Recurse"
if ($release -notlike "*$payloadStage*") {
    throw 'Release contract missing: recursive staging of the complete payload directory'
}

$workerPath = Join-Path $root 'cloudflare\winmint\src\index.js'
if (-not (Test-Path -LiteralPath $workerPath)) {
    throw "Worker source missing: $workerPath"
}
$worker = Get-Content -LiteralPath $workerPath -Raw
if ($worker -notmatch '/primary-gate') {
    throw 'Worker contract missing: /primary-gate route'
}
if ($worker -notmatch 'PrimaryGate') {
    throw 'Worker contract missing: PrimaryGate invoke in /primary-gate wrapper'
}
if ($worker -notmatch '/validate') {
    throw 'Worker contract missing: /validate route'
}
if ($worker -notmatch 'ValidateOnly') {
    throw 'Worker contract missing: ValidateOnly invoke in /validate wrapper'
}

Write-Host 'Bootstrap contract tests passed.'
