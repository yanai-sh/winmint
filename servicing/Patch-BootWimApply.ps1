#requires -Version 7.6
param(
    [Parameter(Mandatory)] [string] $MediaDir,
    [Parameter(Mandatory)] [string] $MountDir,
    [Parameter(Mandatory)] [string] $WorkDirectory,
    [Parameter(Mandatory)] [string] $QualityPackageDir
)
# Source-ISO edition index is unrelated: after single-image export, apply target is always index 1.

function Copy-WinMintMediaBootFile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Destination
    )
    if (-not $PSCmdlet.ShouldProcess($Destination, 'Replace media boot file')) { return }
    $destItem = Get-Item -LiteralPath $Destination -ErrorAction SilentlyContinue
    if ($null -ne $destItem -and $destItem.IsReadOnly) { $destItem.IsReadOnly = $false }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Copy-WinMintWinPeDesktop {
    param(
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Destination
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "winpe.jpg missing: $Source" }

    # boot.wim index 2 keeps the inbox wallpaper after the LCU. Owner is TrustedInstaller
    # and the DACL grants Administrators read/execute only (not read-only, not a share lock).
    # Clearing IsReadOnly cannot overwrite it. Grant Administrators on this file only.
    try {
        $existing = Get-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        if ($null -ne $existing -and $existing.IsReadOnly) { $existing.IsReadOnly = $false }
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        return
    }
    catch {
        $ex = $_.Exception
        $denied = $false
        while ($null -ne $ex) {
            if ($ex -is [UnauthorizedAccessException] -or $ex.Message -match 'Access to the path') {
                $denied = $true
                break
            }
            $ex = $ex.InnerException
        }
        if (-not $denied -or -not (Test-Path -LiteralPath $Destination -PathType Leaf)) { throw }
    }

    & takeown.exe /F $Destination /A | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "takeown failed: $Destination exit $LASTEXITCODE" }
    # Administrators (BA) — S-1-5-32-544
    & icacls.exe $Destination /grant '*S-1-5-32-544:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls grant failed: $Destination exit $LASTEXITCODE" }
    $existing = Get-Item -LiteralPath $Destination -Force
    if ($existing.IsReadOnly) { $existing.IsReadOnly = $false }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Publish-WinMintMediaBootFile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $MediaDir,
        [string] $BootMgfw = '',
        [string] $BootMgr = '',
        [string] $BootStl = ''
    )
    # Learn "Update Windows installation media": after the LCU is on boot.wim, copy
    # Windows\Boot\EFI\boot.stl to efi\microsoft\boot\boot.stl and replace the media
    # bootmgfw/bootaa64/bootmgr copies with that same serviced WinPE. KB5127648:
    # a missing or mismatched boot.stl fails Secure Boot media start (0xc0430001).
    if (-not $PSCmdlet.ShouldProcess($MediaDir, 'Publish serviced boot file')) { return }
    $haveMgfw = -not [string]::IsNullOrWhiteSpace($BootMgfw)
    $haveMgr = -not [string]::IsNullOrWhiteSpace($BootMgr)
    if (-not [string]::IsNullOrWhiteSpace($BootStl)) {
        $stlDir = Join-Path $MediaDir 'efi\microsoft\boot'
        New-Item -ItemType Directory -Force -Path $stlDir | Out-Null
        Copy-WinMintMediaBootFile -Source $BootStl -Destination (Join-Path $stlDir 'boot.stl')
    }
    # ARM64 Source ISO has efi\boot\bootaa64.efi and no efi\microsoft\boot\bootmgfw.efi.
    # Replacing only names already on disk never creates the path USB publish requires.
    if ($haveMgfw) {
        $mgfwDir = Join-Path $MediaDir 'efi\microsoft\boot'
        $aa64Dir = Join-Path $MediaDir 'efi\boot'
        New-Item -ItemType Directory -Force -Path @($mgfwDir, $aa64Dir) | Out-Null
        Copy-WinMintMediaBootFile -Source $BootMgfw -Destination (Join-Path $mgfwDir 'bootmgfw.efi')
        Copy-WinMintMediaBootFile -Source $BootMgfw -Destination (Join-Path $aa64Dir 'bootaa64.efi')
    }
    if (-not $haveMgfw -and -not $haveMgr) { return }
    $efiFiles = @(Get-ChildItem -LiteralPath $MediaDir -Force -Recurse -File -Filter 'b*.efi' -ErrorAction SilentlyContinue)
    foreach ($file in $efiFiles) {
        if ($haveMgfw -and $file.Name -match '^(?i)(bootmgfw|bootx64|bootia32|bootaa64)\.efi$') {
            Copy-WinMintMediaBootFile -Source $BootMgfw -Destination $file.FullName
        }
        elseif ($haveMgr -and $file.Name -match '^(?i)bootmgr\.efi$') {
            Copy-WinMintMediaBootFile -Source $BootMgr -Destination $file.FullName
        }
    }
}

function Test-WinMintPeImage {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $buf = [byte[]]::new(2)
        $read = $stream.Read($buf, 0, 2)
        return $read -eq 2 -and $buf[0] -eq 0x4D -and $buf[1] -eq 0x5A
    }
    finally {
        $stream.Dispose()
    }
}

function Test-WinMintBootManagerCa2023 {
    <#
    .SYNOPSIS
      A Valid Authenticode signer is current when it is Windows UEFI CA 2023 or a
      Windows Production PCA from 2023 on. Production PCA 2011 stays rejected.
      26H2 bootmgfw is issued by Microsoft Windows Production PCA 2026.
    #>
    param(
        [Parameter(Mandatory)]
        $Signature
    )
    if ($Signature.Status -ne [Management.Automation.SignatureStatus]::Valid) { return $false }
    $cert = $Signature.SignerCertificate
    $blob = if ($null -eq $cert) { '' } else { "$($cert.Subject)`n$($cert.Issuer)" }
    if ($blob -match 'PCA 2011') { return $false }
    return $blob -match 'Windows UEFI CA 2023' -or $blob -match 'Production PCA 20(2[3-9]|[3-9]\d)'
}

function Assert-WinMintBootManagerCa2023 {
    <#
    .SYNOPSIS
      A real PE boot manager must chain to Windows UEFI CA 2023 or a later Windows Production PCA.
      Non-PE fixtures (contract tests) are ignored so the copy function stays byte-oriented.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )
    if (-not (Test-WinMintPeImage -Path $Path)) { return }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if (-not (Test-WinMintBootManagerCa2023 -Signature $signature)) {
        throw "bootmgfw.efi is not signed through Windows UEFI CA 2023: $Path ($($signature.Status))"
    }
}

function Clear-WinMintBootEfiStage {
    param(
        [Parameter(Mandatory)]
        [string] $StageDir
    )
    foreach ($leaf in @('boot.stl', 'bootmgfw.efi', 'bootmgr.efi')) {
        $staged = Join-Path $StageDir $leaf
        if (Test-Path -LiteralPath $staged) {
            Remove-Item -LiteralPath $staged -Force
        }
    }
}

function Copy-WinMintBootEfiStage {
    param(
        [Parameter(Mandatory)]
        [string] $MountDir,
        [Parameter(Mandatory)]
        [string] $StageDir
    )
    $efiDir = Join-Path $MountDir 'Windows\Boot\EFI'
    foreach ($leaf in @('boot.stl', 'bootmgfw.efi', 'bootmgr.efi')) {
        $src = Join-Path $efiDir $leaf
        if (Test-Path -LiteralPath $src -PathType Leaf) {
            New-Item -ItemType Directory -Force -Path $StageDir | Out-Null
            Copy-Item -LiteralPath $src -Destination (Join-Path $StageDir $leaf) -Force
        }
    }
}

function Publish-WinMintStagedBootSet {
    param(
        [Parameter(Mandatory)]
        [string] $MediaDir,
        [Parameter(Mandatory)]
        [string] $StageDir
    )
    $stl = Join-Path $StageDir 'boot.stl'
    $mgfw = Join-Path $StageDir 'bootmgfw.efi'
    $mgr = Join-Path $StageDir 'bootmgr.efi'
    if (-not (Test-Path -LiteralPath $stl -PathType Leaf)) {
        throw 'Serviced boot.wim is missing Windows\Boot\EFI\boot.stl; Secure Boot media needs efi\microsoft\boot\boot.stl'
    }
    if (-not (Test-Path -LiteralPath $mgfw -PathType Leaf)) {
        throw 'Serviced boot.wim is missing Windows\Boot\EFI\bootmgfw.efi'
    }
    Assert-WinMintBootManagerCa2023 -Path $mgfw
    $mgrArg = ''
    if (Test-Path -LiteralPath $mgr -PathType Leaf) { $mgrArg = $mgr }
    Publish-WinMintMediaBootFile -MediaDir $MediaDir -BootStl $stl -BootMgfw $mgfw -BootMgr $mgrArg
}

if ($MyInvocation.InvocationName -ne '.') {
. (Join-Path $PSScriptRoot 'WinPeApplyContract.ps1')
. (Join-Path $PSScriptRoot 'Resolve-WinMintMount.ps1')
. (Join-Path $PSScriptRoot 'Resolve-WinMintQualityUpdate.ps1')
. (Join-Path $PSScriptRoot 'Invoke-WinMintDism.ps1')
$launchApplyPayload = Get-WinPeApplyPayloadPath
$expectedMarker = Get-WinPeApplyMarkerText
$bootLeafRaw = @(Get-WinMintQualityPackageLeaf -PackageDir $QualityPackageDir -Kind boot)
$bootPackages = @($bootLeafRaw | Where-Object { Test-WinMintBootWimQualityLeaf -Leaf $_ })
if ($bootLeafRaw.Count -gt 0 -and $bootPackages.Count -lt $bootLeafRaw.Count) {
    Write-WinMintQualityPackageLeaf -PackageDir $QualityPackageDir -Kind boot -Leaf $bootPackages
    Write-Output 'PatchBootWimApply trimmed install-only checkpoint leaves from boot.packages'
}
$applyQuality = $bootPackages.Count -gt 0

# Spike #70: 3-partition GPT (EFI 100 MB, MSR 16 MB, primary) — WinPE apply disk layout.
# LabConfig on applied-image SYSTEM hive (not boot.wim) — Hyper-V no-vTPM VMs read it at first boot.
$bootWim = Join-Path $mediaDir 'sources\boot.wim'
$bootMarker = Join-Path $mediaDir 'sources\.winmint-boot-apply'
$legacyMarker = Join-Path $mediaDir 'sources\.winmint-boot-legacy'
if (-not (Test-Path -LiteralPath $bootWim)) {
    throw "boot.wim missing under media (expected $bootWim)"
}

function Test-LaunchApplyPatched {
    param([string] $Wim, [string] $Mount, [int] $Index)
    Write-WinMintMountOwner -Kind boot -WorkDirectory $workDirectory -MountDirectory $Mount -ImageFile $Wim -SourceIndex $Index | Out-Null
    try {
        Invoke-WinMintDism -ArgumentList @('/English', '/Mount-Image', "/ImageFile:$Wim", "/Index:$Index", "/MountDir:$Mount", '/ReadOnly') -Stage 'Mount-Image-ReadOnly'
    }
    catch {
        try {
            Invoke-WinMintDism -ArgumentList @('/English', '/Unmount-Image', "/MountDir:$Mount", '/Discard') -Stage 'Unmount-Discard'
            Remove-WinMintMountOwner -Kind boot
        }
        catch {
            Write-Debug "Mount-Image-ReadOnly cleanup after failure: $_"
        }
        return $false
    }
    $clean = $false
    $primaryError = $null
    try {
        $clean = (Get-WinPeApplyDefect -MountDir $Mount -WorkDirectory $workDirectory).Count -eq 0
    }
    catch {
        $primaryError = $_
        throw
    }
    finally {
        try {
            Invoke-WinMintDism -ArgumentList @('/English', '/Unmount-Image', "/MountDir:$Mount", '/Discard') -Stage 'Unmount-Discard'
            Remove-WinMintMountOwner -Kind boot
        }
        catch {
            $message = "Unmount boot.wim:$Index after apply check failed: $($_.Exception.Message)"
            if ($null -eq $primaryError) { throw $message }
            Write-Warning "$message (preserving earlier error: $($primaryError.Exception.Message))"
        }
    }
    return $clean
}

function Copy-WinMintBootWimEfiStage {
    param(
        [Parameter(Mandatory)] [string] $Wim,
        [Parameter(Mandatory)] [string] $Mount,
        [Parameter(Mandatory)] [int] $Index,
        [Parameter(Mandatory)] [string] $StageDir,
        [Parameter(Mandatory)] [string] $WorkDirectory
    )
    Write-WinMintMountOwner -Kind boot -WorkDirectory $WorkDirectory -MountDirectory $Mount -ImageFile $Wim -SourceIndex $Index | Out-Null
    try {
        Invoke-WinMintDism -ArgumentList @('/English', '/Mount-Image', "/ImageFile:$Wim", "/Index:$Index", "/MountDir:$Mount", '/ReadOnly') -Stage 'Mount-Image-ReadOnly'
    }
    catch {
        try {
            Invoke-WinMintDism -ArgumentList @('/English', '/Unmount-Image', "/MountDir:$Mount", '/Discard') -Stage 'Unmount-Discard'
            Remove-WinMintMountOwner -Kind boot
        }
        catch {
            Write-Debug "Mount-Image-ReadOnly cleanup after boot-file stage failure: $_"
        }
        throw
    }
    $primaryError = $null
    try {
        Clear-WinMintBootEfiStage -StageDir $StageDir
        Copy-WinMintBootEfiStage -MountDir $Mount -StageDir $StageDir
    }
    catch {
        $primaryError = $_
        throw
    }
    finally {
        try {
            Invoke-WinMintDism -ArgumentList @('/English', '/Unmount-Image', "/MountDir:$Mount", '/Discard') -Stage 'Unmount-Discard'
            Remove-WinMintMountOwner -Kind boot
        }
        catch {
            $message = "Unmount boot.wim:$Index after boot-file stage failed: $($_.Exception.Message)"
            if ($null -eq $primaryError) { throw $message }
            Write-Warning "$message (preserving earlier error: $($primaryError.Exception.Message))"
        }
    }
}

$bootEfiStage = Join-Path $WorkDirectory 'boot-efi'
$bootMount = Join-Path (Split-Path -Parent $mountDir) 'boot-mount'
if (Test-Path -LiteralPath $bootMount) {
    try {
        Invoke-WinMintDism -ArgumentList @('/English', '/Unmount-Image', "/MountDir:$bootMount", '/Discard') -Stage 'Unmount-Discard'
        Remove-WinMintMountOwner -Kind boot
    }
    catch {
        Write-Debug "Stale boot-mount discard before patch: $_"
    }
    Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $bootMount | Out-Null

$info = Invoke-WinMintDism -ArgumentList @('/English', '/Get-WimInfo', "/WimFile:$bootWim") -Stage 'Get-WimInfo' -PassThruText
$indexes = @([regex]::Matches($info, '(?m)^Index : (\d+)\s*$') | ForEach-Object { [int]$_.Groups[1].Value })
if ($indexes.Count -eq 0) { throw 'boot.wim has no indexes' }

$helperSrc = Get-WinPeApplyHelperPath -WorkDirectory $workDirectory
if (-not (Test-Path -LiteralPath $helperSrc -PathType Leaf)) {
    throw "WinMintApply.exe missing under $helperSrc. Run: just publish-provisioning"
}

# Skip only when marker + every boot index proves the authoritative apply launcher contract
# and this run did not Add-Package an LCU (LCU can overwrite winpeshl.ini).
if (Test-Path -LiteralPath $bootMarker) {
    if (-not $applyQuality) {
        $markerText = (Get-Content -LiteralPath $bootMarker -Raw -Encoding utf8).Trim()
        $allIndexesPatched = $markerText -eq $expectedMarker
        if ($allIndexesPatched) {
            foreach ($index in $indexes) {
                if (-not (Test-LaunchApplyPatched -Wim $bootWim -Mount $bootMount -Index $index)) {
                    $allIndexesPatched = $false
                    break
                }
            }
        }
        if ($allIndexesPatched) {
            Copy-WinMintBootWimEfiStage -Wim $bootWim -Mount $bootMount -Index $indexes[-1] -StageDir $bootEfiStage -WorkDirectory $WorkDirectory
            Publish-WinMintStagedBootSet -MediaDir $mediaDir -StageDir $bootEfiStage
            Remove-Item -LiteralPath $legacyMarker -Force -ErrorAction SilentlyContinue
            Write-Output 'PatchBootWimApply skipped (already patched; LaunchApply verified in every boot.wim index)'
            Write-Output 'PatchBootWimApply copied boot.stl to efi\microsoft\boot\boot.stl'
            Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
            exit 0
        }
        Write-Output "PatchBootWimApply re-patch (marker='$markerText' or LaunchApply mismatch)"
        Remove-Item -LiteralPath $bootMarker -Force -ErrorAction SilentlyContinue
    }
}

$bootItem = Get-Item -LiteralPath $bootWim
if ($bootItem.IsReadOnly) { $bootItem.IsReadOnly = $false }

$winpeshl = Get-WinPeApplyWinpeshlText
Clear-WinMintBootEfiStage -StageDir $bootEfiStage

foreach ($index in $indexes) {
    Write-Output "Patch boot.wim index $index (WinPE apply launcher)"
    Write-WinMintMountOwner -Kind boot -WorkDirectory $workDirectory -MountDirectory $bootMount -ImageFile $bootWim -SourceIndex $index | Out-Null
    Invoke-WinMintDism -ArgumentList @('/English', '/Mount-Image', "/ImageFile:$bootWim", "/Index:$index", "/MountDir:$bootMount") -Stage 'Mount-Image'
    try {
        if ($applyQuality) {
            foreach ($leaf in $bootPackages) {
                Invoke-WinMintDismAddPackage -MountDir $bootMount -PackagePath (Join-Path $QualityPackageDir $leaf)
            }
        }
        Copy-Item -LiteralPath $launchApplyPayload `
            -Destination (Join-Path $bootMount 'Windows\System32\LaunchApply.cmd') -Force
        Copy-Item -LiteralPath $helperSrc `
            -Destination (Join-Path $bootMount 'Windows\System32\WinMintApply.exe') -Force
        Set-Content -LiteralPath (Join-Path $bootMount 'Windows\System32\winpeshl.ini') -Value $winpeshl -Encoding ascii
        $desktopSrc = Join-Path (Split-Path -Parent $launchApplyPayload) 'winpe.jpg'
        Copy-WinMintWinPeDesktop -Source $desktopSrc -Destination (Join-Path $bootMount 'Windows\System32\winpe.jpg')
        Copy-WinMintBootEfiStage -MountDir $bootMount -StageDir $bootEfiStage
    }
    finally {
        Invoke-WinMintDism -ArgumentList @('/English', '/Unmount-Image', "/MountDir:$bootMount", '/Commit') -Stage 'Unmount-Commit'
        Remove-WinMintMountOwner -Kind boot
    }
}

Set-Content -LiteralPath $bootMarker -Value $expectedMarker -Encoding utf8
# Apply lane supersedes legacy LabConfig-in-boot.wim marker; leave no ambiguous dual story.
Remove-Item -LiteralPath $legacyMarker -Force -ErrorAction SilentlyContinue

$winreSrc = Join-Path $MountDir 'Windows\System32\Recovery\Winre.wim'
$winrePackages = @(Get-WinMintQualityPackageLeaf -PackageDir $QualityPackageDir -Kind winre)
if ((Test-Path -LiteralPath $winreSrc) -and $winrePackages.Count -gt 0) {
    Write-Output 'PatchBootWimApply Safe OS DU on WinRE'
    $winreTmp = Join-Path $WorkDirectory 'winre.wim'
    Copy-Item -LiteralPath $winreSrc -Destination $winreTmp -Force
    $winreItem = Get-Item -LiteralPath $winreTmp
    if ($winreItem.IsReadOnly) { $winreItem.IsReadOnly = $false }
    Write-WinMintMountOwner -Kind boot -WorkDirectory $workDirectory -MountDirectory $bootMount -ImageFile $winreTmp -SourceIndex 1 | Out-Null
    Invoke-WinMintDism -ArgumentList @('/English', '/Mount-Image', "/ImageFile:$winreTmp", "/MountDir:$bootMount", '/Index:1') -Stage 'Mount-Image'
    try {
        foreach ($leaf in $winrePackages) {
            Invoke-WinMintDismAddPackage -MountDir $bootMount -PackagePath (Join-Path $QualityPackageDir $leaf)
        }
    }
    finally {
        Invoke-WinMintDism -ArgumentList @('/English', '/Unmount-Image', "/MountDir:$bootMount", '/Commit') -Stage 'Unmount-Commit'
        Remove-WinMintMountOwner -Kind boot
    }
    Copy-Item -LiteralPath $winreTmp -Destination $winreSrc -Force
    Remove-Item -LiteralPath $winreTmp -Force -ErrorAction SilentlyContinue
}

Publish-WinMintStagedBootSet -MediaDir $mediaDir -StageDir $bootEfiStage
Write-Output 'PatchBootWimApply copied boot.stl to efi\microsoft\boot\boot.stl'

Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
Write-Output 'PatchBootWimApply ok'
exit 0
}
