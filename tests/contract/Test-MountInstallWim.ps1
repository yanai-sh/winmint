#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$kernel = Join-Path $repo 'servicing\Mount-InstallWim.ps1'
$cmd = Get-Command $kernel
foreach ($need in @(
        'SourceIso', 'MountDir', 'MediaDir', 'WimIndex', 'WorkDirectory',
        'SourceIsoSha256', 'SourceIsoLength', 'CacheSchema', 'CacheRoot')) {
    if (-not $cmd.Parameters.ContainsKey($need)) {
        throw "Mount-InstallWim missing -$need"
    }
}
if ($cmd.Parameters.ContainsKey('ReuseMedia') -or $cmd.Parameters.ContainsKey('Parameters')) {
    throw 'Mount-InstallWim must take named params, not -ReuseMedia or -Parameters'
}

. (Join-Path $repo 'servicing\Initialize-SourceMediaCache.ps1')
$cache = Join-Path $env:ProgramData 'WinMint\Servicing\media-cache'
$threw = $false
try {
    Assert-WinMintMountImagePath -ImageFile (Join-Path $cache 'v1\abc\index-3\media\sources\install.wim') -CacheRoot $cache
}
catch { $threw = $true }
if (-not $threw) { throw 'must refuse mounting a Prepared-media WIM' }

Write-Output 'Test-MountInstallWim ok'
exit 0
