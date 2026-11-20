#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'servicing\Enable-WinMintStayAwake.ps1')

Enable-WinMintStayAwake
Disable-WinMintStayAwake

$callers = @(
    'tools\apply\Invoke-HostApply.ps1',
    'tools\vm\Start-SmokeElevated.ps1',
    'servicing\Invoke-ServicingPlan.ps1',
    'servicing\Resolve-WinMintMount.ps1'
)
foreach ($relative in $callers) {
    $text = Get-Content -LiteralPath (Join-Path $repo $relative) -Raw -Encoding utf8
    if ($text -notmatch 'Enable-WinMintStayAwake') {
        throw "$relative must keep the host awake for a long Apply or discard"
    }
}

$plan = Get-Content -LiteralPath (Join-Path $repo 'servicing\Invoke-ServicingPlan.ps1') -Raw -Encoding utf8
$apply = Get-Content -LiteralPath (Join-Path $repo 'tools\apply\Invoke-HostApply.ps1') -Raw -Encoding utf8
$smoke = Get-Content -LiteralPath (Join-Path $repo 'tools\vm\Start-SmokeElevated.ps1') -Raw -Encoding utf8
foreach ($pair in @(
        @{ Name = 'Invoke-ServicingPlan'; Text = $plan },
        @{ Name = 'Invoke-HostApply'; Text = $apply },
        @{ Name = 'Start-SmokeElevated'; Text = $smoke }
    )) {
    if ($pair.Text -notmatch 'Disable-WinMintStayAwake') {
        throw "$($pair.Name) must release the stay-awake request"
    }
}

$mount = Get-Content -LiteralPath (Join-Path $repo 'servicing\Resolve-WinMintMount.ps1') -Raw -Encoding utf8
if ($mount -notmatch 'Write-Host "discard \$kind \$mountDir"') {
    throw 'stale discard must name the mount before DISM starts'
}

Write-Output 'Test-WinMintStayAwake ok'
exit 0
