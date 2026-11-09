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

    $absent = Join-Path $tmp 'absent-mgfw'
    New-Item -ItemType Directory -Force -Path @(
        (Join-Path $absent 'efi\boot'),
        (Join-Path $absent 'efi\microsoft\boot')
    ) | Out-Null
    Set-Content -LiteralPath (Join-Path $absent 'efi\boot\bootaa64.efi') -Value $old -Encoding utf8 -NoNewline
    Set-Content -LiteralPath (Join-Path $absent 'efi\microsoft\boot\efisys_noprompt.bin') -Value $bin -Encoding utf8 -NoNewline
    Publish-WinMintMediaBootFile -MediaDir $absent -BootMgfw $mgfw -BootStl $stl
    $createdFw = Get-Content -LiteralPath (Join-Path $absent 'efi\microsoft\boot\bootmgfw.efi') -Raw -Encoding utf8
    $createdAa64 = Get-Content -LiteralPath (Join-Path $absent 'efi\boot\bootaa64.efi') -Raw -Encoding utf8
    $absentEfisys = Get-Content -LiteralPath (Join-Path $absent 'efi\microsoft\boot\efisys_noprompt.bin') -Raw -Encoding utf8
    if ($createdFw -ne 'new-mgfw') { throw "absent media must gain bootmgfw.efi (got $createdFw)" }
    if ($createdAa64 -ne 'new-mgfw') { throw "absent media must replace bootaa64.efi (got $createdAa64)" }
    if ($absentEfisys -ne $bin) { throw 'efisys_noprompt.bin must stay unchanged when bootmgfw.efi is created' }

    Assert-WinMintBootManagerCa2023 -Path $mgfw

    $unsigned = Join-Path $stage 'unsigned.efi'
    [IO.File]::WriteAllBytes($unsigned, [byte[]](0x4D, 0x5A, 0, 0))
    $rejected = $false
    try {
        Assert-WinMintBootManagerCa2023 -Path $unsigned
    }
    catch {
        $rejected = $_.Exception.Message -match 'Windows UEFI CA 2023'
    }
    if (-not $rejected) { throw 'A PE boot manager without the Windows UEFI CA 2023 signature must fail' }

    $emptyStage = Join-Path $tmp 'empty-stage'
    New-Item -ItemType Directory -Force -Path $emptyStage | Out-Null
    $missingStl = $false
    try {
        Publish-WinMintStagedBootSet -MediaDir $media -StageDir $emptyStage
    }
    catch {
        $missingStl = $_.Exception.Message -match 'boot\.stl'
    }
    if (-not $missingStl) { throw 'Publish must fail when Windows\Boot\EFI\boot.stl is missing' }

    $mgfwOnly = Join-Path $tmp 'mgfw-only'
    New-Item -ItemType Directory -Force -Path $mgfwOnly | Out-Null
    Copy-Item -LiteralPath $mgfw -Destination (Join-Path $mgfwOnly 'bootmgfw.efi')
    $missingMgfw = $false
    try {
        Publish-WinMintStagedBootSet -MediaDir $media -StageDir $mgfwOnly
    }
    catch {
        $missingMgfw = $_.Exception.Message -match 'boot\.stl'
    }
    if (-not $missingMgfw) { throw 'Publish must fail when boot.stl is absent even if bootmgfw.efi is staged' }

    $noMgfw = Join-Path $tmp 'no-mgfw'
    New-Item -ItemType Directory -Force -Path $noMgfw | Out-Null
    Copy-Item -LiteralPath $stl -Destination (Join-Path $noMgfw 'boot.stl')
    $missingBootMgfw = $false
    try {
        Publish-WinMintStagedBootSet -MediaDir $media -StageDir $noMgfw
    }
    catch {
        $missingBootMgfw = $_.Exception.Message -match 'bootmgfw\.efi'
    }
    if (-not $missingBootMgfw) { throw 'Publish must fail when Windows\Boot\EFI\bootmgfw.efi is missing' }
}
finally {
    Get-ChildItem -LiteralPath $tmp -Recurse -Force -File -ErrorAction SilentlyContinue |
        ForEach-Object { $_.IsReadOnly = $false }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$patcher = Get-Content -LiteralPath (Join-Path $repo 'servicing\Patch-BootWimApply.ps1') -Raw -Encoding utf8
$skipAt = $patcher.IndexOf('already patched; LaunchApply verified', [StringComparison]::Ordinal)
if ($skipAt -lt 0) { throw 'Patch-BootWimApply is missing the already-patched skip' }
$skipBefore = $patcher.Substring([Math]::Max(0, $skipAt - 700), [Math]::Min(700, $skipAt))
if ($skipBefore -notmatch 'Copy-WinMintBootWimEfiStage') {
    throw 'The already-patched skip must stage Windows\Boot\EFI before it returns'
}
if ($skipBefore -notmatch 'Publish-WinMintStagedBootSet') {
    throw 'The already-patched skip must publish bootmgfw.efi, bootaa64.efi, and boot.stl'
}
$qualityGate = 'if ($applyQuality) {'
$publishAt = $patcher.LastIndexOf('Publish-WinMintStagedBootSet -MediaDir $mediaDir -StageDir $bootEfiStage', [StringComparison]::Ordinal)
if ($publishAt -lt 0) { throw 'Patch-BootWimApply must publish the staged boot set after the launcher patch' }
$between = $patcher.Substring($publishAt - 120, 120)
if ($between.Contains($qualityGate)) {
    throw 'Boot-file publish must run when no quality packages were applied'
}

Write-Output 'Test-MediaBootFiles ok'
exit 0
