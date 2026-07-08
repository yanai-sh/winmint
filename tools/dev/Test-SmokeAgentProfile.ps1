#Requires -Version 7.6
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $root 'src\runtime\modules\WinMint.Engine\WinMint.Engine.psd1') -Force
. (Join-Path $root 'src\runtime\firstlogon\Modules\Profiles.ps1')

$buildProfile = Get-Content (Join-Path $root 'tests\profiles\hyper-v-smoke-arm64.json') -Raw | ConvertFrom-Json
$plan = New-WinMintInstallPlan -BuildProfile $buildProfile
$agentProfile = $plan.AgentProfile

$asHashtable = Invoke-WinMintAgentProfileBootstrap -AgentProfile $agentProfile -State @{}
if ($asHashtable.Status -ne 'ok') {
    throw "hashtable validation failed: $($asHashtable.Message)"
}
Write-Output "hashtable OK: $($asHashtable.Message)"

$tmp = Join-Path $env:TEMP 'winmint-smoke-agent-profile.json'
$agentProfile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tmp -Encoding utf8
$loaded = Get-Content -LiteralPath $tmp -Raw -Encoding utf8 | ConvertFrom-Json
$asJson = Invoke-WinMintAgentProfileBootstrap -AgentProfile $loaded -State @{}
if ($asJson.Status -ne 'ok') {
    throw "json validation failed: $($asJson.Message)"
}
Write-Output "json OK: $($asJson.Message)"
Write-Output 'PASS'
