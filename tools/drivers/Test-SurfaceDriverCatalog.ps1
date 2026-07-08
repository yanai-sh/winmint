#Requires -Version 7.6

[CmdletBinding()]
param(
    [switch]$DownloadPackages
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\runtime\image\WinMint.ps1')
Initialize-WinMintEngine -RepositoryRoot $repoRoot

$results = [System.Collections.Generic.List[object]]::new()
foreach ($device in Get-WinMintSurfaceDriverDeviceCatalog) {
    Write-Host "Checking $($device.id) -> $($device.detailsUrl)"
    $asset = Resolve-WinMintSurfaceDriverDownloadAsset -Device $device
    $head = Invoke-WebRequest -Method Head -Uri ([string]$asset.downloadUrl) -UseBasicParsing
    $record = [ordered]@{
        id = [string]$device.id
        name = [string]$device.name
        architecture = [string]$device.architecture
        detailsUrl = [string]$device.detailsUrl
        downloadUrl = [string]$asset.downloadUrl
        fileName = [string]$asset.fileName
        statusCode = [int]$head.StatusCode
        contentLength = [string]($head.Headers['Content-Length'] | Select-Object -First 1)
        etag = [string]($head.Headers['ETag'] | Select-Object -First 1)
    }

    if ($DownloadPackages) {
        $sessionRoot = Join-Path ([IO.Path]::GetTempPath()) ('winmint-surface-driver-smoke-' + [Guid]::NewGuid().ToString('n'))
        try {
            $package = Save-WinMintSurfaceDriverPackage -Device $device -DestinationDirectory $sessionRoot
            $record.sha256 = [string]$package.sha256
            $record.signatureValid = $true
        }
        finally {
            Remove-Item -LiteralPath $sessionRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $results.Add([pscustomobject]$record) | Out-Null
}

$results | ConvertTo-Json -Depth 8
