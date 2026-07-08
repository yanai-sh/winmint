#Requires -Version 7.6

function Get-WinMintAgentProfilePropertyNames {
    param([Parameter(Mandatory)][object]$AgentProfile)

    if ($AgentProfile -is [System.Collections.IDictionary]) {
        return @($AgentProfile.Keys | ForEach-Object { [string]$_ })
    }
    return @($AgentProfile.PSObject.Properties.Name)
}

function Get-WinMintAgentProfilePropertyValue {
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][string]$Name
    )

    $value = $null
    $found = $false
    if ($AgentProfile -is [System.Collections.IDictionary]) {
        if (@($AgentProfile.Keys | ForEach-Object { [string]$_ }) -contains $Name) {
            $value = $AgentProfile[$Name]
            $found = $true
        }
    }
    else {
        $property = $AgentProfile.PSObject.Properties[$Name]
        if ($property) {
            $value = $property.Value
            $found = $true
        }
    }
    if (-not $found) { return $null }
    # Empty arrays must stay arrays. Comma-unary only for those — wrapping a
    # scalar/string would make 'profile' look like Object[] and fail string checks.
    if ($value -is [System.Array] -or ($value -is [System.Collections.IList] -and -not ($value -is [string]))) {
        return , $value
    }
    return $value
}

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
            Message = 'Profile is null. WinMintAgentProfile.json was not loaded; the FirstLogon agent has nothing to apply.'
        }
    }

    $problems = [System.Collections.Generic.List[string]]::new()
    $propertyNames = @(Get-WinMintAgentProfilePropertyNames -AgentProfile $AgentProfile)

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
        $value = Get-WinMintAgentProfilePropertyValue -AgentProfile $CandidateProfile -Name $Name
        switch ($Kind) {
            'String' {
                if ($null -eq $value -or $value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$value)) {
                    $Sink.Add("'$Name' must be a non-empty string")
                }
            }
            'Array' {
                # $null after empty-array unwrap is treated as empty OK when the key exists.
                $isArray = ($null -eq $value) -or ($value -is [System.Array]) -or ($value -is [System.Collections.IList] -and -not ($value -is [string]))
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
    Test-AgentProfileField -Name 'browsers' -Names $propertyNames -CandidateProfile $AgentProfile -Sink $problems -Kind 'Array'

    $modules = Get-WinMintAgentProfilePropertyValue -AgentProfile $AgentProfile -Name 'modules'
    if ($null -ne $modules) {
        $moduleNames = @(Get-WinMintAgentProfilePropertyNames -AgentProfile $modules)
        foreach ($requiredModule in @('packageManagers', 'wsl', 'browsers', 'raycast', 'launcherKey', 'liveInstallAudit', 'shell', 'windhawk')) {
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

    $editors = Get-WinMintAgentProfilePropertyValue -AgentProfile $AgentProfile -Name 'editors'
    $browsers = Get-WinMintAgentProfilePropertyValue -AgentProfile $AgentProfile -Name 'browsers'
    $profileName = [string](Get-WinMintAgentProfilePropertyValue -AgentProfile $AgentProfile -Name 'profile')
    $wsl = if ($null -ne $modules) { Get-WinMintAgentProfilePropertyValue -AgentProfile $modules -Name 'wsl' } else { $null }
    $distros = if ($null -ne $wsl) { Get-WinMintAgentProfilePropertyValue -AgentProfile $wsl -Name 'distros' } else { @() }
    $editorCount = @($editors).Count
    $browserCount = @($browsers).Count
    $distroCount = @($distros).Count
    return [pscustomobject]@{
        Id      = 'profiles'
        Status  = 'ok'
        Message = "Profile validated: $profileName; editors=$editorCount; browsers=$browserCount; distros=$distroCount"
    }
}

