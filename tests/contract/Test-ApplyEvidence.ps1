#requires -Version 7.6
# S5 bar through Assert-ApplyEvidence on the fixture adapter. No Hyper-V.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$assert = Join-Path $repo 'tools\apply\Assert-ApplyEvidence.ps1'
$fixture = Join-Path $repo 'tests\fixtures\apply-evidence'
. (Join-Path $repo 'tools\host\Assert-ImageEvidenceCore.ps1')
if (-not (Test-WinMintIsGateB -Lane 'Release' -PackageStrict:$true)) {
    throw 'Test-WinMintIsGateB Release+strict must be true (Apply lane predicate; not full HostReview.IsGateB)'
}
if (Test-WinMintIsGateB -Lane 'Release' -PackageStrict:$false) {
    throw 'soft Release must not be Gate B'
}
if (Test-WinMintIsGateB -Lane 'Test' -PackageStrict:$true) {
    throw 'Test lane must not be Gate B'
}

function Copy-Tree([string] $Source, [string] $Dest) {
    foreach ($file in [IO.Directory]::GetFiles($Source, '*', [IO.SearchOption]::AllDirectories)) {
        $rel = [IO.Path]::GetRelativePath($Source, $file)
        $target = Join-Path $Dest $rel
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
        [IO.File]::Copy($file, $target, $true)
    }
}

function Invoke-ApplyAssert {
    param(
        [string] $Work,
        [string] $RequireLane = '',
        [switch] $ExpectFuPosture
    )
    try {
        $splat = @{
            WorkDirectory    = $Work
            ExpectDrivers    = $true
            RequireOutputIso = $true
        }
        if ($RequireLane) { $splat.RequireLane = $RequireLane }
        if ($ExpectFuPosture) { $splat.ExpectFuPosture = $true }
        $null = & $assert @splat
        return [pscustomobject]@{ Code = 0; Err = '' }
    }
    catch {
        return [pscustomobject]@{ Code = 1; Err = [string]$_.Exception.Message }
    }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('winmint-s5-' + [guid]::NewGuid().ToString('N'))
try {
    $ok = Join-Path $root 'ok'
    Copy-Tree $fixture $ok
    $r = Invoke-ApplyAssert $ok
    if ($r.Code -ne 0) { throw "fixture must pass: $($r.Err)" }
    $json = Get-Content -LiteralPath (Join-Path $ok 'apply-acceptance.json') -Raw
    if ($json -notmatch 'winmint.apply.acceptance/v1') { throw 'acceptance schema' }
    if ($json -notmatch '"preWipeOnly": true') { throw 'preWipeOnly' }
    if ($json -notmatch '"driverIncludedCount": 12') { throw 'driver count' }
    if ($json -notmatch '"firmwareExcluded": true') { throw 'firmware excluded' }

    $nodriver = Join-Path $root 'nodriver'
    Copy-Tree $fixture $nodriver
    $ev = Get-Content -LiteralPath (Join-Path $nodriver 'evidence.json') -Raw | ConvertFrom-Json
    $ev.digests.PSObject.Properties.Remove('drivers.deviceId')
    ($ev | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $nodriver 'evidence.json') -Encoding utf8
    $r = Invoke-ApplyAssert $nodriver
    if ($r.Code -eq 0) { throw 'missing driver digest must fail' }
    if ($r.Err -notmatch 'Driver digest missing') { throw "driver digest message: $($r.Err)" }

    $fw = Join-Path $root 'fw'
    Copy-Tree $fixture $fw
    $inv = Get-Content -LiteralPath (Join-Path $fw 'logs\WinMint-DriverInventory.json') -Raw | ConvertFrom-Json
    $inv.records[1].decision = 'includeOffline'
    ($inv | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $fw 'logs\WinMint-DriverInventory.json') -Encoding utf8
    $r = Invoke-ApplyAssert $fw
    if ($r.Code -eq 0) { throw 'firmware include must fail' }
    if ($r.Err -notmatch 'firmware') { throw "firmware message: $($r.Err)" }

    $stale = Join-Path $root 'stale'
    Copy-Tree $fixture $stale
    $ev = Get-Content -LiteralPath (Join-Path $stale 'evidence.json') -Raw | ConvertFrom-Json
    $ev.digests.'outputIso.sha256' = 'deadbeef'
    ($ev | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $stale 'evidence.json') -Encoding utf8
    $r = Invoke-ApplyAssert $stale
    if ($r.Code -eq 0) { throw 'stale outputIso digest must fail' }
    if ($r.Err -notmatch 'outputIso.sha256 mismatch') { throw "outputIso message: $($r.Err)" }

    $lane = Join-Path $root 'lane'
    Copy-Tree $fixture $lane
    $r = Invoke-ApplyAssert $lane -RequireLane Release
    if ($r.Code -eq 0) { throw 'Test fixture must fail RequireLane Release' }
    if ($r.Err -notmatch 'lane must be Release') { throw "lane message: $($r.Err)" }

    $nops = Join-Path $root 'nops'
    Copy-Tree $fixture $nops
    $ev = Get-Content -LiteralPath (Join-Path $nops 'evidence.json') -Raw | ConvertFrom-Json
    $ev.lane = 'Release'
    $ev.PSObject.Properties.Remove('packageStrict')
    ($ev | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $nops 'evidence.json') -Encoding utf8
    $r = Invoke-ApplyAssert $nops -RequireLane Release
    if ($r.Code -eq 0) { throw 'Release without packageStrict must fail' }
    if ($r.Err -notmatch 'packageStrict') { throw "packageStrict missing message: $($r.Err)" }

    $psfalse = Join-Path $root 'psfalse'
    Copy-Tree $fixture $psfalse
    $ev = Get-Content -LiteralPath (Join-Path $psfalse 'evidence.json') -Raw | ConvertFrom-Json
    $ev.lane = 'Release'
    $ev | Add-Member -NotePropertyName packageStrict -NotePropertyValue $false -Force
    ($ev | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $psfalse 'evidence.json') -Encoding utf8
    $r = Invoke-ApplyAssert $psfalse -RequireLane Release
    if ($r.Code -eq 0) { throw 'Release packageStrict false must fail' }
    if ($r.Err -notmatch 'packageStrict') { throw "packageStrict false message: $($r.Err)" }

    $nofu = Join-Path $root 'nofu'
    Copy-Tree $fixture $nofu
    $r = Invoke-ApplyAssert $nofu -ExpectFuPosture
    if ($r.Code -eq 0) { throw 'ExpectFuPosture without digests must fail' }
    if ($r.Err -notmatch 'FU posture digest missing') { throw "FU digest message: $($r.Err)" }

    $fu = Join-Path $root 'fu'
    Copy-Tree $fixture $fu
    $ev = Get-Content -LiteralPath (Join-Path $fu 'evidence.json') -Raw | ConvertFrom-Json
    $ev.lane = 'Release'
    $ev | Add-Member -NotePropertyName packageStrict -NotePropertyValue $true -Force
    $ev.digests | Add-Member -NotePropertyName 'policy.cloudContent.DisableWindowsConsumerFeatures' -NotePropertyValue '1' -Force
    $ev.digests | Add-Member -NotePropertyName 'policy.cloudContent.DisableSoftLanding' -NotePropertyValue '1' -Force
    $ev.digests | Add-Member -NotePropertyName 'policy.store.AutoDownload' -NotePropertyValue '2' -Force
    ($ev | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $fu 'evidence.json') -Encoding utf8
    $payload = Join-Path $fu 'payload'
    New-Item -ItemType Directory -Force -Path $payload | Out-Null
    Set-Content -LiteralPath (Join-Path $payload 'jobs.json') -Encoding utf8 -Value @'
{"jobs":[{"id":"winget.import","kind":"winget.import"},{"id":"scoop.batch","kind":"scoop.batch","packageId":"starship"},{"id":"shell.stamp","kind":"shell.stamp"}]}
'@
    Set-Content -LiteralPath (Join-Path $payload 'winget-import.json') -Encoding utf8 -Value @'
{"Sources":[{"SourceDetails":{"Name":"winget","Identifier":"Microsoft.Winget.Source_8wekyb3d8bbwe","Argument":"https://cdn.winget.microsoft.com/cache","Type":"Microsoft.PreIndexed.Package"},"Packages":[
  {"PackageIdentifier":"Git.MinGit"},
  {"PackageIdentifier":"Microsoft.PowerShell"},
  {"PackageIdentifier":"Microsoft.WindowsTerminal"},
  {"PackageIdentifier":"Microsoft.Coreutils"},
  {"PackageIdentifier":"Nilesoft.Shell"}
]}]}
'@
    $r = Invoke-ApplyAssert $fu -RequireLane Release
    if ($r.Code -ne 0) { throw "Release FU fixture must pass: $($r.Err)" }
    $acc = Get-Content -LiteralPath (Join-Path $fu 'apply-acceptance.json') -Raw
    if ($acc -notmatch '"fuPosture": true') { throw 'fuPosture true' }
    if ($acc -notmatch '"lane": "Release"') { throw 'lane Release' }

    $wslFromFile = Join-Path $root 'wsl-fromfile'
    Copy-Tree $fixture $wslFromFile
    $exp = Get-Content -LiteralPath (Join-Path $wslFromFile 'expected-evidence.json') -Raw | ConvertFrom-Json
    $exp.requiredWslPackageIds = @('NixOS')
    ($exp | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $wslFromFile 'expected-evidence.json') -Encoding utf8
    $payload = Join-Path $wslFromFile 'payload'
    New-Item -ItemType Directory -Force -Path $payload | Out-Null
    Set-Content -LiteralPath (Join-Path $payload 'jobs.json') -Encoding utf8 -Value @'
{"jobs":[{"id":"wsl.NixOS","kind":"wsl","packageId":"NixOS"}]}
'@
    $r = Invoke-ApplyAssert $wslFromFile
    if ($r.Code -ne 0) { throw "fromFile catalog installId must pass Gate B WSL assert: $($r.Err)" }

    $wslOmitted = Join-Path $root 'wsl-omitted-evidence'
    Copy-Tree $fixture $wslOmitted
    $payload = Join-Path $wslOmitted 'payload'
    New-Item -ItemType Directory -Force -Path $payload | Out-Null
    Set-Content -LiteralPath (Join-Path $payload 'jobs.json') -Encoding utf8 -Value @'
{"jobs":[{"id":"wsl.Ubuntu","kind":"wsl","packageId":"Ubuntu"}]}
'@
    $r = Invoke-ApplyAssert $wslOmitted
    if ($r.Code -eq 0) { throw 'wsl jobs with empty requiredWslPackageIds must fail' }
    if ($r.Err -notmatch 'requiredWslPackageIds missing or empty') { throw "wsl omitted evidence message: $($r.Err)" }

    $dmaIncomplete = Join-Path $root 'dma-incomplete'
    Copy-Tree $fixture $dmaIncomplete
    $ev = Get-Content -LiteralPath (Join-Path $dmaIncomplete 'evidence.json') -Raw | ConvertFrom-Json
    $ev.lane = 'Release'
    $ev | Add-Member -NotePropertyName packageStrict -NotePropertyValue $true -Force
    ($ev | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $dmaIncomplete 'evidence.json') -Encoding utf8
    $payload = Join-Path $dmaIncomplete 'payload'
    New-Item -ItemType Directory -Force -Path $payload | Out-Null
    Set-Content -LiteralPath (Join-Path $payload 'bundle.json') -Encoding utf8 -Value @'
{"schemaVersion":"winmint.provisioning.bundle/v1","supervisorPath":"C:\\Windows\\WinMint\\Supervisor.exe","username":"winmint","password":"","dmaEnabled":true,"settle":null,"packageStrict":true}
'@
    $r = Invoke-ApplyAssert $dmaIncomplete -RequireLane Release
    if ($r.Code -eq 0) { throw 'Gate B with dmaEnabled and incomplete settle must fail' }
    if ($r.Err -notmatch 'dma\.settle requires locale, geoId, timeZoneId, and locationServicesEnabled') {
        throw "dma settle message: $($r.Err)"
    }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Test-ApplyEvidence ok'
exit 0
