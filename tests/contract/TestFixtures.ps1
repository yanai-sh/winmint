#Requires -Version 7.3

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
    $fixtureDir = Get-WinMintTestFixturePath -RelativePath 'iso'
    $iso = Get-ChildItem -LiteralPath $fixtureDir -Filter '*.iso' -File |
        Sort-Object Name |
        Select-Object -First 1
    if (-not $iso) {
        throw "Required Windows ISO test fixture is missing under: $fixtureDir"
    }
    return $iso.FullName
}

function Get-WinMintTestOfficialIsoFixturePath {
    Get-WinMintTestIsoFixturePath
}
