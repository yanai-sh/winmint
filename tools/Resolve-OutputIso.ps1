#requires -Version 7.6
<#
.SYNOPSIS
  Shared Output ISO resolution ladder. Dot-source; do not run directly.

.DESCRIPTION
  One ladder for every gate: evidence.outputIsoPath -> newest winmint_*.iso -> legacy out.iso.
  ImageServicing owns the default leaf (winmint_{profile}_{lane}_{timestamp}.iso); consumers here
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

    $named = @(Get-ChildItem -LiteralPath $WorkDirectory -Filter 'winmint_*.iso' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    if ($named.Count -ge 1) {
        return $named[0].FullName
    }

    $legacy = Join-Path $WorkDirectory 'out.iso'
    if (Test-Path -LiteralPath $legacy) {
        return (Resolve-Path -LiteralPath $legacy).Path
    }

    return $null
}
