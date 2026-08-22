#requires -Version 7.6
# Resolve published Cli (toolkit) or fall back to dotnet run (dev tree).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $repoRoot
. (Join-Path $PSScriptRoot 'Resolve-WinMintPublishedBinary.ps1')

# just / `pwsh -File … -- …` may pass a literal `--` as $args[0]
$cliArgs = [System.Collections.Generic.List[string]]::new()
foreach ($a in $args) {
    if ($cliArgs.Count -eq 0 -and $a -eq '--') { continue }
    $cliArgs.Add([string]$a)
}

$published = Join-Path $repoRoot 'bin\cli\WinMint.Cli.exe'
$cliSourceRoots = @(
    (Join-Path $repoRoot 'src\WinMint.Cli'),
    (Join-Path $repoRoot 'src\WinMint.Orchestrator'),
    (Join-Path $repoRoot 'src\WinMint.Contracts')
)
if ((Test-Path -LiteralPath $published -PathType Leaf) -and
    (Test-WinMintPublishedBinaryCurrent -PublishedExe $published -SourceRoots $cliSourceRoots)) {
    & $published @cliArgs
    exit $LASTEXITCODE
}

$project = Join-Path $repoRoot 'src\WinMint.Cli\WinMint.Cli.csproj'
if (-not (Test-Path -LiteralPath $project)) {
    throw "WinMint.Cli.exe not found at $published and project missing at $project"
}

& dotnet run --project $project -- @cliArgs
exit $LASTEXITCODE
