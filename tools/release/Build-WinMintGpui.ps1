#Requires -Version 7.3
[CmdletBinding()]
param(
    [string]$RustTarget = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:WinMintRepositoryRoot = $root
. (Join-Path $root 'src\WinMint\Core.ps1')

$launcher = Get-WinMintPath -Name GpuiTool -ChildPath 'Start-GpuiLab.ps1'
& $launcher -Release -BuildOnly -RustTarget $RustTarget
if ($LASTEXITCODE -ne 0) {
    throw "GPUI release build failed with exit code $LASTEXITCODE."
}

$manifest = Get-WinMintPath -Name GpuiCargoToml
$metadata = & cargo metadata --manifest-path $manifest --format-version 1 --no-deps | ConvertFrom-Json
$targetDirectory = [string]$metadata.target_directory
$profileDirectory = if ([string]::IsNullOrWhiteSpace($RustTarget)) {
    Join-Path $targetDirectory 'release'
} else {
    Join-Path (Join-Path $targetDirectory $RustTarget) 'release'
}

$sourceExe = Join-Path $profileDirectory 'winmint-gpui.exe'
if (-not (Test-Path -LiteralPath $sourceExe -PathType Leaf)) {
    throw "GPUI build completed but executable was not found: $sourceExe"
}

$destination = Get-WinMintPath -Name GpuiBinary
$destinationDirectory = Split-Path -Parent $destination
New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
Copy-Item -LiteralPath $sourceExe -Destination $destination -Force
Write-Host "GPUI binary: $destination"
