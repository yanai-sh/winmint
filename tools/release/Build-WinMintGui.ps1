#Requires -Version 7.3
[CmdletBinding()]
param(
    [string]$RustTarget = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:WinMintRepositoryRoot = $root
. (Join-Path $root 'src\runtime\image\Core.ps1')

$launcher = Get-WinMintPath -Name GuiToolsRoot -ChildPath 'Start-GuiDev.ps1'
& $launcher -Release -BuildOnly -RustTarget $RustTarget
if ($LASTEXITCODE -ne 0) {
    throw "GUI release build failed with exit code $LASTEXITCODE."
}

$manifest = Get-WinMintPath -Name GuiCargoToml
$metadata = & cargo metadata --manifest-path $manifest --format-version 1 --no-deps | ConvertFrom-Json
$targetDirectory = [string]$metadata.target_directory
$profileDirectory = if ([string]::IsNullOrWhiteSpace($RustTarget)) {
    Join-Path $targetDirectory 'release'
} else {
    Join-Path (Join-Path $targetDirectory $RustTarget) 'release'
}

$sourceExe = Join-Path $profileDirectory 'winmint-gui.exe'
if (-not (Test-Path -LiteralPath $sourceExe -PathType Leaf)) {
    throw "GUI build completed but executable was not found: $sourceExe"
}

$destination = Get-WinMintPath -Name GuiBinary
$destinationDirectory = Split-Path -Parent $destination
New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
Copy-Item -LiteralPath $sourceExe -Destination $destination -Force
Write-Host "GUI binary: $destination"
