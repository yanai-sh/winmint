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
    if (-not $haveMgfw -and -not $haveMgr) { return }
    $efiFiles = @(Get-ChildItem -LiteralPath $MediaDir -Force -Recurse -File -Filter 'b*.efi' -ErrorAction SilentlyContinue)
    foreach ($file in $efiFiles) {
        if ($haveMgfw -and $file.Name -match '^(?i)bootmgfw\.efi|bootx64\.efi|bootia32\.efi|bootaa64\.efi$') {
            Copy-WinMintMediaBootFile -Source $BootMgfw -Destination $file.FullName
        }
        elseif ($haveMgr -and $file.Name -match '^(?i)bootmgr\.efi$') {
            Copy-WinMintMediaBootFile -Source $BootMgr -Destination $file.FullName
        }
    }
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
            Remove-Item -LiteralPath $legacyMarker -Force -ErrorAction SilentlyContinue
            Write-Output 'PatchBootWimApply skipped (already patched; LaunchApply verified in every boot.wim index)'
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
        $efiDir = Join-Path $bootMount 'Windows\Boot\EFI'
        foreach ($leaf in @('boot.stl', 'bootmgfw.efi', 'bootmgr.efi')) {
            $src = Join-Path $efiDir $leaf
            if (Test-Path -LiteralPath $src -PathType Leaf) {
                New-Item -ItemType Directory -Force -Path $bootEfiStage | Out-Null
                Copy-Item -LiteralPath $src -Destination (Join-Path $bootEfiStage $leaf) -Force
            }
        }
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

if ($applyQuality) {
    $stlStaged = Join-Path $bootEfiStage 'boot.stl'
    if (-not (Test-Path -LiteralPath $stlStaged -PathType Leaf)) {
        throw 'Serviced boot.wim is missing Windows\Boot\EFI\boot.stl; Secure Boot media needs efi\microsoft\boot\boot.stl'
    }
    $mgfwStaged = Join-Path $bootEfiStage 'bootmgfw.efi'
    $mgrStaged = Join-Path $bootEfiStage 'bootmgr.efi'
    $mgfwArg = ''
    $mgrArg = ''
    if (Test-Path -LiteralPath $mgfwStaged -PathType Leaf) { $mgfwArg = $mgfwStaged }
    if (Test-Path -LiteralPath $mgrStaged -PathType Leaf) { $mgrArg = $mgrStaged }
    Publish-WinMintMediaBootFile -MediaDir $mediaDir -BootStl $stlStaged -BootMgfw $mgfwArg -BootMgr $mgrArg
    Write-Output 'PatchBootWimApply copied boot.stl to efi\microsoft\boot\boot.stl'
}

Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
Write-Output 'PatchBootWimApply ok'
exit 0
}
