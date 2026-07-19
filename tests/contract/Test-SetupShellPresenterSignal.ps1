#Requires -Version 7.6
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [System.Collections.Generic.List[string]]::new()
function Add-PresenterFailure([string]$Message) { $failures.Add($Message) | Out-Null }

. (Join-Path $root 'tools\vm\lib\VmEvidence.ps1')

function New-PresenterEvidenceFixture {
    param(
        [string]$SetupShellLog = '',
        [string]$FirstLogonLog = 'host-start presenter=native pid=1',
        [string]$ControlPhase = 'complete'
    )
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("winmint-presenter-" + [guid]::NewGuid().ToString('n'))
    $null = New-Item -ItemType Directory -Path $dir -Force
    Set-Content -LiteralPath (Join-Path $dir 'FirstLogon.log') -Value $FirstLogonLog -Encoding UTF8
    if (-not [string]::IsNullOrWhiteSpace($SetupShellLog)) {
        Set-Content -LiteralPath (Join-Path $dir 'SetupShell.log') -Value $SetupShellLog -Encoding UTF8
    }
    Set-Content -LiteralPath (Join-Path $dir 'setup-shell-control.json') -Value (@{ phase = $ControlPhase } | ConvertTo-Json) -Encoding UTF8
    return $dir
}

$watch = New-WinMintVmSetupShellWatch
$watch.liveUi = $true
$watch.desktopGuard = $true
$watch.screenshotCaptured = $true
$png = Join-Path ([System.IO.Path]::GetTempPath()) ("winmint-presenter-" + [guid]::NewGuid().ToString('n') + '.png')
[System.IO.File]::WriteAllBytes($png, [byte[]]::new(9000))
$watch.screenshotPath = $png

$goodDir = New-PresenterEvidenceFixture -SetupShellLog "host=native`npresenter=gdi-fallback`nrender ready"
$watch.screenshotPath = $png
$good = Test-WinMintSetupShellAcceptanceEvidence -Watch $watch -EvidenceDir $goodDir -AcceptanceTier Smoke
if (-not $good.plumbingOk) {
    Add-PresenterFailure "expected plumbingOk for host=native presenter=gdi-fallback; got: $($good.plumbingFailures -join ' | ')"
}
if ([string]$good.meta.host -ne 'native') {
    Add-PresenterFailure "meta.host must be native, got '$($good.meta.host)'"
}
if ([string]$good.meta.presenter -ne 'gdi-fallback') {
    Add-PresenterFailure "meta.presenter must be gdi-fallback, got '$($good.meta.presenter)'"
}

$missingHostDir = New-PresenterEvidenceFixture -SetupShellLog "presenter=gdi-fallback"
$missingHost = Test-WinMintSetupShellAcceptanceEvidence -Watch $watch -EvidenceDir $missingHostDir -AcceptanceTier Smoke
if ($missingHost.plumbingOk) {
    Add-PresenterFailure 'blank/missing host must be a plumbing failure.'
}
if (-not (@($missingHost.plumbingFailures) -match 'host field blank/missing').Count) {
    Add-PresenterFailure 'missing host failure message must mention host field blank/missing.'
}

$missingPresenterDir = New-PresenterEvidenceFixture -SetupShellLog 'host=native'
$missingPresenterSmoke = Test-WinMintSetupShellAcceptanceEvidence -Watch $watch -EvidenceDir $missingPresenterDir -AcceptanceTier Smoke
if (-not $missingPresenterSmoke.plumbingOk) {
    Add-PresenterFailure "Smoke missing presenter should warn, not plumbing-fail; got: $($missingPresenterSmoke.plumbingFailures -join ' | ')"
}
if (-not (@($missingPresenterSmoke.meta.warnings) -match 'presenter field blank/missing').Count) {
    Add-PresenterFailure 'Smoke missing presenter must record a warning on meta.warnings.'
}

$missingPresenterFull = Test-WinMintSetupShellAcceptanceEvidence -Watch $watch -EvidenceDir $missingPresenterDir -AcceptanceTier Full
if ($missingPresenterFull.evidenceOk) {
    Add-PresenterFailure 'Full tier missing presenter must be an evidence failure.'
}

Remove-Item -LiteralPath $goodDir, $missingHostDir, $missingPresenterDir, $png -Recurse -Force -ErrorAction SilentlyContinue

$evidenceText = Get-Content -LiteralPath (Join-Path $root 'tools\vm\lib\VmEvidence.ps1') -Raw
foreach ($expected in @('meta.host', 'meta.presenter', 'host field blank/missing', 'presenter field blank/missing')) {
    if ($evidenceText -notmatch [regex]::Escape($expected)) {
        Add-PresenterFailure "VmEvidence presenter signal should contain '$expected'."
    }
}

if ($failures.Count -gt 0) {
    Write-Host 'Setup-shell presenter signal contract: FAIL'
    $failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}
Write-Host 'Setup-shell presenter signal contract: OK'
exit 0
