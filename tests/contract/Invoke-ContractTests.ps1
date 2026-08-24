#requires -Version 7.6
param(
    [string] $StatusPath = '',
    [string] $RunId = ''
)
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$repo = Split-Path -Parent (Split-Path -Parent $here)
$writeStatus = -not [string]::IsNullOrWhiteSpace($StatusPath) -and -not [string]::IsNullOrWhiteSpace($RunId)
if ($writeStatus) {
    . (Join-Path $repo 'tools\host\CheckStatus.ps1')
}

$scripts = @(Get-ChildItem -LiteralPath $here -Filter 'Test-*.ps1' | Sort-Object Name)
$count = $scripts.Count
$index = 0
foreach ($script in $scripts) {
    $index++
    Write-Host $script.Name
    if ($writeStatus) {
        Write-CheckStatus -Path $StatusPath -RunId $RunId -Phase contract -Leaf $script.Name `
            -LastHostLine $script.Name -Index $index -Count $count
    }
    & pwsh -NoProfile -File $script.FullName
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
