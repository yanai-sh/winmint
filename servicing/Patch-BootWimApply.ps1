#requires -Version 7.6
param(
    [Parameter(Mandatory)] [string] $MediaDir,
    [Parameter(Mandatory)] [string] $MountDir,
    [Parameter(Mandatory)] [string] $WorkDirectory
)
$mediaDir = $MediaDir
$mountDir = $MountDir
# Source-ISO edition index is unrelated: after single-image export, apply target is always index 1.
. (Join-Path $PSScriptRoot 'WinPeApplyContract.ps1')
. (Join-Path $PSScriptRoot 'Resolve-WinMintMount.ps1')
$workDirectory = $WorkDirectory
$launchApplyPayload = Get-WinPeApplyPayloadPath
$expectedMarker = Get-WinPeApplyMarkerText

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
    & dism.exe /English /Mount-Image /ImageFile:$Wim /Index:$Index /MountDir:$Mount /ReadOnly
    if ($LASTEXITCODE -ne 0) {
        & dism.exe /English /Unmount-Image /MountDir:$Mount /Discard 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { Remove-WinMintMountOwner -Kind boot }
        return $false
    }
    $clean = $false
    $primaryError = $null
    try {
        $clean = (Get-WinPeApplyDefect -MountDir $Mount).Count -eq 0
    }
    catch {
        $primaryError = $_
        throw
    }
    finally {
        & dism.exe /English /Unmount-Image /MountDir:$Mount /Discard | Out-Null
        $unmountExit = $LASTEXITCODE
        if ($unmountExit -eq 0) {
            Remove-WinMintMountOwner -Kind boot
        }
        else {
            $message = "Unmount boot.wim:$Index after apply check failed: $unmountExit"
            if ($null -eq $primaryError) { throw $message }
            Write-Warning "$message (preserving earlier error: $($primaryError.Exception.Message))"
        }
    }
    return $clean
}

$bootMount = Join-Path (Split-Path -Parent $mountDir) 'boot-mount'
if (Test-Path -LiteralPath $bootMount) {
    & dism.exe /English /Unmount-Image /MountDir:$bootMount /Discard 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Remove-WinMintMountOwner -Kind boot }
    Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $bootMount | Out-Null

$info = & dism.exe /English /Get-WimInfo /WimFile:$bootWim 2>&1 | Out-String
$indexes = @([regex]::Matches($info, '(?m)^Index : (\d+)\s*$') | ForEach-Object { [int]$_.Groups[1].Value })
if ($indexes.Count -eq 0) { throw 'boot.wim has no indexes' }

# Skip only when marker + every boot index proves the authoritative apply launcher contract.
if (Test-Path -LiteralPath $bootMarker) {
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

$bootItem = Get-Item -LiteralPath $bootWim
if ($bootItem.IsReadOnly) { $bootItem.IsReadOnly = $false }

$winpeshl = @"
[LaunchApps]
%SYSTEMDRIVE%\Windows\System32\LaunchApply.cmd
"@

foreach ($index in $indexes) {
    Write-Output "Patch boot.wim index $index (WinPE apply launcher)"
    Write-WinMintMountOwner -Kind boot -WorkDirectory $workDirectory -MountDirectory $bootMount -ImageFile $bootWim -SourceIndex $index | Out-Null
    & dism.exe /English /Mount-Image /ImageFile:$bootWim /Index:$index /MountDir:$bootMount
    if ($LASTEXITCODE -ne 0) { throw "Mount boot.wim:$index failed: $LASTEXITCODE" }
    try {
        Copy-Item -LiteralPath $launchApplyPayload `
            -Destination (Join-Path $bootMount 'Windows\System32\LaunchApply.cmd') -Force
        Set-Content -LiteralPath (Join-Path $bootMount 'Windows\System32\winpeshl.ini') -Value $winpeshl -Encoding ascii
    }
    finally {
        & dism.exe /English /Unmount-Image /MountDir:$bootMount /Commit
        if ($LASTEXITCODE -ne 0) { throw "Unmount boot.wim:$index failed: $LASTEXITCODE" }
        Remove-WinMintMountOwner -Kind boot
    }
}

Set-Content -LiteralPath $bootMarker -Value $expectedMarker -Encoding utf8
# Apply lane supersedes legacy LabConfig-in-boot.wim marker; leave no ambiguous dual story.
Remove-Item -LiteralPath $legacyMarker -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
Write-Output 'PatchBootWimApply ok'
exit 0
