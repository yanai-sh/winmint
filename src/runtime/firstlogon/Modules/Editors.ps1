#Requires -Version 7.3

function Invoke-WinMintAgentEditorBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    $editors = @()
    if ($AgentProfile.PSObject.Properties['editors']) { $editors = @($AgentProfile.editors) }

    if ($editors.Count -eq 0) {
        return [pscustomobject]@{
            Id      = 'editors'
            Status  = 'skipped'
            Message = 'No editors selected.'
        }
    }

    if (-not $manifest -or -not $manifest.PSObject.Properties['tools']) {
        return [pscustomobject]@{
            Id      = 'editors'
            Status  = 'failed'
            Message = 'packages.json does not contain a tools manifest.'
        }
    }

    $selection = Invoke-WinMintAgentManifestToolSelection -SelectionId 'editors' -SelectedIds $editors -State $State -StateKeyPrefix 'editor'
    $failedEditors = @($selection.FailedIds)

    if ($failedEditors.Count -gt 0) {
        return [pscustomobject]@{
            Id      = 'editors'
            Status  = 'failed'
            Message = "Failed editors: $($failedEditors -join ', ')"
        }
    }

    [pscustomobject]@{
        Id      = 'editors'
        Status  = 'ok'
        Message = "Editors installed: $($editors -join ', ')"
    }
}
