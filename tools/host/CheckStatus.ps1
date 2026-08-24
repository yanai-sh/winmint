#requires -Version 7.6
# Check status: watch-only projection of a just check run. Not control plane.

Set-StrictMode -Version Latest

function Write-CheckStatus {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $RunId,
        [Parameter(Mandatory)][string] $Phase,
        [string] $Leaf = '',
        [string] $LastHostLine = '',
        [int] $Index = 0,
        [int] $Count = 0
    )
    try {
        $dir = Split-Path -Parent $Path
        if ($dir) {
            New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null
        }
        $doc = [ordered]@{
            schemaVersion = 'winmint.check.status/v1'
            updatedAt     = [datetime]::UtcNow.ToString('o')
            runId         = $RunId
            phase         = $Phase
            leaf          = $Leaf
            lastHostLine  = $LastHostLine
        }
        if ($Count -gt 0) {
            $doc.index = $Index
            $doc.count = $Count
        }
        ($doc | ConvertTo-Json -Compress) | Set-Content -LiteralPath $Path -Encoding utf8 -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not write Check status: $($_.Exception.Message)"
    }
}

function Get-CheckWatchVerdict {
    param([string] $Phase = '')
    if ($Phase -in @('passed', 'failed')) {
        return 'done'
    }
    return 'continue'
}
