#requires -Version 7.6
Set-StrictMode -Version Latest

function Save-WinMintDigestMap {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $WorkDirectory,
        [Parameter(Mandatory)] [hashtable] $Digests
    )
    $logDir = Join-Path $WorkDirectory 'logs'
    $digestPath = Join-Path $logDir 'digests.json'
    if (-not $PSCmdlet.ShouldProcess($digestPath, 'Save digest map')) { return }
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $map = [ordered]@{}
    if (Test-Path -LiteralPath $digestPath) {
        foreach ($p in (Get-Content -LiteralPath $digestPath -Raw | ConvertFrom-Json).PSObject.Properties) {
            $map[[string]$p.Name] = [string]$p.Value
        }
    }
    foreach ($k in $Digests.Keys) { $map[[string]$k] = [string]$Digests[$k] }
    $map | ConvertTo-Json | Set-Content -LiteralPath $digestPath -Encoding utf8
}
