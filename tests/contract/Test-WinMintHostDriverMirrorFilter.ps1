#Requires -Version 7.6
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'src\runtime\image\WinMint.ps1')
Initialize-WinMintEngine -RepositoryRoot $root -DryRun

$failures = [System.Collections.Generic.List[string]]::new()
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("winmint-driver-filter-{0}" -f [Guid]::NewGuid().ToString('n'))
$source = Join-Path $tempRoot 'source'
$dest = Join-Path $tempRoot 'dest'
$null = New-Item -ItemType Directory -Path (Join-Path $source 'net'), (Join-Path $source 'display') -Force

@'
[Version]
Signature="$Windows NT$"
Class=Net
'@ | Set-Content -LiteralPath (Join-Path $source 'net\net.inf') -Encoding ASCII

@'
[Version]
Signature="$Windows NT$"
Class=Display
'@ | Set-Content -LiteralPath (Join-Path $source 'display\display.inf') -Encoding ASCII

$included = Copy-WinMintSetupCriticalDrivers -DriverSource $source -Destination $dest
if ($included -ne 1) {
    $failures.Add("Expected setup-critical filter to keep one INF; got $included") | Out-Null
}
if (-not (Test-Path -LiteralPath (Join-Path $dest 'net\net.inf'))) {
    $failures.Add('Expected net.inf in filtered host mirror output.') | Out-Null
}
if (Test-Path -LiteralPath (Join-Path $dest 'display\display.inf')) {
    $failures.Add('Expected display.inf to be excluded from setup-critical filter.') | Out-Null
}

Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}
Write-Host 'Host driver mirror filter contract: OK'
exit 0
