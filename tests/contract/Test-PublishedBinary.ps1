#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools\host\Resolve-WinMintPublishedBinary.ps1')

$root = Join-Path ([IO.Path]::GetTempPath()) ('winmint-cli-fresh-' + [guid]::NewGuid().ToString('N'))
try {
    $src = Join-Path $root 'src'
    $exe = Join-Path $root 'WinMint.Cli.exe'
    New-Item -ItemType Directory -Force -Path $src | Out-Null
    Set-Content -LiteralPath $exe -Value 'exe'
    Set-Content -LiteralPath (Join-Path $src 'Program.cs') -Value '// code'
    (Get-Item -LiteralPath $exe).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-2)
    (Get-Item -LiteralPath (Join-Path $src 'Program.cs')).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-1)
    if (Test-WinMintPublishedBinaryCurrent -PublishedExe $exe -SourceRoots @($src)) {
        throw 'Test-PublishedBinary: source newer than publish must be stale'
    }

    (Get-Item -LiteralPath $exe).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-1)
    (Get-Item -LiteralPath (Join-Path $src 'Program.cs')).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-2)
    if (-not (Test-WinMintPublishedBinaryCurrent -PublishedExe $exe -SourceRoots @($src))) {
        throw 'Test-PublishedBinary: publish newer than source must be current'
    }

    New-Item -ItemType Directory -Force -Path (Join-Path $src 'obj') | Out-Null
    Set-Content -LiteralPath (Join-Path $src 'obj\Generated.cs') -Value '// generated'
    (Get-Item -LiteralPath (Join-Path $src 'obj\Generated.cs')).LastWriteTimeUtc = [datetime]::UtcNow
    (Get-Item -LiteralPath $exe).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-1)
    (Get-Item -LiteralPath (Join-Path $src 'Program.cs')).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-2)
    if (-not (Test-WinMintPublishedBinaryCurrent -PublishedExe $exe -SourceRoots @($src))) {
        throw 'Test-PublishedBinary: obj/ must not count as source'
    }

    if (-not (Test-WinMintPublishedBinaryCurrent -PublishedExe $exe -SourceRoots @(Join-Path $root 'missing'))) {
        throw 'Test-PublishedBinary: absent source must not block (packaged toolkit)'
    }

    (Get-Item -LiteralPath (Join-Path $src 'Program.cs')).LastWriteTimeUtc = [datetime]::UtcNow.AddHours(2)
    (Get-Item -LiteralPath $exe).LastWriteTimeUtc = [datetime]::UtcNow.AddMinutes(-5)
    if (-not (Test-WinMintPublishedBinaryCurrent -PublishedExe $exe -SourceRoots @($src))) {
        throw 'Test-PublishedBinary: future source mtime is clock skew, not stale'
    }

    $cli = Get-Content -LiteralPath (Join-Path $repo 'tools\host\Invoke-WinMintCli.ps1') -Raw -Encoding utf8
    if ($cli -notmatch 'Test-WinMintPublishedBinaryCurrent') {
        throw 'Test-PublishedBinary: Invoke-WinMintCli must skip a stale bin\cli'
    }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Test-PublishedBinary ok'
exit 0
