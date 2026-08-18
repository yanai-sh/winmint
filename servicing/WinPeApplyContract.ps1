#requires -Version 7.6
<#
.SYNOPSIS
  What "this boot.wim is patched for WinPE apply" means.
.NOTES
  Dot-sourced by Patch-BootWimApply (skip-or-re-patch) and by tools/apply/Assert-ApplyEvidence
  (pre-wipe gate). One definition on purpose: the gate certifies the media the patcher produced,
  so a rule taught to one side and not the other greens media the patcher would have rejected.
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
        # HKCU\Console\QuickEdit is read when the console is created. A Hyper-V click in Select Mode
        # pauses DISM until another click/Enter; media without this line still has that stall.
        if ($body -notmatch 'reg add HKCU\\Console /v QuickEdit /t REG_DWORD /d 0 /f') {
            $defects += 'LaunchApply.cmd must disable console Quick Edit (Hyper-V click pauses DISM)'
        }
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

    return , ([string[]] $defects)
}
