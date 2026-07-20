#Requires -Version 7.6
# Dot-sourced by WinMint-VmConsole.ps1 — SetupComplete hard/soft log classification.

function Get-WinMintVmSetupCompleteLogLines {
    param([string]$Path)

    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }
    return @(
        Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { $_ }
    )
}

function Test-WinMintVmSetupCompleteLogEvidence {
    <#
    .SYNOPSIS
        Classify SetupComplete_errors.log (hard plumbing) vs SetupComplete_warnings.log (soft).
    #>
    param(
        [Parameter(Mandatory)][string]$EvidenceDir
    )

    $errorsPath = Join-Path $EvidenceDir 'ProgramData-Logs\SetupComplete_errors.log'
    $warningsPath = Join-Path $EvidenceDir 'ProgramData-Logs\SetupComplete_warnings.log'
    $errorLines = @(Get-WinMintVmSetupCompleteLogLines -Path $errorsPath)
    $warningLines = @(Get-WinMintVmSetupCompleteLogLines -Path $warningsPath)

    $plumbingFailures = [System.Collections.Generic.List[string]]::new()
    $softWarnings = [System.Collections.Generic.List[string]]::new()

    if ($errorLines.Count -gt 0) {
        $preview = ($errorLines | Select-Object -First 3) -join ' | '
        if ($errorLines.Count -gt 3) { $preview = "$preview | …($($errorLines.Count) lines)" }
        $plumbingFailures.Add("SetupComplete_errors.log is non-empty: $preview") | Out-Null
    }

    if ($warningLines.Count -gt 0) {
        $preview = ($warningLines | Select-Object -First 3) -join ' | '
        if ($warningLines.Count -gt 3) { $preview = "$preview | …($($warningLines.Count) lines)" }
        $softWarnings.Add("SetupComplete_warnings.log: $preview") | Out-Null
    }

    [pscustomobject]@{
        plumbingOk         = ($plumbingFailures.Count -eq 0)
        plumbingFailures   = @($plumbingFailures)
        softWarnings       = @($softWarnings)
        errorLineCount     = $errorLines.Count
        warningLineCount   = $warningLines.Count
        errorsPath         = $errorsPath
        warningsPath       = $warningsPath
    }
}
