#requires -Version 7.6
<#
.SYNOPSIS
  Own-console host watch for Smoke, Check, or Apply. Close it to stop watching, not the run.
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('smoke', 'check', 'apply')]
    [string] $Kind,

    [string] $Work = '',
    [string] $Path = '',
    # Invoke-Smoke binds leftover or empty after it already stamped this run.
    # Unbound = standalone watch: leftover file id is prior.
    [string] $PriorRunId,
    [string] $MarkerPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $repoRoot 'tools/host/Write-WinMintHostProgress.ps1')

function Resolve-WinMintWatchDll {
    param([Parameter(Mandatory)] [string] $RepoRoot)
    # Prefer Smoke/host published leaf (just publish-watch → artifacts/watch).
    $published = Join-Path $RepoRoot 'artifacts/watch/WinMint.Watch.dll'
    if (Test-Path -LiteralPath $published -PathType Leaf) {
        return (Resolve-Path -LiteralPath $published).Path
    }
    foreach ($cfg in @('Release', 'Debug')) {
        $candidate = Join-Path $RepoRoot "src/WinMint.Watch/bin/$cfg/net11.0/WinMint.Watch.dll"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    $proj = Join-Path $RepoRoot 'src/WinMint.Watch/WinMint.Watch.csproj'
    if (-not (Test-Path -LiteralPath $proj -PathType Leaf)) { return '' }
    & dotnet publish $proj -c Release -o (Join-Path $RepoRoot 'artifacts/watch') -v q | Out-Null
    if ($LASTEXITCODE -ne 0) { return '' }
    if (Test-Path -LiteralPath $published -PathType Leaf) {
        return (Resolve-Path -LiteralPath $published).Path
    }
    return ''
}

$watchPriorRunId = ''
switch ($Kind) {
    'smoke' {
        . (Join-Path $repoRoot 'tools/vm/SmokeStatus.ps1')
        if ([string]::IsNullOrWhiteSpace($Work)) { $Work = Join-Path $repoRoot '.scratch\smoke' }
        $status = Join-Path $Work 'smoke-status.json'
        if (-not $PSBoundParameters.ContainsKey('PriorRunId')) {
            $watchPriorRunId = ''
            if (Test-Path -LiteralPath $status -PathType Leaf) {
                try {
                    $watchPriorRunId = [string]((Get-Content -LiteralPath $status -Raw -Encoding utf8 | ConvertFrom-Json).runId)
                }
                catch { $watchPriorRunId = '' }
            }
        }
        else {
            $watchPriorRunId = $PriorRunId
        }
    }
    'check' {
        . (Join-Path $repoRoot 'tools/host/CheckStatus.ps1')
        if ([string]::IsNullOrWhiteSpace($Path)) {
            $Path = Join-Path $repoRoot '.scratch\check-status.json'
        }
        $host.UI.RawUI.WindowTitle = "WinMint check watch — $Path"
        Write-Host ($PSStyle.Foreground.BrightBlack + 'Close this window to stop watching. just check keeps running.' + $PSStyle.Reset)
    }
    'apply' {
        . (Join-Path $repoRoot 'tools/host/WinMintPaths.ps1')
        if ([string]::IsNullOrWhiteSpace($Work)) {
            $Work = Get-WinMintGateBWorkDirectory
        }
    }
}

if ($Kind -in @('smoke', 'apply')) {
    $dll = Resolve-WinMintWatchDll -RepoRoot $repoRoot
    if (-not $dll) {
        Write-Error 'WinMint.Watch.dll not found; dotnet build src/WinMint.Watch/WinMint.Watch.csproj'
        exit 1
    }
    $execArgs = @(
        'exec', $dll,
        '--work', $Work,
        '--kind', $Kind
    )
    if ($Kind -eq 'smoke') {
        $execArgs += @('--prior-run-id', $watchPriorRunId)
    }
    if (-not [string]::IsNullOrWhiteSpace($MarkerPath)) {
        $execArgs += @('--marker-path', $MarkerPath)
    }
    $dotnet = (Get-Command dotnet -ErrorAction Stop).Source
    & $dotnet @execArgs
    exit $LASTEXITCODE
}

$doneTicks = 0
while ($true) {
    $verdict = ''
    $phase = ''
    $leaf = ''
    $lastHost = ''
    $format = @{ Title = $host.UI.RawUI.WindowTitle }

    if ($Kind -eq 'check') {
        $verdict = 'continue'
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            try {
                $doc = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
                $phase = [string]$doc.phase
                $leaf = if ($doc.PSObject.Properties.Name -contains 'leaf') { [string]$doc.leaf } else { '' }
                $lastHost = if ($doc.PSObject.Properties.Name -contains 'lastHostLine') { [string]$doc.lastHostLine } else { '' }
                $verdict = Get-CheckWatchVerdict -Phase $phase
            }
            catch {
                $verdict = 'continue'
            }
        }
        $format.Verdict = $verdict
        $format.Phase = $phase
        $format.Leaf = $leaf
        $format.LastHostLine = $lastHost
    }

    Clear-Host
    Write-Host (Format-WinMintHostWatch @format)

    if ($verdict -eq 'done') {
        $doneTicks++
        if ($doneTicks -ge 3) { break }
    }
    else {
        $doneTicks = 0
    }
    Start-Sleep -Seconds 2
}
