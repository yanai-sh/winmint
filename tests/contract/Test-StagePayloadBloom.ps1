#requires -Version 7.6
Set-StrictMode -Version Latest
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$bloom = Join-Path $repo 'payload\media\wallpaper\bloom.jpg'
if (-not (Test-Path -LiteralPath $bloom -PathType Leaf)) { throw "bloom.jpg missing: $bloom" }
if ((Get-Item -LiteralPath $bloom).Length -lt 1KB) { throw 'bloom.jpg too small' }
$stage = Get-Content -LiteralPath (Join-Path $repo 'servicing\Stage-Payload.ps1') -Raw
if ($stage -notmatch 'WinMint-Bloom\.jpg') { throw 'Stage-Payload.ps1 must copy WinMint-Bloom.jpg' }
