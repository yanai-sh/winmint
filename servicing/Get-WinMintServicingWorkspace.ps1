#requires -Version 7.6
Set-StrictMode -Version Latest

function Get-WinMintServicingWorkspace {
    param([Parameter(Mandatory)] [string] $Root)
    $manifest = Join-Path $Root 'workspace.json'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        throw "workspace.json missing: $manifest"
    }
    return Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
}
