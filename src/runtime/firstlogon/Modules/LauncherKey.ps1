#Requires -Version 7.6

function Get-WinMintAgentLauncherKeyModule {
    param([Parameter(Mandatory)][object]$AgentProfile)

    if (-not $AgentProfile.PSObject.Properties['modules']) { return $null }
    $module = $AgentProfile.modules.PSObject.Properties['launcherKey']
    if ($module) { return $module.Value }
    return $null
}

function Get-WinMintAgentLauncherKeyPlan {
    param([Parameter(Mandatory)][object]$AgentProfile)

    $module = Get-WinMintAgentLauncherKeyModule -AgentProfile $AgentProfile
    $target = if ($module -and $module.PSObject.Properties['target']) { [string]$module.target } else { '' }
    if ([string]::IsNullOrWhiteSpace($target)) {
        $target = 'Search'
    }

    $chord = if ($module -and $module.PSObject.Properties['chord'] -and -not [string]::IsNullOrWhiteSpace([string]$module.chord)) {
        [string]$module.chord
    } else {
        'Win+Shift+F23'
    }

    [pscustomobject]@{
        Target = $target
        Chord = $chord
    }
}

function Clear-WinMintAgentCopilotHardwareKeyAppPolicy {
    $keyPath = 'HKCU:\Software\Policies\Microsoft\Windows\CopilotKey'
    if (-not (Test-Path -LiteralPath $keyPath)) {
        return $false
    }

    foreach ($name in @('SetCopilotHardwareKey', 'EnterAppAumid')) {
        Remove-ItemProperty -LiteralPath $keyPath -Name $name -Force -ErrorAction SilentlyContinue
    }
    return $true
}

function Resolve-WinMintAgentStartAppAumid {
    param([Parameter(Mandatory)][string]$Name)

    try {
        $apps = @(Get-StartApps -ErrorAction Stop)
        $exact = $apps | Where-Object { [string]$_.Name -eq $Name } | Select-Object -First 1
        if ($exact -and -not [string]::IsNullOrWhiteSpace([string]$exact.AppID)) {
            return [string]$exact.AppID
        }
        $pattern = [regex]::Escape($Name)
        $match = $apps | Where-Object { [string]$_.Name -match $pattern -or [string]$_.AppID -match $pattern } | Select-Object -First 1
        if ($match -and -not [string]::IsNullOrWhiteSpace([string]$match.AppID)) {
            return [string]$match.AppID
        }
    }
    catch {
        Write-AgentLog "Start app AUMID lookup warning for ${Name}: $($_.Exception.Message)"
    }

    return ''
}

function Set-WinMintAgentCopilotHardwareKeyAppPolicy {
    param([Parameter(Mandatory)][string]$Aumid)

    $keyPath = 'HKCU:\Software\Policies\Microsoft\Windows\CopilotKey'
    $null = New-Item -Path $keyPath -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -LiteralPath $keyPath -Name 'EnterAppAumid' -Force -ErrorAction SilentlyContinue
    New-ItemProperty -LiteralPath $keyPath -Name 'SetCopilotHardwareKey' -PropertyType String -Value $Aumid -Force | Out-Null
    return $keyPath
}

function Invoke-WinMintAgentLauncherKeyBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    $plan = Get-WinMintAgentLauncherKeyPlan -AgentProfile $AgentProfile
    $result = [ordered]@{
        status = 'ok'
        updatedAt = (Get-Date -Format o)
        target = [string]$plan.Target
        chord = [string]$plan.Chord
        nativeSearchFallback = $false
        notes = @()
    }

    switch ([string]$plan.Target) {
        'Search' {
            $cleared = Clear-WinMintAgentCopilotHardwareKeyAppPolicy
            $result['nativeSearchFallback'] = $true
            $result['policyOverrideCleared'] = $cleared
            $result['notes'] = @('No launcher selected. Copilot app key policy was cleared so Windows can use the native Search target/fallback.')
        }
        default {
            $result['status'] = 'skipped'
            $result['notes'] = @("Unsupported launcher key target: $($plan.Target)")
        }
    }

    $State.steps['config:launcher-key'] = $result
    Save-AgentState -State $State
    $requiredStateSteps = @()
    if ([string]$result.status -eq 'ok') {
        $requiredStateSteps = @('config:launcher-key')
    }

    [pscustomobject]@{
        Id = 'launcher-key'
        Status = [string]$result.status
        Message = "Launcher key target: $($plan.Target)."
        RequiredStateSteps = $requiredStateSteps
    }
}

