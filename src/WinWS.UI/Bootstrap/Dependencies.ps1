#Requires -Version 7.3

if (-not (Get-Command Write-WinWSUiLog -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\Logging.ps1"
}

function Invoke-WinWSUiWithHostRunspace {
    <#
    .SYNOPSIS
        Runs a scriptblock with the engine runspace pinned for the current thread.
    .NOTES
        WPF (including WPF.UI FluentWindow) can raise Activated/Closing on a path where
        PowerShell's thread-local DefaultRunspace is unset, which throws
        "There is no Runspace available to run scripts in this thread" for scriptblock handlers.
        Callers pass the engine runspace explicitly — do not stash it in $global: so
        `irm ... | iex` and nested invocations do not pollute the user's session.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.Runspace]$HostRunspace,
        [Parameter(Mandatory)]
        [scriptblock]$Script
    )
    $prev = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
    try {
        [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace = $HostRunspace
        & $Script
    }
    finally {
        [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace = $prev
    }
}

# .NET 10 breaking change: DynamicResource optimization crashes under elevation when WPF
# loads the Classic theme (different resource key types than Aero2). Must be set before
# PresentationFramework loads. https://learn.microsoft.com/dotnet/core/compatibility/wpf/10.0/dynamicresource-crash
[System.AppContext]::SetSwitch('Switch.System.Windows.Controls.DisableDynamicResourceOptimization', $true)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Write-WinWSUiLog 'Loaded WPF assemblies.'

if (-not (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)) {
    Import-Module ThreadJob -ErrorAction SilentlyContinue
    if (-not (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)) {
        Install-Module -Name ThreadJob -Scope CurrentUser -Force -AllowClobber
        Import-Module ThreadJob
    }
}
Write-WinWSUiLog 'ThreadJob available.'
