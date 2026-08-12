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

function Get-WinPeApplyMarkerText {
    return 'apply+wimIndex=1'
}

function Get-WinPeApplyDefect {
    <#
    .SYNOPSIS
      Reasons a mounted boot.wim is not WinMint apply media. Empty = patched.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $MountDir
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
        $mountedBytes = [IO.File]::ReadAllBytes($launch)
        if ($payloadAvailable) {
            $payloadBytes = [IO.File]::ReadAllBytes($payload)
            if ([Convert]::ToBase64String($mountedBytes) -cne [Convert]::ToBase64String($payloadBytes)) {
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
    }

    if (-not (Test-Path -LiteralPath $winpeshl)) {
        $defects += 'winpeshl.ini missing inside boot.wim'
    }
    elseif ((Get-Content -LiteralPath $winpeshl -Raw -Encoding ascii) -notmatch 'LaunchApply\.cmd') {
        $defects += 'winpeshl.ini must launch LaunchApply.cmd'
    }

    return , ([string[]] $defects)
}
