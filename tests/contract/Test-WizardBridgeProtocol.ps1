#Requires -Version 7.6
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [System.Collections.Generic.List[string]]::new()
function Add-BridgeFailure([string]$Message) { $failures.Add($Message) | Out-Null }

. (Join-Path $root 'tools\ui-bridge\WinMint.UiBridgeProtocol.ps1')

$resultLine = ConvertTo-WinMintUiBridgeResultJson -Result ([ordered]@{
        Ok           = $true
        Architecture = 'ARM64'
        Editions     = @('Pro')
        Error        = ''
    })
$noisy = @(
    'mounting ISO...'
    '{"ok":true,"spoiler":1}'
    'INFO: still working'
    $resultLine
    'trailing noise'
) -join "`n"

$parsed = ConvertFrom-WinMintUiBridgeStdout -Stdout $noisy
if (-not $parsed) {
    Add-BridgeFailure 'Parser must find schemaVersion/type=result amid noisy stdout.'
}
elseif (-not [bool]$parsed.Ok -or [string]$parsed.Architecture -ne 'ARM64') {
    Add-BridgeFailure "Parser returned unexpected payload: $($parsed | ConvertTo-Json -Compress)"
}
elseif ([int]$parsed.schemaVersion -ne 1 -or [string]$parsed.type -ne 'result') {
    Add-BridgeFailure 'Result must carry schemaVersion=1 and type=result.'
}

$spoilerOnly = ConvertFrom-WinMintUiBridgeStdout -Stdout '{"ok":true,"spoiler":1}'
if ($null -ne $spoilerOnly) {
    Add-BridgeFailure 'Parser must ignore JSON without schemaVersion/type=result (no last-brace heuristic).'
}

$hostText = Get-Content -LiteralPath (Join-Path $root 'apps\setup-shell-web\WizardBridge.cs') -Raw
if ($hostText -match 'ParseLastJson') {
    Add-BridgeFailure 'WizardBridge must not keep ParseLastJson last-brace heuristic.'
}
if ($hostText -notmatch 'ParseBridgeResult' -or $hostText -notmatch 'schemaVersion') {
    Add-BridgeFailure 'WizardBridge must parse schemaVersion/type=result protocol.'
}

foreach ($bridge in @('Get-UiIsoMetadata.ps1', 'Start-UiBuildFromProfile.ps1')) {
    $text = Get-Content -LiteralPath (Join-Path $root "tools\ui-bridge\$bridge") -Raw
    if ($text -notmatch 'WinMint\.UiBridgeProtocol\.ps1' -or $text -notmatch 'Write-WinMintUiBridgeResult') {
        Add-BridgeFailure "$bridge must emit results through Write-WinMintUiBridgeResult."
    }
}

if ($failures.Count -gt 0) {
    Write-Host 'Wizard bridge protocol contract: FAIL'
    $failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}
Write-Host 'Wizard bridge protocol contract: OK'
exit 0
