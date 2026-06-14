#Requires -Version 7.3

function Invoke-WinMintAgentBrowsersBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    $browsers = @()
    if ($AgentProfile.PSObject.Properties['browsers']) { $browsers = @($AgentProfile.browsers) }

    if ($browsers.Count -eq 0) {
        return [pscustomobject]@{
            Id      = 'browsers'
            Status  = 'skipped'
            Message = 'No browsers selected.'
        }
    }

    $keepEdge = $browsers -contains 'edge'
    $installBrowsers = @($browsers | Where-Object { $_ -ne 'edge' })
    if ($installBrowsers.Count -eq 0 -and $keepEdge) {
        return [pscustomobject]@{
            Id      = 'browsers'
            Status  = 'ok'
            Message = 'Edge browser kept installed; no browser packages selected.'
        }
    }

    if (-not $manifest -or -not $manifest.PSObject.Properties['tools']) {
        return [pscustomobject]@{
            Id      = 'browsers'
            Status  = 'failed'
            Message = 'packages.json does not contain a tools manifest.'
        }
    }

    $failedBrowsers = [System.Collections.Generic.List[string]]::new()
    foreach ($browserId in $installBrowsers) {
        $property = $manifest.tools.PSObject.Properties[$browserId]
        $tool = if ($property) { $property.Value } else { $null }
        if (-not $tool) {
            $State.steps["browser:$browserId"] = @{
                status = 'failed'
                updatedAt = (Get-Date -Format o)
                error = "Unknown browser id: $browserId"
            }
            Write-AgentLog "Unknown browser id in profile: $browserId"
            Save-AgentState -State $State
            $failedBrowsers.Add($browserId) | Out-Null
            continue
        }

        Install-AgentTool -Tool $tool -State $State
        Save-AgentState -State $State

        $key = "tool:$([string]$tool.id)"
        $status = if ($State.steps.ContainsKey($key)) { [string]$State.steps[$key].status } else { '' }
        if ($status -ne 'ok' -and $status -ne 'skipped') {
            $failedBrowsers.Add($browserId) | Out-Null
        }
    }

    if ($failedBrowsers.Count -gt 0) {
        return [pscustomobject]@{
            Id      = 'browsers'
            Status  = 'failed'
            Message = "Failed browsers: $($failedBrowsers -join ', ')"
        }
    }

    $message = if ($keepEdge) {
        "Browsers installed: $($installBrowsers -join ', '); Edge kept installed."
    }
    else {
        "Browsers installed: $($installBrowsers -join ', ')."
    }

    [pscustomobject]@{
        Id      = 'browsers'
        Status  = 'ok'
        Message = $message
    }
}
