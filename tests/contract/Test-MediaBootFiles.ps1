#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'servicing\Patch-BootWimApply.ps1') -MediaDir 'x' -MountDir 'y' -WorkDirectory 'z' -QualityPackageDir 'q'

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('winmint-bootfiles-' + [guid]::NewGuid().ToString('N'))
$media = Join-Path $tmp 'media'
$stage = Join-Path $tmp 'stage'
New-Item -ItemType Directory -Force -Path @(
    (Join-Path $media 'efi\boot'),
    (Join-Path $media 'efi\microsoft\boot'),
    (Join-Path $media 'sources'),
    $stage
) | Out-Null
try {
    $old = 'old-boot'
    $bin = 'efisys-bytes'
    Set-Content -LiteralPath (Join-Path $media 'efi\boot\bootaa64.efi') -Value $old -Encoding utf8 -NoNewline
    Set-Content -LiteralPath (Join-Path $media 'efi\microsoft\boot\bootmgfw.efi') -Value $old -Encoding utf8 -NoNewline
    Set-Content -LiteralPath (Join-Path $media 'efi\microsoft\boot\bootmgr.efi') -Value $old -Encoding utf8 -NoNewline
    Set-Content -LiteralPath (Join-Path $media 'efi\microsoft\boot\efisys_noprompt.bin') -Value $bin -Encoding utf8 -NoNewline
    (Get-Item -LiteralPath (Join-Path $media 'efi\boot\bootaa64.efi')).IsReadOnly = $true

    $mgfw = Join-Path $stage 'bootmgfw.efi'
    $mgr = Join-Path $stage 'bootmgr.efi'
    $stl = Join-Path $stage 'boot.stl'
    Set-Content -LiteralPath $mgfw -Value 'new-mgfw' -Encoding utf8 -NoNewline
    Set-Content -LiteralPath $mgr -Value 'new-mgr' -Encoding utf8 -NoNewline
    Set-Content -LiteralPath $stl -Value 'new-stl' -Encoding utf8 -NoNewline

    Publish-WinMintMediaBootFile -MediaDir $media -BootMgfw $mgfw -BootMgr $mgr -BootStl $stl

    $aa64 = Get-Content -LiteralPath (Join-Path $media 'efi\boot\bootaa64.efi') -Raw -Encoding utf8
    $fw = Get-Content -LiteralPath (Join-Path $media 'efi\microsoft\boot\bootmgfw.efi') -Raw -Encoding utf8
    $mgrOut = Get-Content -LiteralPath (Join-Path $media 'efi\microsoft\boot\bootmgr.efi') -Raw -Encoding utf8
    $stlOut = Get-Content -LiteralPath (Join-Path $media 'efi\microsoft\boot\boot.stl') -Raw -Encoding utf8
    $efisys = Get-Content -LiteralPath (Join-Path $media 'efi\microsoft\boot\efisys_noprompt.bin') -Raw -Encoding utf8
    if ($aa64 -ne 'new-mgfw') { throw "bootaa64.efi must be the serviced bootmgfw (got $aa64)" }
    if ($fw -ne 'new-mgfw') { throw "bootmgfw.efi must be replaced (got $fw)" }
    if ($mgrOut -ne 'new-mgr') { throw "bootmgr.efi must be replaced (got $mgrOut)" }
    if ($stlOut -ne 'new-stl') { throw "boot.stl must land in efi\microsoft\boot (got $stlOut)" }
    if ($efisys -ne $bin) { throw 'efisys_noprompt.bin must stay the El Torito image' }
    if (Test-Path -LiteralPath (Join-Path $media 'sources\boot.stl')) { throw 'boot.stl must not be copied to sources\' }
}
finally {
    Get-ChildItem -LiteralPath $tmp -Recurse -Force -File -ErrorAction SilentlyContinue |
        ForEach-Object { $_.IsReadOnly = $false }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Test-MediaBootFiles ok'
exit 0
