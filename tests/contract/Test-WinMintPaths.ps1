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
New-Item -ItemType Directory -Force -Path $root | Out-Null
$logs = Join-Path $root 'logs'
@{
    root                  = $root
    logs                  = $logs
    payload               = Join-Path $root 'payload'
    media                 = Join-Path $root 'media'
    evidence              = Join-Path $root 'evidence.json'
    expectedEvidence      = Join-Path $root 'expected-evidence.json'
    failure               = Join-Path $root 'failure.json'
    applyStatus           = Join-Path $root 'apply-status.txt'
    stages                = Join-Path $root 'stages.json'
    installWim            = Join-Path $root 'install.wim'
    unattend              = Join-Path $root 'unattend.xml'
    digests               = Join-Path $logs 'digests.json'
    preparedMedia         = Join-Path $root 'prepared-media.json'
    incomingMediaPrefix   = 'media.incoming-'
    previousMediaPrefix   = 'media.previous-'
    hostPreparedMediaRoot = $expectCache
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'workspace.json') -Encoding utf8

$ws = Get-WinMintServicingWorkspace -Root $root
if ($ws.logs -ne $logs) { throw 'logs leaf' }
if ($ws.evidence -ne (Join-Path $root 'evidence.json')) { throw 'evidence leaf' }
if ($ws.incomingMediaPrefix -ne 'media.incoming-') { throw 'incoming prefix' }
if ($ws.previousMediaPrefix -ne 'media.previous-') { throw 'previous prefix' }

Remove-Item -LiteralPath $root -Recurse -Force
Write-Output 'Test-WinMintPaths ok'
exit 0
