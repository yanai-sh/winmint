#requires -Version 7.6
<#
.SYNOPSIS
  What "this boot.wim is patched for WinPE apply" means.
.NOTES
  Dot-sourced by Patch-BootWimApply (skip-or-re-patch), Publish-UsbMedia, the USB static
  verifier, and tools/apply/Assert-ApplyEvidence (pre-wipe gate). One definition on purpose:
  the gate certifies the media the patcher produced, so a rule taught to one side and not
  the other greens media the patcher would have rejected.
  Not a kernel — no opcode maps here.
#>

function Get-WinPeApplyPayloadPath {
    return Join-Path (Split-Path -Parent $PSScriptRoot) 'payload\winpe\LaunchApply.cmd'
}

function Get-WinPeApplyHelperPath {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WorkDirectory
    )
    return Join-Path $WorkDirectory 'payload\WinMintApply.exe'
}

function Get-WinPeApplyMarkerText {
    return 'apply+wimIndex=1+winpeshlLaunchApp+cmdCall'
}

function Get-WinPeApplyWinpeshlText {
    # Learn: [LaunchApp] AppPath is a Windows-subsystem exe with no arguments.
    # [LaunchApps] + a .cmd is how v2 painted X:\windows\system32\cmd.exe (#119).
    return "[LaunchApp]`r`nAppPath = %SYSTEMDRIVE%\Windows\System32\WinMintApply.exe`r`n"
}

function Get-WinPeApplyDefect {
    <#
    .SYNOPSIS
      Reasons a mounted boot.wim is not WinMint apply media. Empty = patched.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $MountDir,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WorkDirectory
    )

    $defects = @()
    $launch = Join-Path $MountDir 'Windows\System32\LaunchApply.cmd'
    $payload = Get-WinPeApplyPayloadPath
    $winpeshl = Join-Path $MountDir 'Windows\System32\winpeshl.ini'
    $payloadAvailable = Test-Path -LiteralPath $payload -PathType Leaf
    if (-not $payloadAvailable) {
        $defects += "authoritative payload/winpe/LaunchApply.cmd missing: $payload"
    }

    if (-not (Test-Path -LiteralPath $launch)) {
        $defects += 'LaunchApply.cmd missing inside boot.wim'
    }
    else {
        if ($payloadAvailable) {
            if ((Get-FileHash -LiteralPath $launch -Algorithm SHA256).Hash -cne
                (Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash) {
                $defects += 'LaunchApply.cmd bytes differ from authoritative payload/winpe/LaunchApply.cmd'
            }
        }

        # ASCII-compatible authoritative payload; semantic defects explain dangerous drift clearly.
        $body = Get-Content -LiteralPath $launch -Raw -Encoding ascii
        if ($body -notlike '*/Index:1*') {
            $defects += 'LaunchApply.cmd must Apply-Image /Index:1 (single-image export)'
        }
        if ($body -match '/Index:(\d+)' -and [int]$Matches[1] -ne 1) {
            $defects += "LaunchApply.cmd has wrong /Index:$($Matches[1]) (need 1)"
        }
        # Media patched before the target-disk guard existed picks no disk — it erases disk 0.
        if ($body -notmatch 'winmint_pick') {
            $defects += 'LaunchApply.cmd predates the target-disk guard (no winmint_pick): it would erase disk 0'
        }
        # The stick is the volume WinPE booted from, not a diskpart Type line that says USB.
        # The boot-disk subroutine is defined below `clean`; the call that runs first is what matters.
        $findAt = $body.IndexOf('call :winmint_find_install')
        $bootCleanAt = $body.IndexOf('echo clean')
        if ($body -notmatch 'PEBootRamdiskSourceDrive' -or $body -notmatch 'call :winmint_boot_disk' -or
            $body -notmatch 'if "%N%"=="%BOOTDISK%"' -or
            $findAt -lt 0 -or $bootCleanAt -lt 0 -or $findAt -ge $bootCleanAt) {
            $defects += 'LaunchApply.cmd must resolve PEBootRamdiskSourceDrive and skip that disk before diskpart clean'
        }
        # HKCU\Console\QuickEdit is read when the console is created. A Hyper-V click in Select Mode
        # pauses DISM until another click/Enter; media without this line still has that stall.
        if ($body -notmatch 'reg add HKCU\\Console /v QuickEdit /t REG_DWORD /d 0 /f') {
            $defects += 'LaunchApply.cmd must disable console Quick Edit (Hyper-V click pauses DISM)'
        }
        # A second USB boot used to reach `clean` again. The marker has to be tested first.
        $appliedAt = $body.IndexOf('winmint-applied.txt')
        $cleanAt = $body.IndexOf('echo clean')
        if ($appliedAt -lt 0 -or $cleanAt -lt 0 -or $appliedAt -ge $cleanAt) {
            $defects += 'LaunchApply.cmd must notice winmint-applied.txt before diskpart clean'
        }
        if ($body -notmatch 'wpeutil shutdown') {
            $defects += 'LaunchApply.cmd must shut down instead of erasing when WinMint is already installed'
        }
        $installAt = $body.IndexOf('if not exist "%INSTALL%:\winmint-install.txt"')
        $seeAt = $body.IndexOf('call :winmint_see_payload')
        $diskpartAt = $body.IndexOf('diskpart /s')
        if ($installAt -lt 0 -or $seeAt -lt 0 -or $findAt -lt 0 -or $diskpartAt -lt 0 -or
            $seeAt -ge $installAt -or $installAt -ge $findAt -or $installAt -ge $diskpartAt) {
            $defects += 'LaunchApply.cmd must read winmint-install.txt before diskpart and before it resolves the boot disk'
        }
        if ($body -notmatch '/offline /bootex') {
            $defects += 'LaunchApply.cmd must bcdboot /offline /bootex (2023 UEFI CA boot manager)'
        }
        # WinRE is registered from the recovery partition created after apply, not from System32\Recovery.
        if ($body -notmatch '/setreimage /path R:\\Recovery\\WindowsRE /target W:\\Windows') {
            $defects += 'LaunchApply.cmd must register WinRE from R:\Recovery\WindowsRE'
        }
        # A bare wpeinit waits on Wi-Fi DHCP. The blue desktop never reaches shutdown.
        $earlyAt = $body.IndexOf('if not exist "%SEEN%:\winmint-install.txt"')
        $initAt = $body.IndexOf('call :winmint_init_pe')
        $longAt = $body.IndexOf('for /L %%i in (1,1,10) do if not defined SEEN call :winmint_see_payload')
        if ($earlyAt -lt 0 -or $initAt -lt 0 -or $longAt -lt 0 -or $earlyAt -ge $initAt -or $initAt -ge $longAt -or
            $body -notmatch 'wpeinit -unattend:"%~dp0wpeinit\.xml"' -or $body -match '(?m)^call wpeinit\s*$') {
            $defects += 'LaunchApply.cmd must shut down a missing install file before wpeinit, and wpeinit must disable the network'
        }
    }

    $wpeXml = Join-Path $MountDir 'Windows\System32\wpeinit.xml'
    if (-not (Test-Path -LiteralPath $wpeXml -PathType Leaf) -or
        (Get-Content -LiteralPath $wpeXml -Raw -Encoding utf8) -notmatch '<EnableNetwork>\s*false\s*</EnableNetwork>') {
        $defects += 'wpeinit.xml must set EnableNetwork false'
    }

    if (-not (Test-Path -LiteralPath $winpeshl)) {
        $defects += 'winpeshl.ini missing inside boot.wim'
    }
    elseif ((Get-Content -LiteralPath $winpeshl -Raw -Encoding ascii) -notmatch '(?is)\[LaunchApp\].*AppPath\s*=\s*%SYSTEMDRIVE%\\Windows\\System32\\WinMintApply\.exe') {
        $defects += 'winpeshl.ini must [LaunchApp] AppPath WinMintApply.exe'
    }

    $helper = Join-Path $MountDir 'Windows\System32\WinMintApply.exe'
    $helperSrc = Get-WinPeApplyHelperPath -WorkDirectory $WorkDirectory
    if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) {
        $defects += 'WinMintApply.exe missing inside boot.wim'
    }
    elseif (-not (Test-Path -LiteralPath $helperSrc -PathType Leaf)) {
        $defects += "WinMintApply.exe helper source missing: $helperSrc"
    }
    elseif ((Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash -cne
        (Get-FileHash -LiteralPath $helperSrc -Algorithm SHA256).Hash) {
        $defects += 'WinMintApply.exe bytes differ from work payload'
    }

    # Learn: WinPE paints windows\system32\winpe.jpg as the desktop. A 1x1 file does not cover
    # the panel, so the stock blue field stays up. The frame has to be a real baseline JPEG.
    $desktop = Join-Path $MountDir 'Windows\System32\winpe.jpg'
    $desktopSrc = Join-Path (Split-Path -Parent (Get-WinPeApplyPayloadPath)) 'winpe.jpg'
    if (-not (Test-Path -LiteralPath $desktop -PathType Leaf)) {
        $defects += 'winpe.jpg missing inside boot.wim (WinPE desktop must be black)'
    }
    elseif (-not (Test-Path -LiteralPath $desktopSrc -PathType Leaf)) {
        $defects += "winpe.jpg payload missing: $desktopSrc"
    }
    elseif ((Get-FileHash -LiteralPath $desktop -Algorithm SHA256).Hash -cne
        (Get-FileHash -LiteralPath $desktopSrc -Algorithm SHA256).Hash) {
        $defects += 'winpe.jpg bytes differ from payload/winpe/winpe.jpg'
    }
    elseif (-not (Test-WinMintWinPeDesktopJpeg -Path $desktop)) {
        $defects += 'winpe.jpg must be a baseline JPEG at least 640x480 (a 1x1 file leaves the stock blue desktop)'
    }

    return , ([string[]] $defects)
}

function Test-WinMintWinPeDesktopJpeg {
    <#
    .SYNOPSIS
      Baseline JPEG large enough that center, tile, or stretch covers the WinPE desktop.
      Cast before the shift: a [byte] shift drops the high half and a 2880-wide frame reads as 64.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 10 -or $bytes[0] -ne 0xFF -or $bytes[1] -ne 0xD8) { return $false }
    $i = 2
    while ($i -lt ($bytes.Length - 9)) {
        if ($bytes[$i] -ne 0xFF) { $i++; continue }
        $marker = [int] $bytes[$i + 1]
        if ($marker -eq 0x00 -or $marker -eq 0xD8 -or $marker -eq 0xD9 -or $marker -eq 0x01 -or
            ($marker -ge 0xD0 -and $marker -le 0xD7)) {
            $i += 2
            continue
        }
        $length = ([int] $bytes[$i + 2] -shl 8) -bor [int] $bytes[$i + 3]
        if ($marker -ge 0xC0 -and $marker -le 0xCF -and $marker -ne 0xC4 -and $marker -ne 0xC8 -and $marker -ne 0xCC) {
            if ($marker -ne 0xC0) { return $false }
            $height = ([int] $bytes[$i + 5] -shl 8) -bor [int] $bytes[$i + 6]
            $width = ([int] $bytes[$i + 7] -shl 8) -bor [int] $bytes[$i + 8]
            return $width -ge 640 -and $height -ge 480
        }
        if ($marker -eq 0xDA -or $length -lt 2) { return $false }
        $i += 2 + $length
    }
    return $false
}

function Get-WinPeWimIndex {
    <#
    .SYNOPSIS
      Explicit image indexes from DISM Get-WimInfo or wimlib-imagex info text.
      A gap stays a gap. Image Count is not expanded to 1..N.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    # DISM Get-WimInfo: "Index : N".
    # wimlib-imagex info (libwim-15 "Index:                  %d"): "Index:" then whitespace then N.
    # "Boot Index" and "Image Count" are single header fields, not the image list.
    $found = [Collections.Generic.List[int]]::new()
    foreach ($match in [regex]::Matches($Text, '(?m)^(?:Index : |Index:\s+)(\d+)\s*$')) {
        $found.Add([int] $match.Groups[1].Value)
    }
    return , ([int[]] $found.ToArray())
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
