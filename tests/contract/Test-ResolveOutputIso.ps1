#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools\Resolve-OutputIso.ps1')

$work = Join-Path ([IO.Path]::GetTempPath()) ('winmint-outiso-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $a = Join-Path $work 'winmint_a_Test_20260101-000000.iso'
    $b = Join-Path $work 'winmint_b_Test_20260102-000000.iso'
    Set-Content -LiteralPath $a -Value 'a'
    Set-Content -LiteralPath $b -Value 'b'
    (Get-Item -LiteralPath $a).LastWriteTimeUtc = [datetime]::UtcNow
    (Get-Item -LiteralPath $b).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-1)

    $threw = $false
    try { Resolve-WinMintOutputIso -WorkDirectory $work | Out-Null } catch { $threw = $true }
    if (-not $threw) { throw 'Test-ResolveOutputIso: two unnamed ISOs must not pick by LastWriteTime' }

    @{ outputIsoPath = $b } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $work 'evidence.json') -Encoding utf8
    $hit = Resolve-WinMintOutputIso -WorkDirectory $work
    if ($hit -ne (Resolve-Path -LiteralPath $b).Path) {
        throw "Test-ResolveOutputIso: evidence path must win, got $hit"
    }

    Remove-Item -LiteralPath (Join-Path $work 'evidence.json') -Force
    Remove-Item -LiteralPath $b -Force
    $one = Resolve-WinMintOutputIso -WorkDirectory $work
    if ($one -ne (Resolve-Path -LiteralPath $a).Path) {
        throw "Test-ResolveOutputIso: single named ISO must resolve, got $one"
    }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Test-ResolveOutputIso ok'
exit 0
