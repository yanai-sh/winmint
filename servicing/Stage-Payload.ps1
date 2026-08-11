#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
# Stage Supervisor, SetupComplete.cmd, provisioning bundle into the offline image.
$payloadDir = $Parameters['payloadDir']
$mountDir = $Parameters['mountDir']
if ([string]::IsNullOrWhiteSpace($payloadDir)) { throw 'payloadDir required' }
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }

$guestWinMint = Join-Path $mountDir 'Windows\WinMint'
$guestScripts = Join-Path $mountDir 'Windows\Setup\Scripts'
New-Item -ItemType Directory -Force -Path $guestWinMint, $guestScripts | Out-Null

Copy-Item -LiteralPath (Join-Path $payloadDir 'Supervisor.exe') -Destination (Join-Path $guestWinMint 'Supervisor.exe') -Force
Copy-Item -LiteralPath (Join-Path $payloadDir 'SetupComplete.cmd') -Destination (Join-Path $guestScripts 'SetupComplete.cmd') -Force
Copy-Item -LiteralPath (Join-Path $payloadDir 'bundle.json') -Destination (Join-Path $guestWinMint 'bundle.json') -Force
Copy-Item -LiteralPath (Join-Path $payloadDir 'jobs.json') -Destination (Join-Path $guestWinMint 'jobs.json') -Force
$wingetImport = Join-Path $payloadDir 'winget-import.json'
if (Test-Path -LiteralPath $wingetImport) {
    Copy-Item -LiteralPath $wingetImport -Destination (Join-Path $guestWinMint 'winget-import.json') -Force
}

$shellSkel = Join-Path $payloadDir 'shell-skel'
if (Test-Path -LiteralPath $shellSkel) {
    $guestSkel = Join-Path $guestWinMint 'shell-skel'
    New-Item -ItemType Directory -Force -Path $guestSkel | Out-Null
    Copy-Item -LiteralPath (Join-Path $shellSkel '*') -Destination $guestSkel -Recurse -Force
}

Write-Output "StagePayload ok"
exit 0
