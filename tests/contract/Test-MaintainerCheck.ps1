#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools\host\WinMint-MaintainerCheck.ps1')

function Assert-True([bool] $Cond, [string] $Msg) {
    if (-not $Cond) { throw $Msg }
}

# --- UBR parse ---
Assert-True ((ConvertFrom-WinMintWimImageUbr -Version '10.0.26200.6584' -ServicePackBuild '26200') -eq 6584) 'version UBR'
Assert-True ((ConvertFrom-WinMintWimImageUbr -Version '10.0.26200.1' -ServicePackBuild '26200') -eq 1) 'version rev 1'
Assert-True ((ConvertFrom-WinMintWimImageUbr -Version '10.0.26200.1' -ServicePackBuild '8037') -eq 8037) 'SP build UBR'

# --- advisory gate ---
$adv = Test-WinMintMaintainerIsoAdvisory -WimUbr 100 -CatalogUbr 9457 -IsoSha256 'aa' -SnapshotIsoSha256 'aa'
Assert-True $adv.Advisory 'advisory when gap and same hash'
$noSnap = Test-WinMintMaintainerIsoAdvisory -WimUbr 100 -CatalogUbr 9457 -IsoSha256 'aa' -SnapshotIsoSha256 ''
Assert-True (-not $noSnap.Advisory) 'no advisory without prior snapshot hash'
$small = Test-WinMintMaintainerIsoAdvisory -WimUbr 9000 -CatalogUbr 9457 -IsoSha256 'aa' -SnapshotIsoSha256 'aa'
Assert-True (-not $small.Advisory) 'no advisory when gap below threshold'

# --- ISO check with mocked mount ---
$fixture = [pscustomobject]@{
    sourceIso = [pscustomobject]@{
        path         = 'C:\fake\Win11_25H2_English_Arm64_v2.iso'
        train        = '25H2'
        sha256       = 'deadbeef'
        architecture = 'ARM64'
    }
}

$fakeIso = Join-Path $repo '.scratch\contract-maintainer-fake.iso'
New-Item -ItemType Directory -Force -Path (Split-Path $fakeIso) | Out-Null
Set-Content -LiteralPath $fakeIso -Value 'contract-maintainer-iso-bytes' -NoNewline
$fixture.sourceIso.path = $fakeIso
$fixture.sourceIso.sha256 = (Get-WinMintIsoSha256Hex -Path $fakeIso)

$mockRows = {
    param([string] $Path)
    if ($Path -ne $fakeIso) { throw "unexpected iso $Path" }
    return , @(
        [ordered]@{
            index        = 3
            name         = 'Windows 11 Pro'
            architecture = 'ARM64'
            edition      = 'Professional'
            version      = '10.0.26200.6584'
            build        = '26200'
            languages    = 'en-US'
        }
    )
}

$snapPath = Join-Path $repo '.scratch\contract-maintainer-snap.json'
@{ isoSha256 = $fixture.sourceIso.sha256 } | ConvertTo-Json | Set-Content -LiteralPath $snapPath -Encoding utf8

$isoOk = Invoke-WinMintMaintainerIsoCheck `
    -Fixture $fixture `
    -CatalogUbr 9457 `
    -SnapshotPath $snapPath `
    -IndexListProvider $mockRows
Assert-True $isoOk.Advisory 'iso check advisory with mock wim'
Assert-True ($isoOk.WimUbr -eq 6584) 'mock wim ubr'

$fixtureBadSha = [pscustomobject]@{
    sourceIso = [pscustomobject]@{
        path   = $fakeIso
        train  = '25H2'
        sha256 = '0000000000000000000000000000000000000000000000000000000000000000'
    }
}
$warn = Invoke-WinMintMaintainerIsoCheck `
    -Fixture $fixtureBadSha `
    -CatalogUbr 6600 `
    -SnapshotPath $snapPath `
    -IndexListProvider $mockRows
Assert-True ($warn.Messages.Count -ge 1) 'fixture sha mismatch message'
Assert-True (-not $warn.Advisory) 'fixture mismatch alone is not stale-ISO advisory'

# --- core orchestration (mock catalog + skip iso path via SkipIso false but mock index) ---
$fakeRoot = Join-Path ([IO.Path]::GetTempPath()) ("maintainer-core-" + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $fakeRoot 'tests\fixtures') | Out-Null
    $fixture | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $fakeRoot 'tests\fixtures\maintainer-host.json')
    $catalogMock = {
        param([string] $Version, [string] $Architecture, [int] $ImageUbr)
        [pscustomobject]@{
            Kb         = 'KB5129195'
            Title      = '2026-09 Cumulative Update for Windows 11 Version 25H2 for ARM64-based Systems (KB5129195) (26200.9457)'
            PackageUbr = 9457
        }
    }
    $snapOut = Join-Path $fakeRoot '.scratch\maintainer\last-check.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $snapOut) | Out-Null
    @{ isoSha256 = $fixture.sourceIso.sha256 } | ConvertTo-Json | Set-Content -LiteralPath $snapOut -Encoding utf8
    $core = Invoke-WinMintMaintainerCheckCore `
        -RepoRoot $fakeRoot `
        -ModuleRoot $repo `
        -SnapshotPath $snapOut `
        -CatalogResolver $catalogMock `
        -IndexListProvider $mockRows
    Assert-True ($core.ExitCode -eq 2) 'exit 2 on iso advisory'
    Assert-True (Test-Path -LiteralPath $snapOut) 'snapshot written'
    $saved = Get-Content -LiteralPath $snapOut -Raw | ConvertFrom-Json
    Assert-True ($saved.quality[0].kb -eq 'KB5129195') 'snapshot quality kb'

    $failCatalog = {
        param([string] $Version, [string] $Architecture, [int] $ImageUbr)
        throw 'catalog down'
    }
    $fail = Invoke-WinMintMaintainerCheckCore `
        -RepoRoot $fakeRoot `
        -ModuleRoot $repo `
        -SnapshotPath (Join-Path $fakeRoot '.scratch\maintainer\fail.json') `
        -CatalogResolver $failCatalog `
        -SkipIso
    Assert-True ($fail.ExitCode -eq 1) 'exit 1 on quality failure'
}
finally {
    Remove-Item -LiteralPath $fakeIso -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $snapPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fakeRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# --- wrapper token honesty (exit 2 must not print quality-check ok) ---
$wrapper = Get-Content -LiteralPath (Join-Path $repo 'tools\host\Invoke-MaintainerCheck.ps1') -Raw -Encoding utf8
Assert-True ($wrapper -match '\[int\]\$result\.ExitCode -eq 0') 'ok token gated on exit 0'
Assert-True ($wrapper -match "maintainer-check advisory") 'advisory token present'
Assert-True ($wrapper -match "Write-Output 'quality-check ok'") 'ok token still present when exit 0'

Write-Output 'Test-MaintainerCheck ok'
