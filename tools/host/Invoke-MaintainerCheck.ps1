#requires -Version 7.6
# SL7 maintainer: Catalog B-release + optional Source ISO advisory. Not in `just check`.

param(
    [switch] $SkipIso
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repo 'tools\host\WinMint-MaintainerCheck.ps1')
. (Join-Path $repo 'tools\host\WinMint-QualityCheck.ps1')

$result = Invoke-WinMintMaintainerCheckCore -RepoRoot $repo -SkipIso:$SkipIso
if ($result.QualityFailed) {
    Write-Output $result.QualityError
}
else {
    Write-WinMintQualityReconcileLines -Rows $result.QualityRows
    if ($null -ne $result.IsoResult) {
        foreach ($m in $result.IsoResult.Messages) { Write-Output $m }
    }
    Write-Output 'quality-check ok'
}
exit [int]$result.ExitCode
