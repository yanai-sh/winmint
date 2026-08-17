#requires -Version 7.6
<#
.SYNOPSIS
  Publish an unsigned WinMint toolkit staging tree. Does not Authenticode-sign and does not zip.
#>
param(
    [Parameter(Mandatory)] [string] $Tag,
    [Parameter(Mandatory)] [string] $StageRoot,
    [ValidateSet('win-arm64')] [string] $Runtime = 'win-arm64',
    [string] $Configuration = 'Release'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $repoRoot
. (Join-Path $PSScriptRoot 'Get-WinMintReleaseVersion.ps1')

$safeTag = $Tag.Trim()
$commit = Assert-WinMintReleaseWorktree -RepoRoot $repoRoot -Tag $safeTag
$version = Convert-WinMintReleaseTag -Tag $safeTag -Commit $commit
$publishProps = Get-WinMintDotnetPublishProperties -Version $version

if (-not [System.IO.Path]::IsPathRooted($StageRoot)) {
    $StageRoot = Join-Path $repoRoot $StageRoot
}
if (Test-Path -LiteralPath $StageRoot) {
    Remove-Item -LiteralPath $StageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $StageRoot | Out-Null

$cliOut = Join-Path $StageRoot 'bin\cli'
$wizOut = Join-Path $StageRoot 'bin\wizard'
$provOut = Join-Path $StageRoot 'artifacts\provisioning'
$winPeOut = Join-Path $StageRoot 'artifacts\winpe-apply'

Write-Host "Publishing Cli ($Runtime, self-contained)…"
dotnet publish (Join-Path $repoRoot 'src\WinMint.Cli\WinMint.Cli.csproj') `
    -c $Configuration -r $Runtime --self-contained true `
    -p:PublishSingleFile=false `
    @publishProps `
    -o $cliOut
if ($LASTEXITCODE -ne 0) { throw "Cli publish failed: $LASTEXITCODE" }

Write-Host "Publishing Wizard ($Runtime, self-contained)…"
dotnet publish (Join-Path $repoRoot 'src\WinMint.Wizard\WinMint.Wizard.csproj') `
    -c $Configuration -r $Runtime --self-contained true `
    -p:PublishSingleFile=false `
    @publishProps `
    -o $wizOut
if ($LASTEXITCODE -ne 0) { throw "Wizard publish failed: $LASTEXITCODE" }

Write-Host 'Publishing Provisioning Supervisor (AOT)…'
dotnet publish (Join-Path $repoRoot 'src\WinMint.Provisioning\WinMint.Provisioning.csproj') `
    -c $Configuration `
    @publishProps `
    -o $provOut
if ($LASTEXITCODE -ne 0) { throw "Provisioning publish failed: $LASTEXITCODE" }

Write-Host 'Publishing WinPE apply helper (AOT WinExe)…'
dotnet publish (Join-Path $repoRoot 'src\WinMint.WinPeApply\WinMint.WinPeApply.csproj') `
    -c $Configuration `
    @publishProps `
    -o $winPeOut
if ($LASTEXITCODE -ne 0) { throw "WinPeApply publish failed: $LASTEXITCODE" }

Copy-Item -LiteralPath (Join-Path $repoRoot 'Justfile') -Destination $StageRoot
Copy-Item -LiteralPath (Join-Path $repoRoot 'config') -Destination (Join-Path $StageRoot 'config') -Recurse
Copy-Item -LiteralPath (Join-Path $repoRoot 'servicing') -Destination (Join-Path $StageRoot 'servicing') -Recurse
Copy-Item -LiteralPath (Join-Path $repoRoot 'payload') -Destination (Join-Path $StageRoot 'payload') -Recurse
Copy-Item -LiteralPath (Join-Path $repoRoot 'samples') -Destination (Join-Path $StageRoot 'samples') -Recurse
New-Item -ItemType Directory -Force -Path (Join-Path $StageRoot 'tools\apply') | Out-Null
Copy-Item -Path (Join-Path $repoRoot 'tools\apply\*.ps1') -Destination (Join-Path $StageRoot 'tools\apply')
Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\Resolve-OutputIso.ps1') `
    -Destination (Join-Path $StageRoot 'tools\Resolve-OutputIso.ps1')
New-Item -ItemType Directory -Force -Path (Join-Path $StageRoot 'tools\host') | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\host\Invoke-WinMintCli.ps1') `
    -Destination (Join-Path $StageRoot 'tools\host\Invoke-WinMintCli.ps1')
Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\host\Invoke-PackagesCheck.ps1') `
    -Destination (Join-Path $StageRoot 'tools\host\Invoke-PackagesCheck.ps1')
Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\host\Invoke-WinMintWizard.ps1') `
    -Destination (Join-Path $StageRoot 'tools\host\Invoke-WinMintWizard.ps1')

Write-Host "Unsigned staging at $StageRoot (not Authenticode)"
