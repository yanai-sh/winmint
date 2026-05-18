#Requires -Version 7.3
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workerPath = Join-Path $root 'cloudflare\winmint\src\index.js'
$worker = Get-Content -LiteralPath $workerPath -Raw

function Assert-WorkerText {
    param(
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Description
    )

    if ($worker -notmatch $Pattern) {
        throw "Cloudflare Worker contract missing: $Description"
    }
}

Assert-WorkerText -Pattern 'raw\.githubusercontent\.com/yanai-sh/winmint/main/winmint\.ps1' -Description 'canonical bootstrap source'
Assert-WorkerText -Pattern 'BOOTSTRAP_PATHS = new Set\(\["/", "/winmint", "/winmint\.ps1"\]\)' -Description 'default bootstrap aliases'
Assert-WorkerText -Pattern 'CLI_PATHS = new Set\(\["/cli", "/cli\.ps1"\]\)' -Description 'headless CLI aliases'
Assert-WorkerText -Pattern '\[scriptblock\]::Create\(\$bootstrap\)\) -Headless @forward' -Description 'CLI wrapper invokes headless mode'
Assert-WorkerText -Pattern 'Invoke-RestMethod -UseBasicParsing -Uri' -Description 'CLI wrapper fetches canonical bootstrap'
Assert-WorkerText -Pattern 'url\.pathname === "/winmint/" \|\| url\.pathname === "/cli/"' -Description 'trailing slash redirects'

Write-Host 'Cloudflare Worker contract tests passed.'
