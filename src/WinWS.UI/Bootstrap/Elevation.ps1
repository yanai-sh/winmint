#Requires -Version 7.3

function Test-IsAdministrator {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WinWSPwshPath {
    # Use the actually-running pwsh.exe rather than a bare name. PATH may not
    # include pwsh on a fresh box, and resolving the running-process path is
    # always correct.
    return (Get-Process -Id $PID).Path
}

function Invoke-ElevateForBuild {
    param(
        [Parameter(Mandatory)][string]$ProfilePath,
        [switch]$DryRun,
        [switch]$ExportHostDrivers
    )
    $scriptPath = Join-Path $script:WinWSRepositoryRoot 'WinMint-UI.ps1'
    $pwshArgs   = @('-STA', '-NoProfile', '-File', "`"$scriptPath`"", '-SelfElevated',
                    '-ResumeProfile', "`"$ProfilePath`"")
    if ($DryRun)            { $pwshArgs += '-DryRun' }
    if ($ExportHostDrivers) { $pwshArgs += '-ExportHostDrivers' }
    if ($VerbosePreference -eq 'Continue') { $pwshArgs += '-Verbose' }
    # Always use pwsh.exe directly. wt.exe is an MSIX-packaged app whose
    # activator silently drops `-Verb RunAs`, leaving the inner pwsh
    # non-elevated even though the Terminal window may show "Administrator".
    Start-Process -FilePath (Get-WinWSPwshPath) -ArgumentList $pwshArgs -Verb RunAs
}

function Invoke-SelfElevate {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [switch]$DryRun,
        [switch]$ExportHostDrivers,
        [string]$ResumeProfile = '',
        [switch]$FixtureMode
    )
    Write-Information 'Elevating to Administrator…' -InformationAction Continue
    $pwshArgs = @('-STA', '-NoProfile', '-File', "`"$ScriptPath`"", '-SelfElevated')
    if ($DryRun)            { $pwshArgs += '-DryRun' }
    if ($ExportHostDrivers) { $pwshArgs += '-ExportHostDrivers' }
    if ($ResumeProfile)     { $pwshArgs += '-ResumeProfile'; $pwshArgs += "`"$ResumeProfile`"" }
    if ($FixtureMode)       { $pwshArgs += '-FixtureMode' }
    if ($VerbosePreference -eq 'Continue') { $pwshArgs += '-Verbose' }
    # See comment in Invoke-ElevateForBuild — wt.exe MSIX activation drops
    # `-Verb RunAs` silently. Always use pwsh.exe so the new process is
    # actually elevated when the user accepts UAC.
    $pwshExe = Get-WinWSPwshPath
    $waitForChild = $env:WINWS_UI_WAIT_FOR_ELEVATED_CHILD -eq '1'
    if ($waitForChild) {
        $proc = Start-Process -FilePath $pwshExe -ArgumentList $pwshArgs -Verb RunAs -PassThru -Wait
        if (Get-Command Stop-WinWSUiSessionTranscript -ErrorAction SilentlyContinue) {
            Stop-WinWSUiSessionTranscript
        } else {
            try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
        }
        if ($null -ne $proc) { exit $proc.ExitCode }
        exit 1
    }
    Start-Process -FilePath $pwshExe -ArgumentList $pwshArgs -Verb RunAs
}
