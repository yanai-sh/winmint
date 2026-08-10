#requires -Version 7.6
# Resolve published Wizard (toolkit) or fall back to dotnet run (dev tree).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $repoRoot

$wizArgs = [System.Collections.Generic.List[string]]::new()
foreach ($a in $args) {
    if ($wizArgs.Count -eq 0 -and $a -eq '--') { continue }
    $wizArgs.Add([string]$a)
}

$published = Join-Path $repoRoot 'bin\wizard\WinMint.Wizard.exe'
if (Test-Path -LiteralPath $published -PathType Leaf) {
    & $published @wizArgs
    exit $LASTEXITCODE
}

$project = Join-Path $repoRoot 'src\WinMint.Wizard\WinMint.Wizard.csproj'
if (-not (Test-Path -LiteralPath $project)) {
    throw "WinMint.Wizard.exe not found at $published and project missing at $project"
}

& dotnet run --project $project -- @wizArgs
exit $LASTEXITCODE
