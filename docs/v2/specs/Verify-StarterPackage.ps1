#Requires -Version 7.6
<#
.SYNOPSIS
  Pre-zip / post-zip audit for WinMint v2 starter packages.
.PARAMETER SeedRoot
  Path to seed-for-new-repo (default: sibling ../seed-for-new-repo).
.PARAMETER FutureRoot
  Path to future-assets (default: sibling ../future-assets).
.PARAMETER ZipDir
  Optional docs/v2/dist folder — if set, also audits *.zip listings.
#>
[CmdletBinding()]
param(
    [string]$SeedRoot = (Join-Path $PSScriptRoot '..\seed-for-new-repo'),
    [string]$FutureRoot = (Join-Path $PSScriptRoot '..\future-assets'),
    [string]$ZipDir
)

$ErrorActionPreference = 'Stop'
$failed = 0
function Ok([string]$m) { Write-Host "OK  $m" -ForegroundColor Green }
function Bad([string]$m) { Write-Host "FAIL $m" -ForegroundColor Red; $script:failed++ }

$SeedRoot = (Resolve-Path -LiteralPath $SeedRoot).Path
$FutureRoot = (Resolve-Path -LiteralPath $FutureRoot).Path

# Forbidden anywhere under seed
$forbidden = @(
    'BreezeX', 'img0.jpg', 'img100.jpg', 'Windows11ModernLight',
    'EverythingSetup', '.scratch', 'accountpicture', 'winmint_hero_ui'
)
Get-ChildItem -LiteralPath $SeedRoot -Recurse -Force -File | ForEach-Object {
    $rel = $_.FullName.Substring($SeedRoot.Length)
    foreach ($f in $forbidden) {
        if ($rel -like "*$f*") { Bad "seed contains forbidden path fragment '$f': $rel" }
    }
}

# Required seed anchors (day-one standalone repo)
foreach ($p in @(
        'WinMint.slnx',
        'global.json',
        'Directory.Build.props',
        'Directory.Packages.props',
        'README.md',
        'CONTEXT.md',
        'AGENTS.md',
        'LICENSE',
        'Justfile',
        'PSScriptAnalyzerSettings.psd1',
        '.gitignore',
        '.editorconfig',
        '.github\workflows\ci.yml',
        'docs\START.md',
        'docs\ARCHITECTURE.md',
        'docs\WORKFLOW.md',
        'docs\PORT-FROM-V1.md',
        'docs\STRUCTURE.md',
        'docs\coding-contract.md',
        'docs\decisions\ADR-001-source-iso-legal.md',
        'docs\decisions\ADR-002-v2-architecture.md',
        'docs\decisions\ADR-003-dma-interop.md',
        'assets\brand\mark\splash.png',
        'assets\brand\readme\light.svg',
        'assets\brand\plate\app.ico',
        'payload\media\cursors\modern\arrow.cur',
        'payload\media\wallpaper\bloom.png',
        'payload\media\fonts\cascadia-code-nf-regular.ttf',
        'payload\media\account\avatar.bmp',
        'payload\media\associations\default-apps.xml',
        'payload\media\terminal\settings.json',
        'payload\payload-manifest.json',
        'servicing\Mount-Wim.ps1',
        'servicing\Export-Iso.ps1',
        'servicing\README.md',
        'src\WinMint.Orchestrator\WinMint.Orchestrator.csproj',
        'src\WinMint.Cli\WinMint.Cli.csproj',
        'src\WinMint.Splash\WinMint.Splash.csproj',
        'src\WinMint.Wizard\README.md',
        'tests\WinMint.Orchestrator.Tests\WinMint.Orchestrator.Tests.csproj',
        'tests\WinMint.Cli.Tests\WinMint.Cli.Tests.csproj',
        'tools\analyze-ps.ps1'
    )) {
    if (Test-Path -LiteralPath (Join-Path $SeedRoot $p)) { Ok "seed has $p" }
    else { Bad "seed missing $p" }
}

$start = Get-Content -LiteralPath (Join-Path $SeedRoot 'docs\START.md') -Raw
if ($start -match 'just check' -and $start -match 'v1') { Ok 'START.md covers just check + v1 optional' }
else { Bad 'START.md missing just check / v1 guidance' }

$readme = Get-Content -LiteralPath (Join-Path $SeedRoot 'README.md') -Raw
if ($readme -match 'assets/brand/readme/light\.svg' -and $readme -match '(?m)^# WinMint\s*$') {
    Ok 'README has hero + title'
} else {
    Bad 'README missing hero path and/or # WinMint title'
}

if (Test-Path -LiteralPath (Join-Path $SeedRoot 'assets\ui')) { Bad 'seed still has assets/ui' }
else { Ok 'seed has no assets/ui' }
if (Test-Path -LiteralPath (Join-Path $SeedRoot 'payload\desktop')) { Bad 'seed still has payload/desktop' }
else { Ok 'seed has no payload/desktop' }

# future-assets shelves
foreach ($p in @(
        'README.md',
        'ui\wsl\ubuntu.png',
        'ui\wsl\ubuntu.svg',
        'ui\wsl\archlinux.png',
        'ui\wsl\fedora.png',
        'ui\wsl\nixos.png',
        'ui\wsl\pengwin.png',
        'ui\editors\zed.svg',
        'ui\editors\cursor.svg',
        'ui\editors\neovim.svg',
        'ui\editors\vscodium.png',
        'ui\desktop\windhawk.png',
        'ui\desktop\yasb.png',
        'ui\desktop\komorebi.png',
        'shell\yasb\config.yaml',
        'shell\yasb\preset.manifest.json',
        'shell\windhawk\preset.manifest.json',
        'shell\komorebi\komorebi.json',
        'wizard-webview2\README.md',
        'wizard-webview2\wizard.html'
    )) {
    if (Test-Path -LiteralPath (Join-Path $FutureRoot $p)) { Ok "future has $p" }
    else { Bad "future missing $p" }
}

$futureReadme = Get-Content -LiteralPath (Join-Path $FutureRoot 'README.md') -Raw
if ($futureReadme -match 'Not part of the day-one' -and $futureReadme -match 'winmint-v2-seed') {
    Ok 'future README states shelf role + seed companion'
} else {
    Bad 'future README missing shelf / seed-companion language'
}
if (Test-Path -LiteralPath (Join-Path $FutureRoot 'ui\desktop\windhawk\windhawk.png')) {
    Bad 'future still has nested ui/desktop/windhawk/'
} else { Ok 'future desktop windhawk is flat' }

if ($ZipDir -and (Test-Path -LiteralPath $ZipDir)) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipJunk = @('\bin\', '/bin/', '\obj\', '/obj/', '/.vs/', '\.vs\')
    Get-ChildItem -LiteralPath $ZipDir -Filter '*.zip' -File | ForEach-Object {
        # Prefer newest stamp per prefix; skip obviously bloated rebuild accidents only via junk check
        $zip = [System.IO.Compression.ZipFile]::OpenRead($_.FullName)
        try {
            $names = $zip.Entries | ForEach-Object FullName
            Ok ("zip {0}: {1} entries" -f $_.Name, $names.Count)
            foreach ($f in $forbidden) {
                $hit = $names | Where-Object { $_ -like "*$f*" } | Select-Object -First 1
                if ($hit) { Bad "zip $($_.Name) contains '$f' ($hit)" }
            }
            foreach ($j in $zipJunk) {
                $hit = $names | Where-Object { $_.Replace('/', '\').Contains($j.Replace('/', '\')) } | Select-Object -First 1
                if ($hit) { Bad "zip $($_.Name) contains build junk ($hit)" }
            }
            if ($_.Name -like 'winmint-v2-seed-*') {
                foreach ($need in @('docs/START.md', 'global.json', 'WinMint.slnx')) {
                    if ($names -notcontains $need) { Bad "seed zip $($_.Name) missing $need" }
                }
            }
        } finally { $zip.Dispose() }
    }
}

if ($failed -gt 0) {
    Write-Error "Verify failed with $failed issue(s)."
    exit 1
}
Write-Host 'All packaging checks passed.' -ForegroundColor Green
exit 0
