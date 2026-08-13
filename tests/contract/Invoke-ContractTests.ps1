#requires -Version 7.6
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
Get-ChildItem -LiteralPath $here -Filter 'Test-*.ps1' |
    Sort-Object Name |
    ForEach-Object {
        Write-Host $_.Name
        & pwsh -NoProfile -File $_.FullName
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
