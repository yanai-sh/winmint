#Requires -Version 7.3
<#
.SYNOPSIS
  Rebuild assets\brand\WinMint.vector.svg (GPUI-compatible all-vector mark).

.DESCRIPTION
  By default publishes from assets\brand\winmint-mark-v2.svg via publish_vector_mark_from_v2.py
  (stdlib only — strips degenerate paths, adds accessibility metadata).

  Pass -RasterTrace to regenerate from authoring WinMint.svg embedded PNG leaf using
  build_vector_winmint_mark.py (requires tools\brand\.venv + SciPy/Skimage wheels).
  Use -Bootstrap with -RasterTrace to create the venv.

.EXAMPLE
  pwsh -NoProfile -File tools\brand\Build-WinMintVectorMark.ps1

.EXAMPLE
  pwsh -NoProfile -File tools\brand\Build-WinMintVectorMark.ps1 -RasterTrace -Bootstrap

.EXAMPLE
  pwsh -NoProfile -File tools\brand\Build-WinMintVectorMark.ps1 -RasterTrace -- --approx 2.5
#>
[CmdletBinding()]
param(
    [switch] $RasterTrace,
    [switch] $Bootstrap,
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]] $Passthrough = @()
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$brandDir = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $brandDir)
$venvPy = Join-Path $brandDir '.venv\Scripts\python.exe'
$publishScript = Join-Path $brandDir 'publish_vector_mark_from_v2.py'
$traceScript = Join-Path $brandDir 'build_vector_winmint_mark.py'

if ($RasterTrace) {
    if (-not (Test-Path -LiteralPath $traceScript)) {
        Write-Error "Missing $traceScript"
    }
    if ($Bootstrap) {
        if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
            Write-Error 'uv is required for -Bootstrap (https://docs.astral.sh/uv/).'
        }
        Push-Location $brandDir
        try {
            if (-not (Test-Path -LiteralPath '.venv')) {
                uv venv .venv
            }
            uv pip install -r (Join-Path $brandDir 'requirements-vector.txt') --python $venvPy
        }
        finally {
            Pop-Location
        }
    }

    if (-not (Test-Path -LiteralPath $venvPy)) {
        Write-Error (
            '-RasterTrace needs tools\brand\.venv. Run:' + [Environment]::NewLine +
            '  pwsh -NoProfile -File tools\brand\Build-WinMintVectorMark.ps1 -RasterTrace -Bootstrap' + [Environment]::NewLine +
            'or: uv venv tools\brand\.venv ; uv pip install -r tools\brand\requirements-vector.txt --python tools\brand\.venv\Scripts\python.exe'
        )
    }
}
elseif (-not (Test-Path -LiteralPath $publishScript)) {
    Write-Error "Missing $publishScript"
}

$pythonExe = if ((Test-Path -LiteralPath $venvPy)) { $venvPy } elseif (Get-Command python -ErrorAction SilentlyContinue) {
    (Get-Command python).Source
}
else {
    Write-Error 'Python not found. Install Python or run -RasterTrace -Bootstrap to create tools\brand\.venv.'
}

$scriptPath = if ($RasterTrace) { $traceScript } else { $publishScript }

Push-Location $repoRoot
try {
    & $pythonExe $scriptPath @Passthrough
}
finally {
    Pop-Location
}
