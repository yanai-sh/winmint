#requires -Version 7.6
param(
    [Parameter(Mandatory)] [string] $StageRoot,
    [Parameter(Mandatory)] $Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$owned = @(
    'bin\cli\WinMint.Cli.exe'
    'bin\wizard\WinMint.Wizard.exe'
    'artifacts\provisioning\WinMint.Provisioning.exe'
    'artifacts\provisioning\Supervisor.exe'
    'artifacts\winpe-apply\WinMintApply.exe'
)

$found = 0
foreach ($rel in $owned) {
    $path = Join-Path $StageRoot $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $found++
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($path)
    if ($info.ProductName -cne 'WinMint') { throw "$rel ProductName='$($info.ProductName)'" }
    if ($info.CompanyName -cne 'WinMint contributors') { throw "$rel CompanyName='$($info.CompanyName)'" }
    if ($info.ProductVersion -notlike "$($Version.Version)*") { throw "$rel ProductVersion='$($info.ProductVersion)'" }
    $fileVersion = $info.FileVersion
    if ($fileVersion -ne $Version.FileVersion -and $fileVersion -ne $Version.Version) {
        throw "$rel FileVersion='$fileVersion'"
    }
}
if ($found -eq 0) { throw "no WinMint-owned PE under $StageRoot" }
Write-Output "Test-WinMintVersionMetadata ok ($found PE)"
