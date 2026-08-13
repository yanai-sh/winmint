#requires -Version 7.6
Set-StrictMode -Version Latest

function Get-WinMintServicingWorkspace {
    param([Parameter(Mandatory)] [string] $Root)
    $manifest = Join-Path $Root 'workspace.json'
    if (Test-Path -LiteralPath $manifest -PathType Leaf) {
        return Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    }
    $logs = Join-Path $Root 'logs'
    return [pscustomobject]@{
        root                   = $Root
        logs                   = $logs
        payload                = Join-Path $Root 'payload'
        media                  = Join-Path $Root 'media'
        evidence               = Join-Path $Root 'evidence.json'
        expectedEvidence       = Join-Path $Root 'expected-evidence.json'
        failure                = Join-Path $Root 'failure.json'
        applyStatus            = Join-Path $Root 'apply-status.txt'
        stages                 = Join-Path $Root 'stages.json'
        installWim             = Join-Path $Root 'install.wim'
        unattend               = Join-Path $Root 'unattend.xml'
        digests                = Join-Path $logs 'digests.json'
        preparedMedia          = Join-Path $Root 'prepared-media.json'
        incomingMediaPrefix    = 'media.incoming-'
        previousMediaPrefix    = 'media.previous-'
        hostPreparedMediaRoot  = Join-Path $env:ProgramData 'WinMint\Servicing\media-cache'
    }
}
