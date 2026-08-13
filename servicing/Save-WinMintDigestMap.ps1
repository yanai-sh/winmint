#requires -Version 7.6
Set-StrictMode -Version Latest

function Save-WinMintDigestMap {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    param(
        [Parameter(Mandatory)] [string] $WorkDirectory,
        [Parameter(Mandatory)] [hashtable] $Digests
    )
    $logDir = Join-Path $WorkDirectory 'logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $digestPath = Join-Path $logDir 'digests.json'
    $map = [ordered]@{}
    if (Test-Path -LiteralPath $digestPath) {
        foreach ($p in (Get-Content -LiteralPath $digestPath -Raw | ConvertFrom-Json).PSObject.Properties) {
            $map[[string]$p.Name] = [string]$p.Value
        }
    }
    foreach ($k in $Digests.Keys) { $map[[string]$k] = [string]$Digests[$k] }
    $map | ConvertTo-Json | Set-Content -LiteralPath $digestPath -Encoding utf8
}
