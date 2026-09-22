#requires -Version 7.6
# S4 bar through Assert-SmokeEvidence on the fixture adapter. No Hyper-V.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$assert = Join-Path $repo 'tools\vm\Assert-SmokeEvidence.ps1'
$fixture = Join-Path $repo 'tests\fixtures\smoke-evidence'

function Copy-Tree([string] $Source, [string] $Dest) {
    foreach ($file in [IO.Directory]::GetFiles($Source, '*', [IO.SearchOption]::AllDirectories)) {
        $rel = [IO.Path]::GetRelativePath($Source, $file)
        $target = Join-Path $Dest $rel
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
        [IO.File]::Copy($file, $target, $true)
    }
}

function Guest-EvidencePath([string] $Work) {
    @([IO.Directory]::GetFiles((Join-Path $Work 'guest'), 'evidence-*.json'))[0]
}

function Invoke-StaticAssert {
    param(
        [string] $Work,
        [string[]] $PinnedRemoveAppx = @()
    )
    try {
        $splat = @{ EvidenceDir = $Work; StaticEvidenceOnly = $true }
        if ($PinnedRemoveAppx.Count -gt 0) { $splat.PinnedRemoveAppx = $PinnedRemoveAppx }
        $null = & $assert @splat
        return [pscustomobject]@{ Code = 0; Err = '' }
    }
    catch {
        return [pscustomobject]@{ Code = 1; Err = [string]$_.Exception.Message }
    }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('winmint-s4-' + [guid]::NewGuid().ToString('N'))
try {
    $ok = Join-Path $root 'ok'
    Copy-Tree $fixture $ok
    $r = Invoke-StaticAssert $ok
    if ($r.Code -ne 0) { throw "fixture must pass: $($r.Err)" }
    $json = Get-Content -LiteralPath (Join-Path $ok 'acceptance.json') -Raw
    if ($json -notmatch 'winmint.smoke.acceptance/v1') { throw 'acceptance schema' }
    if ($json -notmatch '"splashBeforeExplorer": true') { throw 'splash-before-Explorer' }
    if ($json -notmatch '"lane": "Test"') { throw 'lane Test' }
    if ($json -notmatch '"outcome": "Complete"') { throw 'outcome Complete' }

    $nokeep = Join-Path $root 'nokeep'
    Copy-Tree $fixture $nokeep
    Remove-Item -LiteralPath (Join-Path $nokeep 'acceptance.json') -ErrorAction SilentlyContinue
    Set-Content -LiteralPath (Join-Path $nokeep 'apply\evidence.json') `
        -Value '{"schemaVersion":"winmint.image.evidence/v1","lane":"Test","digests":{}}' -Encoding utf8
    $r = Invoke-StaticAssert $nokeep -PinnedRemoveAppx @('Microsoft.BingNews')
    if ($r.Code -eq 0) { throw 'empty keep-flag digests must fail' }
    if ($r.Err -notmatch 'keep-flag digest missing') { throw "keep-flag message: $($r.Err)" }
    if (Test-Path -LiteralPath (Join-Path $nokeep 'acceptance.json')) { throw 'no acceptance on keep-flag fail' }

    $nopaint = Join-Path $root 'nopaint'
    Copy-Tree $fixture $nopaint
    Remove-Item -LiteralPath (Join-Path $nopaint 'acceptance.json') -ErrorAction SilentlyContinue
    $guest = Get-Content -LiteralPath (Guest-EvidencePath $nopaint) -Raw | ConvertFrom-Json
    $guest.phases = @('settle.begin', 'settle.ok', 'jobs.ok')
    ($guest | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Guest-EvidencePath $nopaint) -Encoding utf8
    $r = Invoke-StaticAssert $nopaint
    if ($r.Code -eq 0) { throw 'missing firstPaint must fail' }

    $nooobe = Join-Path $root 'nooobe'
    Copy-Tree $fixture $nooobe
    Remove-Item -LiteralPath (Join-Path $nooobe 'acceptance.json') -ErrorAction SilentlyContinue
    $guest = Get-Content -LiteralPath (Guest-EvidencePath $nooobe) -Raw | ConvertFrom-Json
    $guest.phases = @(
        'shell.firstPaint', 'settle.begin', 'settle.deviceRegionOk', 'settle.ok', 'jobs.begin',
        'jobs.workstation.quiet', 'jobs.wsl.platform.mocked', 'shell.chrome', 'jobs.ok')
    ($guest | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Guest-EvidencePath $nooobe) -Encoding utf8
    $r = Invoke-StaticAssert $nooobe
    if ($r.Code -eq 0) { throw 'missing oobe.dismiss must fail' }
    if ($r.Err -notmatch 'oobe.dismiss') { throw "oobe.dismiss message: $($r.Err)" }

    $pins = Join-Path $root 'pins'
    Copy-Tree $fixture $pins
    Remove-Item -LiteralPath (Join-Path $pins 'acceptance.json') -ErrorAction SilentlyContinue
    $chrome = Get-Content -LiteralPath (Join-Path $pins 'guest\shell-chrome.json') -Raw | ConvertFrom-Json
    $chrome.startPinIds = @('explorer', 'terminal')
    ($chrome | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $pins 'guest\shell-chrome.json') -Encoding utf8
    $r = Invoke-StaticAssert $pins
    if ($r.Code -eq 0) { throw 'missing start pins must fail' }
    if ($r.Err -notmatch 'startPinIds') { throw "startPinIds message: $($r.Err)" }

    $baseline = Join-Path $root 'baseline'
    Copy-Tree $fixture $baseline
    Remove-Item -LiteralPath (Join-Path $baseline 'acceptance.json') -ErrorAction SilentlyContinue
    $chrome = Get-Content -LiteralPath (Join-Path $baseline 'guest\shell-chrome.json') -Raw | ConvertFrom-Json
    $chrome.startPinIds = @('explorer', 'settings', 'terminal')
    $chrome.taskbarPinIds = @('explorer', 'terminal')
    ($chrome | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $baseline 'guest\shell-chrome.json') -Encoding utf8
    $r = Invoke-StaticAssert $baseline
    if ($r.Code -ne 0) { throw "Test-lane baseline pins must pass: $($r.Err)" }

    $strict = Join-Path $root 'strict'
    Copy-Tree $baseline $strict
    $apply = Get-Content -LiteralPath (Join-Path $strict 'apply\evidence.json') -Raw | ConvertFrom-Json
    $apply.packageStrict = $true
    ($apply | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $strict 'apply\evidence.json') -Encoding utf8
    $r = Invoke-StaticAssert $strict
    if ($r.Code -eq 0) { throw 'package-strict missing extra pins must fail' }
    if ($r.Err -notmatch 'package-strict') { throw "package-strict extra pin message: $($r.Err)" }

    $nativeMiss = Join-Path $root 'nativeMiss'
    Copy-Tree $baseline $nativeMiss
    Set-Content -LiteralPath (Join-Path $nativeMiss 'guest\native-packages.json') -Encoding utf8 -Value @'
{"schemaVersion":"winmint.native-packages/v1","packages":[{"wingetId":"Anysphere.Cursor","binaryPath":null,"isArm64Native":null}]}
'@
    $r = Invoke-StaticAssert $nativeMiss
    if ($r.Code -ne 0) { throw "absent native extra pin must not require chrome pin: $($r.Err)" }

    $nativeHit = Join-Path $root 'nativeHit'
    Copy-Tree $baseline $nativeHit
    Set-Content -LiteralPath (Join-Path $nativeHit 'guest\native-packages.json') -Encoding utf8 -Value @'
{"schemaVersion":"winmint.native-packages/v1","packages":[{"wingetId":"Anysphere.Cursor","binaryPath":"C:\\Users\\winmint\\AppData\\Local\\Programs\\cursor\\Cursor.exe","isArm64Native":true}]}
'@
    $r = Invoke-StaticAssert $nativeHit
    if ($r.Code -eq 0) { throw 'installed Cursor without chrome pin must fail' }
    if ($r.Err -notmatch 'cursor') { throw "native extra pin message: $($r.Err)" }

    $nochrome = Join-Path $root 'nochrome'
    Copy-Tree $fixture $nochrome
    Remove-Item -LiteralPath (Join-Path $nochrome 'acceptance.json') -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $nochrome 'guest\shell-chrome.json')
    $r = Invoke-StaticAssert $nochrome
    if ($r.Code -eq 0) { throw 'missing shell-chrome.json must fail' }
    if ($r.Err -notmatch 'shell-chrome.json') { throw "shell-chrome message: $($r.Err)" }

    $nodeprov = Join-Path $root 'nodeprov'
    Copy-Tree $fixture $nodeprov
    Remove-Item -LiteralPath (Join-Path $nodeprov 'acceptance.json') -ErrorAction SilentlyContinue
    $guest = Get-Content -LiteralPath (Guest-EvidencePath $nodeprov) -Raw | ConvertFrom-Json
    $guest.phases = @(
        'shell.firstPaint', 'settle.begin', 'settle.deviceRegionOk', 'settle.ok', 'jobs.begin',
        'jobs.workstation.quiet', 'jobs.wsl.platform.mocked', 'removed.appx.online.Microsoft.BingNews',
        'shell.chrome', 'jobs.ok', 'oobe.dismiss')
    ($guest | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Guest-EvidencePath $nodeprov) -Encoding utf8
    $r = Invoke-StaticAssert $nodeprov
    if ($r.Code -eq 0) { throw 'online remove without deprovision mark must fail' }
    if ($r.Err -notmatch 'deprovisioned.appx') { throw "deprovision message: $($r.Err)" }

    $live = Join-Path $root 'live'
    Copy-Tree $fixture $live
    Remove-Item -LiteralPath (Join-Path $live 'acceptance.json') -ErrorAction SilentlyContinue
    try {
        & $assert -EvidenceDir $live -LiveShell 'C:\Windows\WinMint\Supervisor.exe' -SupervisorRunning:$false
        throw 'live non-explorer shell must fail'
    }
    catch {
        if ($_.Exception.Message -eq 'live non-explorer shell must fail') { throw }
        if ($_.Exception.Message -notmatch 'handoff') { throw "handoff message: $($_.Exception.Message)" }
    }
    if (Test-Path -LiteralPath (Join-Path $live 'acceptance.json')) { throw 'no acceptance on live handoff fail' }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Test-SmokeEvidence ok'
exit 0
