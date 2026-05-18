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

    $failedEditors = [System.Collections.Generic.List[string]]::new()
    foreach ($editorId in $editors) {
        $property = $manifest.tools.PSObject.Properties[$editorId]
        $tool = if ($property) { $property.Value } else { $null }
        if (-not $tool) {
            $State.steps["editor:$editorId"] = @{
                status = 'failed'
                updatedAt = (Get-Date -Format o)
                error = "Unknown editor id: $editorId"
            }
            Write-AgentLog "Unknown editor id in profile: $editorId"
            Save-AgentState -State $State
            $failedEditors.Add($editorId) | Out-Null
            continue
        }

        Install-AgentTool -Tool $tool -State $State
        Save-AgentState -State $State

        $key = "tool:$($tool.id)"
        $status = if ($State.steps.ContainsKey($key)) { [string]$State.steps[$key].status } else { '' }
        if ($status -ne 'ok' -and $status -ne 'skipped') {
            $failedEditors.Add($editorId) | Out-Null
        }
    }

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
