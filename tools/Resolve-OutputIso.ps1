#requires -Version 7.6
<#
.SYNOPSIS
  Shared Output ISO resolution ladder. Dot-source; do not run directly.

.DESCRIPTION
  One ladder for every gate: evidence.outputIsoPath -> single winmint_*.iso -> legacy out.iso.
  ImageServicing owns the default leaf (winmint_{profile}_{lane}.iso); consumers here
  must not re-derive it. Returns $null when nothing resolves — callers decide whether that is fatal.
#>

function Resolve-WinMintOutputIso {
    param(
        [Parameter(Mandatory)][string] $WorkDirectory,

        # Parsed evidence.json. Omit to read {WorkDirectory}\evidence.json when present.
        $Evidence = $null
    )

    if ($null -eq $Evidence) {
        $evidencePath = Join-Path $WorkDirectory 'evidence.json'
        if (Test-Path -LiteralPath $evidencePath) {
            $Evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding utf8 | ConvertFrom-Json
        }
    }

    if ($null -ne $Evidence -and $Evidence.PSObject.Properties.Name -contains 'outputIsoPath') {
        $claimed = [string]$Evidence.outputIsoPath
        if (-not [string]::IsNullOrWhiteSpace($claimed) -and (Test-Path -LiteralPath $claimed)) {
            return (Resolve-Path -LiteralPath $claimed).Path
        }
    }

    $named = @(Get-ChildItem -LiteralPath $WorkDirectory -Filter 'winmint_*.iso' -File -ErrorAction SilentlyContinue)
    if ($named.Count -eq 1) {
        return (Resolve-Path -LiteralPath $named[0].FullName).Path
    }
    if ($named.Count -gt 1) {
        throw "Multiple winmint_*.iso under $WorkDirectory — set evidence.outputIsoPath (do not pick by LastWriteTime)"
    }

    $legacy = Join-Path $WorkDirectory 'out.iso'
    if (Test-Path -LiteralPath $legacy) {
        return (Resolve-Path -LiteralPath $legacy).Path
    }

    return $null
}

<#
.SYNOPSIS
  Drop prior Output ISO leaves in a workdir so Apply cannot stack multi-GB ISOs.
.PARAMETER KeepPath
  Full path to retain (usually the ISO this run will write or -SkipApply reuse). Empty = delete all.
#>
function Clear-WinMintPriorOutputIsos {
    param(
        [Parameter(Mandatory)][string] $WorkDirectory,
        [string] $KeepPath = ''
    )

    if (-not (Test-Path -LiteralPath $WorkDirectory -PathType Container)) {
        return 0
    }

    $keep = $null
    if (-not [string]::IsNullOrWhiteSpace($KeepPath)) {
        $keep = [IO.Path]::GetFullPath($KeepPath.Trim())
    }

    $removed = 0
    $candidates = @(
        Get-ChildItem -LiteralPath $WorkDirectory -Filter 'winmint_*.iso' -File -ErrorAction SilentlyContinue
    )
    $legacy = Join-Path $WorkDirectory 'out.iso'
    if (Test-Path -LiteralPath $legacy -PathType Leaf) {
        $candidates += Get-Item -LiteralPath $legacy
    }

    foreach ($f in $candidates) {
        $full = [IO.Path]::GetFullPath($f.FullName)
        if ($null -ne $keep -and [string]::Equals($full, $keep, [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        try {
            Remove-Item -LiteralPath $full -Force
            $removed++
        }
        catch {
            Write-Warning "prior Output ISO still locked: $full ($($_.Exception.Message))"
        }
    }

    return $removed
}

<#
.SYNOPSIS
  Reclaim Apply staging under a workdir after evidence is copied (media/payload before VHD grows).
.NOTES
  Keeps Output ISO + evidence leaves. -Phase is call-site documentation only (Smoke Assert).
#>
function Clear-WinMintApplyStaging {
    param(
        [Parameter(Mandatory)][string] $WorkDirectory,
        [string] $Phase = 'Assert'
    )

    $null = $Phase
    if (-not (Test-Path -LiteralPath $WorkDirectory -PathType Container)) {
        return 0
    }

    $removed = 0
    foreach ($name in @('media', 'payload', 'quality-packages', 'install.wim')) {
        $path = Join-Path $WorkDirectory $name
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            Remove-Item -LiteralPath $path -Recurse -Force
            $removed++
        }
        catch {
            Write-Warning "Apply staging still locked: $path ($($_.Exception.Message))"
        }
    }

    foreach ($d in @(Get-ChildItem -LiteralPath $WorkDirectory -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'media.previous-*' -or $_.Name -like 'media.incoming-*' })) {
        try {
            Remove-Item -LiteralPath $d.FullName -Recurse -Force
            $removed++
        }
        catch {
            Write-Warning "Apply staging still locked: $($d.FullName) ($($_.Exception.Message))"
        }
    }

    return $removed
}
