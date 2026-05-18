#Requires -Version 7.3

<#
.SYNOPSIS
    WinMint UI host session: runspace pin + application context (single source of truth).
.NOTES
    Dot-sourced scripts each have their own script scope — keep wizard host data on AppContext, not ad hoc $script:.
    Register once from Start-WinMintUIApp. Long-lived UI workers: IsoVerification (mount + thread job),
    Build (message queue + thread job + dispatcher pump). Clear-WinMintUiAppContext stops the build pump first.
#>

$script:WinMintUiPinnedHostRunspace = $null
$script:WinMintUiAppContext = $null

#region Host runspace (WPF scriptblocks)

function Set-WinMintUiHostRunspacePin {
    param(
        [AllowNull()]
        [System.Management.Automation.Runspaces.Runspace]$Runspace
    )
    $script:WinMintUiPinnedHostRunspace = $Runspace
}

function Get-WinMintUiHostRunspacePin {
    if ($null -ne $script:WinMintUiPinnedHostRunspace) {
        return $script:WinMintUiPinnedHostRunspace
    }
    return [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
}

#endregion

#region Application context

function Register-WinMintUiAppContext {
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
    $script:WinMintUiAppContext = [pscustomobject]@{
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

function Get-WinMintUiAppContext {
    if ($null -eq $script:WinMintUiAppContext) {
        throw 'WinMint UI application context is not registered.'
    }
    return $script:WinMintUiAppContext
}

function Get-WinMintUiAppContextOptional {
    return $script:WinMintUiAppContext
}

function Clear-WinMintUiAppContext {
    if (Get-Command Stop-WinMintUiBuildPump -ErrorAction SilentlyContinue) {
        Stop-WinMintUiBuildPump
    }
    if (Get-Command Clear-WinMintUiRoutedBindings -ErrorAction SilentlyContinue) {
        Clear-WinMintUiRoutedBindings
    }
    $script:WinMintUiAppContext = $null
}

function Get-WinMintUiAppProcessExitCode {
    $c = Get-WinMintUiAppContextOptional
    if ($null -eq $c) { return 0 }
    return [int]$c.ProcessExitCode
}

function Get-WinMintUiIsoVerificationSlot {
    $c = Get-WinMintUiAppContextOptional
    if ($null -eq $c) { return $null }
    return $c.IsoVerification
}

function Get-WinMintUiBuildSlot {
    $c = Get-WinMintUiAppContextOptional
    if ($null -eq $c) { return $null }
    return $c.Build
}

function Get-WinMintUiAppStateOptional {
    $c = Get-WinMintUiAppContextOptional
    if ($null -eq $c) { return $null }
    return $c.State
}

function Get-WinMintUiAppWindowOptional {
    $c = Get-WinMintUiAppContextOptional
    if ($null -eq $c) { return $null }
    return $c.Window
}

function Test-WinMintUiAppDryRun {
    $c = Get-WinMintUiAppContextOptional
    return [bool]($null -ne $c -and $c.DryRun)
}

function Test-WinMintUiAppFixtureMode {
    $c = Get-WinMintUiAppContextOptional
    return [bool]($null -ne $c -and $c.FixtureMode)
}

#endregion
