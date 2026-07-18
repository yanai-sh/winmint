#Requires -Version 7.6

function Get-WinMintTestFixturePath {
    param(
        [Parameter(Mandatory)][string]$RelativePath
    )

    $path = Join-Path $root (Join-Path 'tests\fixtures' $RelativePath)
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required test fixture is missing: $path"
    }
    return $path
}

function Get-WinMintTestIsoFixturePath {
    # Primary: %LOCALAPPDATA%\WinMint\source-iso\ — outside the repo, never touched by git clean.
    $localIsoDir = Join-Path $env:LOCALAPPDATA 'WinMint\source-iso'
    if (Test-Path -LiteralPath $localIsoDir) {
        $localIso = Get-ChildItem -LiteralPath $localIsoDir -Filter '*.iso' -File |
            Where-Object { $_.Length -gt 0 } |
            Sort-Object Name |
            Select-Object -First 1
        if ($localIso) {
            return $localIso.FullName
        }
    }

    # Fallback: tests/fixtures/iso/ — only used when the local cache is absent.
    $fixtureDir = Get-WinMintTestFixturePath -RelativePath 'iso'
    $fixtureIso = Get-ChildItem -LiteralPath $fixtureDir -Filter '*.iso' -File |
        Where-Object { $_.Length -gt 0 } |
        Sort-Object Name |
        Select-Object -First 1
    if ($fixtureIso) {
        return $fixtureIso.FullName
    }

    throw "No valid Windows source ISO found. Place the official Windows 11 ARM64 ISO in: $localIsoDir"
}

function Get-WinMintTestOfficialIsoFixturePath {
    Get-WinMintTestIsoFixturePath
}

