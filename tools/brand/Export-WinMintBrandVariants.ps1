#Requires -Version 7.3
#
# Writes WinMint.svg (panes + embedded raster leaf master). For GPUI, publish the
# all-vector mark: pwsh -File tools\brand\Build-WinMintVectorMark.ps1 (from winmint-mark-v2.svg).
[CmdletBinding()]
param(
    [string]$LightPane = '#0078d4',
    [string]$LightPaneAccent = '#0078d4',
    [string]$DarkPane = '#4fb5ff',
    [string]$DarkPaneAccent = '#1f8fe5',
    [switch]$Variants
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$brandDir = Join-Path $root 'assets\brand'
$masterPath = Join-Path $brandDir 'WinMint.svg'
$leafPath = Join-Path $brandDir 'winmint-leaf.original.png'
$lightPath = Join-Path $brandDir 'winmint-mark.light.svg'
$darkPath = Join-Path $brandDir 'winmint-mark.dark.svg'

function Get-WinMintLeafDataUri {
    $master = Get-Content -Raw -LiteralPath $masterPath
    $match = [regex]::Match(
        $master,
        '<image[^>]*id="(?:img2|original-leaf)"[^>]*href="data:image/png;base64,([^"]+)"'
    )
    if ($match.Success) {
        return "data:image/png;base64,$($match.Groups[1].Value)"
    }

    if (Test-Path -LiteralPath $leafPath -PathType Leaf) {
        $leafBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($leafPath))
        return "data:image/png;base64,$leafBase64"
    }

    throw "Could not find the original leaf image in $masterPath or $leafPath."
}

function New-WinMintMarkSvg {
    param(
        [Parameter(Mandatory)][string]$Pane,
        [Parameter(Mandatory)][string]$PaneAccent,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$LeafHref
    )

    @"
<svg xmlns="http://www.w3.org/2000/svg" id="winmint-mark" viewBox="0 0 1080 1080" role="img" aria-labelledby="title desc">
  <title id="title">WinMint mark</title>
  <desc id="desc">$Description</desc>
  <g id="window" shape-rendering="crispEdges" transform="matrix(.146 0 0 .146 184 184)">
    <path class="wm-pane" fill="$Pane" d="M0 0h2311v2310H0z"/>
    <path class="wm-pane-accent" fill="$PaneAccent" d="M2564 0h2311v2310H2564z"/>
    <path class="wm-pane-accent" fill="$PaneAccent" d="M0 2564h2311v2311H0z"/>
    <path class="wm-pane" fill="$Pane" d="M2564 2564h2311v2311H2564z"/>
  </g>
  <image id="original-leaf" class="wm-original-leaf" width="1024" height="1024" href="$LeafHref" transform="matrix(.982,.256,-0.256,.982,456.776,-387.875)"/>
</svg>
"@
}

New-Item -ItemType Directory -Force -Path $brandDir | Out-Null

$leafHref = Get-WinMintLeafDataUri

$masterSvg = New-WinMintMarkSvg `
    -Pane $LightPane `
    -PaneAccent $LightPaneAccent `
    -Description 'Windows panes with the original WinMint leaf artwork.' `
    -LeafHref $leafHref

Set-Content -LiteralPath $masterPath -Value $masterSvg -Encoding utf8NoBOM -NoNewline

if ($Variants) {
    $lightSvg = New-WinMintMarkSvg `
        -Pane $LightPane `
        -PaneAccent $LightPaneAccent `
        -Description 'Light WinMint mark variant using the original leaf artwork.' `
        -LeafHref $leafHref

    $darkSvg = New-WinMintMarkSvg `
        -Pane $DarkPane `
        -PaneAccent $DarkPaneAccent `
        -Description 'Dark WinMint mark variant using the original leaf artwork.' `
        -LeafHref $leafHref

    Set-Content -LiteralPath $lightPath -Value $lightSvg -Encoding utf8NoBOM -NoNewline
    Set-Content -LiteralPath $darkPath -Value $darkSvg -Encoding utf8NoBOM -NoNewline
}

$result = [ordered]@{
    Master = Resolve-Path -LiteralPath $masterPath
    LeafSha256 = [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [Convert]::FromBase64String($leafHref.Substring('data:image/png;base64,'.Length))
        )
    ).ToLowerInvariant()
}

if ($Variants) {
    $result.Light = Resolve-Path -LiteralPath $lightPath
    $result.Dark = Resolve-Path -LiteralPath $darkPath
}

[pscustomobject]$result
