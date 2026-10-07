#requires -Version 7.6
# Servicing boundary: run DISM with raw stdout/stderr in dism-transcript.log only.
Set-StrictMode -Version Latest

function Test-WinMintDismProgressBarLine {
    param([Parameter(Mandatory)] [string] $Line)
    return [bool]($Line -match '^\s*\[.*\d+\.\d+%\s*\]')
}

function Invoke-WinMintDism {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $ArgumentList,

        [string] $Stage = '',

        [switch] $PassThruText,

        [string] $DismPath = 'dism.exe'
    )

    $work = $env:WINMINT_SERVICING_WORK
    if ([string]::IsNullOrWhiteSpace($work)) {
        throw 'WINMINT_SERVICING_WORK is unset or blank; set it to the Servicing work directory before calling Invoke-WinMintDism.'
    }

    $transcriptPath = Join-Path $work 'dism-transcript.log'
    $null = New-Item -ItemType Directory -Force -Path $work

    $argvText = ($ArgumentList | ForEach-Object { if ($_ -match '\s') { """$_""" } else { $_ } }) -join ' '
    $banner = "=== stage=$Stage argv=$argvText ==="

    $stdoutFile = [IO.Path]::GetTempFileName()
    $stderrFile = [IO.Path]::GetTempFileName()
    try {
        # Do not use Start-Process -Wait: after Mount-Image, dism.exe can exit while -Wait
        # never returns (smoke hung ~1h with MountStatus Ok / no Mount-Image transcript).
        $proc = Start-Process -FilePath $DismPath -ArgumentList $ArgumentList -PassThru -NoNewWindow `
            -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
        $null = $proc.WaitForExit()
        $exitCode = $proc.ExitCode
    }
    finally {
        $stdoutRaw = if (Test-Path -LiteralPath $stdoutFile) { Get-Content -LiteralPath $stdoutFile -Raw -Encoding utf8 } else { '' }
        $stderrRaw = if (Test-Path -LiteralPath $stderrFile) { Get-Content -LiteralPath $stderrFile -Raw -Encoding utf8 } else { '' }
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    }

    if ($null -eq $stdoutRaw) { $stdoutRaw = '' }
    if ($null -eq $stderrRaw) { $stderrRaw = '' }

    $combined = New-Object System.Text.StringBuilder
    [void]$combined.Append($stdoutRaw)
    if ($stderrRaw.Length -gt 0) {
        if ($combined.Length -gt 0 -and -not $combined.ToString().EndsWith("`n")) { [void]$combined.Append("`n") }
        [void]$combined.Append($stderrRaw)
    }
    $capture = $combined.ToString()

    $utf8 = New-Object System.Text.UTF8Encoding $false
    $chunk = $banner + "`n" + $capture
    if ($capture.Length -gt 0 -and -not $capture.EndsWith("`n")) { $chunk += "`n" }
    [IO.File]::AppendAllText($transcriptPath, $chunk, $utf8)

    $LASTEXITCODE = $exitCode
    if ($exitCode -ne 0) {
        throw "DISM failed (exit $exitCode). See transcript: $transcriptPath"
    }

    if ($PassThruText) {
        return $capture
    }
}
