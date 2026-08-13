#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools\host\WinMintPaths.ps1')
. (Join-Path $repo 'servicing\Get-WinMintServicingWorkspace.ps1')

$gate = Get-WinMintGateBWorkDirectory
$expectGate = Join-Path $env:LOCALAPPDATA 'WinMint\work\gate-b'
if ($gate -cne $expectGate) { throw "Gate B path mismatch: $gate" }

$cache = Get-WinMintHostPreparedMediaRoot
$expectCache = Join-Path $env:ProgramData 'WinMint\Servicing\media-cache'
if ($cache -cne $expectCache) { throw "Prepared media root mismatch: $cache" }

$root = Join-Path $env:TEMP ('winmint-ws-' + [guid]::NewGuid().ToString('N'))
$ws = Get-WinMintServicingWorkspace -Root $root
if ($ws.logs -ne (Join-Path $root 'logs')) { throw 'logs leaf' }
if ($ws.evidence -ne (Join-Path $root 'evidence.json')) { throw 'evidence leaf' }
if ($ws.incomingMediaPrefix -ne 'media.incoming-') { throw 'incoming prefix' }
if ($ws.previousMediaPrefix -ne 'media.previous-') { throw 'previous prefix' }

Write-Output 'Test-WinMintPaths ok'
exit 0
