#Requires -Version 7.3
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:root = $root
. (Join-Path $root 'tests\contract\TestFixtures.ps1')
. (Join-Path $root 'src\runtime\image\WinMint.ps1')
Initialize-WinMintEngine -RepositoryRoot $root -DryRun

$failures = [System.Collections.Generic.List[string]]::new()

function Add-PayloadStoreFailure {
    param([string]$Message)
    $script:failures.Add($Message) | Out-Null
}

$cacheFile = $null
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('winmint-payload-store-' + [Guid]::NewGuid().ToString('n'))
try {
    $downloadDir = Join-Path (Get-Win11IsoDependencyCacheRoot) 'downloads'
    $null = New-Item -ItemType Directory -Path $downloadDir -Force
    $cacheFile = Join-Path $downloadDir ('WinMintPayloadStoreTest-1.2.3-' + [Guid]::NewGuid().ToString('n') + '.zip')
    Set-Content -LiteralPath $cacheFile -Value 'payload-store-cache-fixture' -Encoding ASCII

    $payload = Resolve-WinMintCachedPayload `
        -Name 'payload-store-fixture' `
        -Patterns @([IO.Path]::GetFileName($cacheFile)) `
        -VersionRegex 'WinMintPayloadStoreTest-(?<Version>\d+\.\d+\.\d+)-' `
        -HashLabel 'payload-store-fixture'

    if ($payload.Path -ne $cacheFile -or $payload.SourceStatus -ne 'cache' -or $payload.CleanupPolicy -ne 'keep') {
        Add-PayloadStoreFailure 'Expected cached payload resolution to preserve path, source status, and keep cleanup policy.'
    }
    if ($payload.Version -ne 'v1.2.3') {
        Add-PayloadStoreFailure "Expected cached payload version v1.2.3, got '$($payload.Version)'."
    }
    if ([string]::IsNullOrWhiteSpace([string]$payload.Sha256) -or [long]$payload.SizeBytes -le 0) {
        Add-PayloadStoreFailure 'Expected cached payload result to include SHA-256 and size facts.'
    }

    $profile = New-WinMintBuildProfile -Settings @{
        Profile = 'WinMint'
        ISOPath = (Get-WinMintTestOfficialIsoFixturePath)
        Architecture = 'arm64'
        ComputerName = 'WinMint'
        AccountName = 'dev'
        DriverSource = 'None'
        DriverPath = ''
    }
    $config = New-WinMintBuildConfig -BuildProfile $profile
    Initialize-WinMintBuildManifest -Config $config
    Add-WinMintManifestPayloadFact -Payload $payload
    $null = New-Item -ItemType Directory -Path $tempRoot -Force
    $manifestPath = Save-WinMintBuildManifest -OutputDir $tempRoot -DryRun
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($manifest.payloads).Count -ne 1 -or [string]$manifest.payloads[0].name -ne 'payload-store-fixture') {
        Add-PayloadStoreFailure 'Expected payload-store manifest fact emission to write one payload entry.'
    }

    $outside = Join-Path $tempRoot 'outside-payload.bin'
    Set-Content -LiteralPath $outside -Value 'outside-cache' -Encoding ASCII
    $outsidePayload = New-WinMintPayloadResult `
        -Name 'outside-cache' `
        -Path $outside `
        -SourceUrl 'file:outside-cache' `
        -Version 'local' `
        -SourceStatus local `
        -CleanupPolicy delete-if-outside-cache `
        -HashLabel 'outside-cache'
    Remove-WinMintPayloadResult -Payload $outsidePayload
    if (Test-Path -LiteralPath $outside) {
        Add-PayloadStoreFailure 'Expected payload cleanup to delete files outside the dependency cache.'
    }

    Remove-WinMintPayloadResult -Payload $payload
    if (-not (Test-Path -LiteralPath $cacheFile)) {
        Add-PayloadStoreFailure 'Expected payload cleanup to keep files inside the dependency cache.'
    }
}
finally {
    if ($cacheFile -and (Test-Path -LiteralPath $cacheFile)) {
        Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    $script:WinMintBuildManifest = $null
}

if ($failures.Count -gt 0) {
    throw "Payload store contract failed:`n$($failures -join "`n")"
}

Write-Host 'Payload store contract smoke passed.'
