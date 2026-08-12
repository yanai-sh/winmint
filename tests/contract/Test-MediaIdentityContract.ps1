#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'servicing/Test-MediaIdentity.ps1')

$root = Join-Path ([IO.Path]::GetTempPath()) ('winmint-media-identity-' + [guid]::NewGuid().ToString('N'))
$marker = Join-Path $root '.winmint-media-identity.json'
$expected = [ordered]@{
    sourceIsoSha256 = ('a' * 64)
    wimIndex = 1
    imageName = 'Windows 11 Pro'
    architecture = 'arm64'
    edition = 'Professional'
    build = '26100'
}
$snapshot = [ordered]@{
    IndexCount = 1
    Name = 'Windows 11 Pro'
    Architecture = 'ARM64'
    Edition = 'Professional'
    Build = '26100'
}

function Assert-False {
    param([bool] $Value, [string] $Case)
    if ($Value) { throw "$Case unexpectedly accepted media reuse" }
}

try {
    New-Item -ItemType Directory -Force -Path $root | Out-Null

    Assert-False `
        (Test-WinMintMediaIdentity -MarkerPath $marker -ExpectedIdentity $expected -Snapshot $snapshot) `
        'missing marker'

    Set-Content -LiteralPath $marker -Value '{' -Encoding utf8
    Assert-False `
        (Test-WinMintMediaIdentity -MarkerPath $marker -ExpectedIdentity $expected -Snapshot $snapshot) `
        'malformed marker'

    $mismatched = [ordered]@{
        schemaVersion = 'winmint.media-identity/v1'
        sourceIsoSha256 = ('b' * 64)
        wimIndex = 1
        imageName = 'Windows 11 Pro'
        architecture = 'arm64'
        build = '26100'
    }
    $mismatched | ConvertTo-Json | Set-Content -LiteralPath $marker -Encoding utf8
    Assert-False `
        (Test-WinMintMediaIdentity -MarkerPath $marker -ExpectedIdentity $expected -Snapshot $snapshot) `
        'mismatched marker'

    Write-WinMintMediaIdentity -MarkerPath $marker -ExpectedIdentity $expected
    if (-not (Test-WinMintMediaIdentity -MarkerPath $marker -ExpectedIdentity $expected -Snapshot $snapshot)) {
        throw 'matching marker and WIM metadata did not allow reuse'
    }

    $wrongWim = [ordered]@{}
    foreach ($key in $snapshot.Keys) { $wrongWim[$key] = $snapshot[$key] }
    $wrongWim['Name'] = 'Windows 11 Home'
    Assert-False `
        (Test-WinMintMediaIdentity -MarkerPath $marker -ExpectedIdentity $expected -Snapshot $wrongWim) `
        'matching marker with mismatched staged WIM'

    $document = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
    if ($document.schemaVersion -cne 'winmint.media-identity/v1') { throw 'marker schema mismatch' }
    if ($document.PSObject.Properties.Name -contains 'edition') { throw 'marker grew beyond v1 contract' }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Media identity contract tests passed.'
