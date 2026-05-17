#Requires -Version 7.3

<#
.SYNOPSIS
    WinWS UI host session: runspace pin + application context (single source of truth).
.NOTES
    Dot-sourced scripts each have their own script scope — keep wizard host data on AppContext, not ad hoc $script:.
    Register once from Start-WinWSUIApp. Long-lived UI workers: IsoVerification (mount + thread job),
    Build (message queue + thread job + dispatcher pump). Clear-WinWSUiAppContext stops the build pump first.
#>

$script:WinWSUiPinnedHostRunspace = $null
$script:WinWSUiAppContext = $null

#region Host runspace (WPF scriptblocks)

function Set-WinWSUiHostRunspacePin {
    param(
        [AllowNull()]
        [System.Management.Automation.Runspaces.Runspace]$Runspace
    )
    $script:WinWSUiPinnedHostRunspace = $Runspace
}

function Get-WinWSUiHostRunspacePin {
    if ($null -ne $script:WinWSUiPinnedHostRunspace) {
        return $script:WinWSUiPinnedHostRunspace
    }
    return [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
}

#endregion

#region Application context

function Register-WinWSUiAppContext {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][string]$UiRoot,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [bool]$DryRun,
        [bool]$FixtureMode,
        [string]$ResumeProfile = ''
    )
    $iso = [pscustomobject]@{
        Job            = $null
        DispatcherPoll = $null
        StartedAt      = $null
    }
    $build = [pscustomobject]@{
        Messages       = $null
        Job            = $null
        DispatcherPump = $null
    }
    $script:WinWSUiAppContext = [pscustomobject]@{
        State                   = $State
        Window                  = $Window
        UiRoot                  = $UiRoot
        RepositoryRoot          = $RepositoryRoot
        DryRun                  = [bool]$DryRun
        FixtureMode             = [bool]$FixtureMode
        ResumeProfile           = [string]$ResumeProfile
        ShellLastStage          = $null
        ShellTransitionPrimed   = $false
        ClipboardIsoRegistered  = $false
        IsoVerification         = $iso
        Build                   = $build
        ProcessExitCode         = 0
    }
}

function Get-WinWSUiAppContext {
    if ($null -eq $script:WinWSUiAppContext) {
        throw 'WinWS UI application context is not registered.'
    }
    return $script:WinWSUiAppContext
}

function Get-WinWSUiAppContextOptional {
    return $script:WinWSUiAppContext
}

function Clear-WinWSUiAppContext {
    if (Get-Command Stop-WinWSUiBuildPump -ErrorAction SilentlyContinue) {
        Stop-WinWSUiBuildPump
    }
    if (Get-Command Clear-WinWSUiRoutedBindings -ErrorAction SilentlyContinue) {
        Clear-WinWSUiRoutedBindings
    }
    $script:WinWSUiAppContext = $null
}

function Get-WinWSUiAppProcessExitCode {
    $c = Get-WinWSUiAppContextOptional
    if ($null -eq $c) { return 0 }
    return [int]$c.ProcessExitCode
}

function Get-WinWSUiIsoVerificationSlot {
    $c = Get-WinWSUiAppContextOptional
    if ($null -eq $c) { return $null }
    return $c.IsoVerification
}

function Get-WinWSUiBuildSlot {
    $c = Get-WinWSUiAppContextOptional
    if ($null -eq $c) { return $null }
    return $c.Build
}

function Get-WinWSUiAppStateOptional {
    $c = Get-WinWSUiAppContextOptional
    if ($null -eq $c) { return $null }
    return $c.State
}

function Get-WinWSUiAppWindowOptional {
    $c = Get-WinWSUiAppContextOptional
    if ($null -eq $c) { return $null }
    return $c.Window
}

function Test-WinWSUiAppDryRun {
    $c = Get-WinWSUiAppContextOptional
    return [bool]($null -ne $c -and $c.DryRun)
}

function Test-WinWSUiAppFixtureMode {
    $c = Get-WinWSUiAppContextOptional
    return [bool]($null -ne $c -and $c.FixtureMode)
}

#endregion
