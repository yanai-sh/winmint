#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Maintainer-only live Catalog reconcile. Not in `just check`.

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'servicing\Resolve-WinMintQualityUpdate.ps1')
. (Join-Path $repo 'tools\host\WinMint-QualityCheck.ps1')

$qualityRows = Invoke-WinMintQualityReconcile
Write-WinMintQualityReconcileLines -Rows $qualityRows
Write-Output 'quality-check ok'
exit 0
