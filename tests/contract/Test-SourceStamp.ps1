#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Same vector as SupervisorFreshnessTests.One_file_digest_matches_the_pinned_vector.
$expected = 'a628d45f7c32f7f21b081290b3f441b85512d970b677614c6039933f56b0dd21'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools\host\Write-WinMintSourceStamp.ps1')

$root = Join-Path ([IO.Path]::GetTempPath()) ('winmint-stamp-' + [guid]::NewGuid().ToString('N'))
try {
    $proj = Join-Path $root 'WinMint.Provisioning'
    New-Item -ItemType Directory -Force -Path $proj | Out-Null
    [IO.File]::WriteAllText((Join-Path $proj 'Program.cs'), 'stamp')
    $digest = Get-WinMintSourceTreeDigest -Roots @($proj)
    if ($digest -ne $expected) {
        throw "Test-SourceStamp: digest $digest"
    }

    New-Item -ItemType Directory -Force -Path (Join-Path $proj 'obj') | Out-Null
    [IO.File]::WriteAllText((Join-Path $proj 'obj\Generated.cs'), 'generated')
    $digest = Get-WinMintSourceTreeDigest -Roots @($proj)
    if ($digest -ne $expected) {
        throw "Test-SourceStamp: obj/ changed the digest to $digest"
    }

    $exe = Join-Path $root 'WinMint.Provisioning.exe'
    [IO.File]::WriteAllText($exe, 'binary')
    if (Test-WinMintPublishedStampCurrent -Exe $exe -SourceRoots @($proj)) {
        throw 'Test-SourceStamp: missing stamp must not count as current'
    }
    [IO.File]::WriteAllText("$exe.sha256", $expected)
    if (-not (Test-WinMintPublishedStampCurrent -Exe $exe -SourceRoots @($proj))) {
        throw 'Test-SourceStamp: matching stamp must count as current'
    }
    [IO.File]::WriteAllText((Join-Path $proj 'Program.cs'), 'edited')
    if (Test-WinMintPublishedStampCurrent -Exe $exe -SourceRoots @($proj)) {
        throw 'Test-SourceStamp: mismatched stamp must not count as current'
    }
    if (Test-WinMintPublishedStampCurrent -Exe (Join-Path $root 'missing.exe') -SourceRoots @($proj)) {
        throw 'Test-SourceStamp: missing exe must not count as current'
    }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

$apply = Get-Content -LiteralPath (Join-Path $repo 'tools\apply\Invoke-HostApply.ps1') -Raw -Encoding utf8
if ($apply -notmatch 'Test-WinMintPublishedStampCurrent -Exe \$supervisor') {
    throw 'Invoke-HostApply must check the Supervisor source stamp before reusing it'
}
if ($apply -notmatch 'Test-WinMintPublishedStampCurrent -Exe \$winPeApply') {
    throw 'Invoke-HostApply must check the WinPE apply source stamp before reusing it'
}

Write-Output 'Test-SourceStamp ok'
