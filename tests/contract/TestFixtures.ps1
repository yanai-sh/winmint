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

function Get-WinMintTestUupDumpIsoFixturePath {
    $fixtureDir = Get-WinMintTestFixturePath -RelativePath 'uupdump'
    $iso = Get-ChildItem -LiteralPath $fixtureDir -Filter '*.iso' -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        Select-Object -First 1
    if ($iso) { return $iso.FullName }

    $preparedRoot = Join-Path $root 'output\.uup'
    $preparedIso = if (Test-Path -LiteralPath $preparedRoot -PathType Container) {
        Get-ChildItem -LiteralPath $preparedRoot -Filter '*.iso' -Recurse -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
    } else {
        $null
    }
    if ($preparedIso) { return $preparedIso.FullName }

    throw "Required UUP Dump ISO test fixture is missing. Put the generated UUP ISO under: $fixtureDir"
}

function Get-WinMintTestUupDumpZipFixturePath {
    $fixtureDir = Get-WinMintTestFixturePath -RelativePath 'uupdump'
    $zip = Get-ChildItem -LiteralPath $fixtureDir -Filter '*.zip' -File |
        Sort-Object Name |
        Select-Object -First 1
    if (-not $zip) {
        throw "Required UUP Dump zip test fixture is missing under: $fixtureDir"
    }
    return $zip.FullName
}

function Get-WinMintTestUupDumpPreparedIsoFixturePath {
    $zip = Get-WinMintTestUupDumpZipFixturePath
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    $sourceDir = Join-Path (Join-Path (Join-Path $root 'output\.uup') $hash.Substring(0, 24)) 'source'
    if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) { return '' }

    $iso = Get-ChildItem -LiteralPath $sourceDir -Filter '*.iso' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if (-not $iso) { return '' }
    return $iso.FullName
}
