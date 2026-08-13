#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'servicing\Build-Iso.ps1') -OutputIso 'x' -MediaDir 'y'

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('winmint-oscdimg-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'boot'), (Join-Path $tmp 'efi\microsoft\boot') | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $tmp 'efi\microsoft\boot\efisys_noprompt.bin') -Value 'efi' -Encoding utf8
    $uefiOnly = Get-WinMintOscdimgBootData -MediaDir $tmp
    if ($uefiOnly -notmatch '^1#pEF,e,b') { throw "UEFI-only bootdata: $uefiOnly" }

    Set-Content -LiteralPath (Join-Path $tmp 'boot\etfsboot.com') -Value 'bios' -Encoding utf8
    $both = Get-WinMintOscdimgBootData -MediaDir $tmp
    if ($both -notmatch '^2#p0,e,b') { throw "BIOS+UEFI bootdata: $both" }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Test-BuildIso ok'
exit 0
