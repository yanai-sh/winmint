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

    $selection = Invoke-WinMintAgentManifestToolSelection -SelectionId 'browsers' -SelectedIds $browsers -State $State -StateKeyPrefix 'browser' -ExcludedIds @('edge')
    $failedBrowsers = @($selection.FailedIds)

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
