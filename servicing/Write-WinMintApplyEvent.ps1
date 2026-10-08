#requires -Version 7.6
# Append-only operator events (apply-events.jsonl). Not an opcode kernel.
Set-StrictMode -Version Latest

function Format-WinMintApplyEventSummary {
    param([AllowEmptyString()][string] $Text = '')
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    if ($Text.Length -le 80) { return $Text }
    return ($Text.Substring(0, 79) + '…')
}

function Write-WinMintApplyEvent {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)]
        [ValidateSet('run.start', 'run.end', 'opcode.end', 'proof')]
        [string] $Kind,
        [string] $RunId = '',
        [string] $Opcode = '',
        [int] $Index = 0,
        [int] $Count = 0,
        [ValidateSet('', 'ok', 'fail')]
        [string] $Outcome = '',
        [int] $DurationMs = -1,
        [string] $Summary = '',
        [hashtable] $Detail = $null,
        [string] $ErrorMessage = '',
        [string] $TranscriptHint = '',
        [string] $Label = '',
        [double] $Percent = -1
    )
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        $RunId = [string]$env:WINMINT_SERVICING_RUN_ID
    }
    $row = [ordered]@{
        ts   = [datetime]::UtcNow.ToString('o')
        kind = $Kind
    }
    if (-not [string]::IsNullOrWhiteSpace($RunId)) { $row['runId'] = $RunId }
    if (-not [string]::IsNullOrWhiteSpace($Opcode)) { $row['opcode'] = $Opcode }
    if ($Index -gt 0) { $row['index'] = $Index }
    if ($Count -gt 0) { $row['count'] = $Count }
    if ($Outcome) { $row['outcome'] = $Outcome }
    if ($DurationMs -ge 0) { $row['durationMs'] = $DurationMs }
    $sum = Format-WinMintApplyEventSummary -Text $Summary
    if ($sum) { $row['summary'] = $sum }
    if ($null -ne $Detail -and $Detail.Count -gt 0) { $row['detail'] = $Detail }
    if ($Kind -eq 'proof') {
        if ($Label) { $row['label'] = $Label }
        if ($Percent -ge 0) { $row['percent'] = [Math]::Round($Percent, 1) }
    }
    if ($ErrorMessage -or $TranscriptHint) {
        $err = [ordered]@{}
        if ($ErrorMessage) { $err['message'] = Format-WinMintApplyEventSummary -Text $ErrorMessage }
        if ($TranscriptHint) { $err['transcriptHint'] = $TranscriptHint }
        $row['error'] = $err
    }
    $line = ($row | ConvertTo-Json -Compress -Depth 6)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Add-Content -LiteralPath $Path -Value $line -Encoding utf8
}
