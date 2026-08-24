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
    if ($both -notmatch 'efisys_noprompt\.bin') { throw "must prefer noprompt: $both" }

    Remove-Item -LiteralPath (Join-Path $tmp 'efi\microsoft\boot\efisys_noprompt.bin') -Force
    Set-Content -LiteralPath (Join-Path $tmp 'efi\microsoft\boot\efisys.bin') -Value 'efi' -Encoding utf8
    $prompt = Get-WinMintOscdimgBootData -MediaDir $tmp
    if ($prompt -notmatch 'efisys\.bin') { throw "prompt fallback: $prompt" }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$isoSrc = Get-Content -LiteralPath (Join-Path $repo 'servicing\Build-Iso.ps1') -Raw -Encoding utf8
if ($isoSrc -notmatch 'oscdimg efisys=') { throw 'Build-Iso must print which efisys*.bin was selected' }

Write-Output 'Test-BuildIso ok'
exit 0
