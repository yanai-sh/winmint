#Requires -Version 7.3

function Invoke-WinMintAgentProfileBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    if ($null -eq $AgentProfile) {
        return [pscustomobject]@{
            Id      = 'profiles'
            Status  = 'failed'
            Message = 'Profile is null. BuildProfile.json was not loaded; the FirstLogon agent has nothing to apply.'
        }
    }

    $problems = [System.Collections.Generic.List[string]]::new()
    $propertyNames = @($AgentProfile.PSObject.Properties.Name)

    function Test-AgentProfileField {
        param(
            [string]$Name,
            [string[]]$Names,
            [object]$CandidateProfile,
            [System.Collections.Generic.List[string]]$Sink,
            [ValidateSet('String', 'Array', 'Boolean')][string]$Kind
        )
        if ($Names -notcontains $Name) {
            $Sink.Add("'$Name' is missing")
            return
        }
        $value = $CandidateProfile.$Name
        switch ($Kind) {
            'String' {
                if ($null -eq $value -or $value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$value)) {
                    $Sink.Add("'$Name' must be a non-empty string")
                }
            }
            'Array' {
                $isArray = ($value -is [System.Array]) -or ($value -is [System.Collections.IList] -and -not ($value -is [string]))
                if (-not $isArray) {
                    $Sink.Add("'$Name' must be an array (empty array is OK)")
                }
            }
            'Boolean' {
                if ($value -isnot [bool]) {
                    $Sink.Add("'$Name' must be a boolean (true/false)")
                }
            }
        }
    }

    Test-AgentProfileField -Name 'profile' -Names $propertyNames -CandidateProfile $AgentProfile -Sink $problems -Kind 'String'
    Test-AgentProfileField -Name 'editors' -Names $propertyNames -CandidateProfile $AgentProfile -Sink $problems -Kind 'Array'

    if ($propertyNames -contains 'modules') {
        $moduleNames = @($AgentProfile.modules.PSObject.Properties.Name)
        foreach ($requiredModule in @('packageManagers', 'wsl', 'flowEverything', 'raycast', 'liveInstallAudit', 'shell', 'windhawk')) {
            if ($moduleNames -notcontains $requiredModule) {
                $problems.Add("'modules.$requiredModule' is missing")
            }
        }
    }
    else {
        $problems.Add("'modules' is missing")
    }

    if ($problems.Count -gt 0) {
        return [pscustomobject]@{
            Id      = 'profiles'
            Status  = 'failed'
            Message = "Profile validation failed: $([string]::Join('; ', $problems))."
        }
    }

    $editorCount = @($AgentProfile.editors).Count
    $distroCount = @($AgentProfile.modules.wsl.distros).Count
    return [pscustomobject]@{
        Id      = 'profiles'
        Status  = 'ok'
        Message = "Profile validated: $($AgentProfile.profile); editors=$editorCount; distros=$distroCount"
    }
}
