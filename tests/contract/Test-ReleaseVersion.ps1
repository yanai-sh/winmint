#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools/release/Get-WinMintReleaseVersion.ps1')

$commit = '0123456789abcdef0123456789abcdef01234567'
$v = Convert-WinMintReleaseTag -Tag 'v1.2.3' -Commit $commit
if ($v.Version -cne '1.2.3') { throw "Version $($v.Version)" }
if ($v.FileVersion -cne '1.2.3.0') { throw "FileVersion $($v.FileVersion)" }
if ($v.AssemblyVersion -cne '1.2.0.0') { throw "AssemblyVersion $($v.AssemblyVersion)" }
if ($v.InformationalVersion -cne "1.2.3+$commit") { throw "InformationalVersion $($v.InformationalVersion)" }

foreach ($bad in @('v1.2', '1.2.3', 'v1.2.3-local', 'v0.0.0-local', 'v1.2.3.4')) {
    $threw = $false
    try { Convert-WinMintReleaseTag -Tag $bad -Commit $commit | Out-Null }
    catch { $threw = $true }
    if (-not $threw) { throw "accepted illegal tag $bad" }
}

$props = Get-Content -LiteralPath (Join-Path $repo 'Directory.Build.props') -Raw
foreach ($needle in @('<Product>WinMint</Product>', '<Company>WinMint contributors</Company>', '<RepositoryUrl>https://github.com/yanai-sh/winmint</RepositoryUrl>', '<PublishRepositoryUrl>true</PublishRepositoryUrl>')) {
    if ($props.IndexOf($needle, [StringComparison]::Ordinal) -lt 0) { throw "Directory.Build.props missing $needle" }
}

$out = Join-Path ([IO.Path]::GetTempPath()) ('winmint-vermeta-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $out | Out-Null
try {
    $publishProps = Get-WinMintDotnetPublishProperties -Version $v
    dotnet publish (Join-Path $repo 'src\WinMint.Contracts\WinMint.Contracts.csproj') `
        -c Release `
        @publishProps `
        -o $out
    if ($LASTEXITCODE -ne 0) { throw "Contracts publish failed: $LASTEXITCODE" }
    $dll = Join-Path $out 'WinMint.Contracts.dll'
    if (-not (Test-Path -LiteralPath $dll)) { throw 'Contracts dll missing' }
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($dll)
    if ($info.ProductName -cne 'WinMint') { throw "ProductName $($info.ProductName)" }
    if ($info.CompanyName -cne 'WinMint contributors') { throw "CompanyName $($info.CompanyName)" }
}
finally {
    Remove-Item -LiteralPath $out -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Test-ReleaseVersion ok'
