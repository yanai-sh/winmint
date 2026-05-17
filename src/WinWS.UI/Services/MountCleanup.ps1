#Requires -Version 7.3

# Minimal logging used by src\WinWS\Private\Media.ps1 when the full engine is not loaded.
if (-not (Get-Command Log -ErrorAction SilentlyContinue)) {
    function Log {
        param([Parameter(Mandatory)][string]$Message)
        Write-Verbose "[WinWS] $Message"
    }
    function LogVerbose {
        param([Parameter(Mandatory)][string]$Message)
        Write-Verbose $Message
    }
    function LogWarn {
        param([Parameter(Mandatory)][string]$Message)
        Write-Warning $Message
    }
}

function Get-WinWSUiIsoMountJournalFile {
    $dir = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'WinWS'
    return (Join-Path $dir 'ui_iso_verify_mount.txt')
}

function Set-WinWSUiIsoMountJournalPath {
    param([Parameter(Mandatory)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $journal = Get-WinWSUiIsoMountJournalFile
    Set-WinWSUtf8NoBomTextFile -LiteralPath $journal -Content $full
}

function Clear-WinWSUiIsoMountJournal {
    $journal = Get-WinWSUiIsoMountJournalFile
    if (Test-Path -LiteralPath $journal) {
        Remove-Item -LiteralPath $journal -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-WinWSUiDismountJournalIsoMounts {
    # End Task / crash: next session dismounts the ISO path we were verifying.
    # Caller must have dot-sourced Media.ps1 so Dismount-Win11IsoDiskImageLiteral exists.
    $journal = Get-WinWSUiIsoMountJournalFile
    if (-not (Test-Path -LiteralPath $journal)) { return }
    $lines = @(
        try {
            @(Get-Content -LiteralPath $journal -ErrorAction Stop | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
        catch {
            @()
        }
    )
    $uniq = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in $lines) {
        if (-not [string]::IsNullOrWhiteSpace($line)) { [void]$uniq.Add($line) }
    }
    foreach ($line in $uniq) {
        if (Get-Command Dismount-Win11IsoDiskImageLiteral -ErrorAction SilentlyContinue) {
            try {
                Dismount-Win11IsoDiskImageLiteral -LiteralImagePath $line
            }
            catch {
                Write-Verbose "Journal ISO dismount '$line': $($_.Exception.Message)"
            }
        }
    }
    Clear-WinWSUiIsoMountJournal
}

function Initialize-WinWSUiMountHygiene {
    <#
    .SYNOPSIS
        Dismounts orphaned WinWS ISO/WIM artifacts under %TEMP% before the UI runs DISM again.
    .NOTES
        Dismount-WindowsImage can hang indefinitely on a corrupted or locked mount. Cleanup runs
        in a worker runspace with a hard timeout so the wizard can always open.
    #>
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [int]$TimeoutSec = 120,
        # UI startup: do not block the STA thread on DISM; close handler still uses synchronous + timeout.
        [switch]$Async
    )
    $runtime = Join-Path $RepositoryRoot 'src\WinWS\Private\Runtime.ps1'
    $media = Join-Path $RepositoryRoot 'src\WinWS\Private\Media.ps1'
    $self = Join-Path $RepositoryRoot 'src\WinWS.UI\Services\MountCleanup.ps1'
    if (-not (Test-Path -LiteralPath $runtime) -or -not (Test-Path -LiteralPath $media)) {
        Write-Verbose 'Initialize-WinWSUiMountHygiene: engine Media/Runtime scripts not found; skip.'
        return
    }

    $cleanupBlock = {
        param([string]$RepoRoot, [string]$ThisFile)
        $ProgressPreference = 'SilentlyContinue'
        $InformationPreference = 'SilentlyContinue'
        $runtimeI = Join-Path $RepoRoot 'src\WinWS\Private\Runtime.ps1'
        $mediaI = Join-Path $RepoRoot 'src\WinWS\Private\Media.ps1'
        . $runtimeI
        . $mediaI
        if (Test-Path -LiteralPath $ThisFile) { . $ThisFile }
        try { Import-Module Dism -ErrorAction SilentlyContinue | Out-Null } catch {}
        try { Import-Module Storage -ErrorAction SilentlyContinue | Out-Null } catch {}
        try { Invoke-WinWSUiDismountJournalIsoMounts } catch {}
        try { Invoke-Win11IsoStartupCleanup } catch {}
    }

    $job = $null
    try {
        $job = Start-ThreadJob -Name 'WinWSMountHygiene' -ScriptBlock $cleanupBlock -ArgumentList $RepositoryRoot, $self
        if ($Async) {
            return
        }
        $done = Wait-Job -Job $job -Timeout $TimeoutSec
        if (-not $done) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Write-Warning (
                "WinWS UI: mount cleanup exceeded ${TimeoutSec}s (likely a stuck DISM mount). Opening the wizard anyway. " +
                "If ISO verification fails, run an elevated prompt: dism /cleanup-wim"
            )
        }
        $null = Receive-Job -Job $job -ErrorAction SilentlyContinue
    }
    catch {
        Write-Verbose "Initialize-WinWSUiMountHygiene job: $($_.Exception.Message)"
    }
    finally {
        if (-not $Async -and $null -ne $job) {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    }
}

function Register-WinWSUiMountHygieneWindowHooks {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [System.Management.Automation.Runspaces.Runspace]$HostRunspace = $null
    )
    if ($null -eq $HostRunspace) {
        $HostRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
    }
    Set-WinWSUiHostRunspacePin -Runspace $HostRunspace
    if ([bool](Get-Variable -Name WinWSUiMountHygieneHooksRegistered -Scope Script -ValueOnly -ErrorAction SilentlyContinue)) {
        return
    }
    $script:WinWSUiMountHygieneHooksRegistered = $true
    $Window.Add_Closing({
        param($cleanupSender, $e)
        [void]$cleanupSender
        try {
            $hr = Get-WinWSUiHostRunspacePin
            $closingWork = {
                if (Get-Command Stop-WinWSUiIsoVerification -ErrorAction SilentlyContinue) {
                    Stop-WinWSUiIsoVerification
                }
                $repo = $null
                try {
                    $ctx = Get-WinWSUiAppContextOptional
                    if ($null -ne $ctx) { $repo = [string]$ctx.RepositoryRoot }
                    if ([string]::IsNullOrWhiteSpace($repo)) { $repo = [string]$script:WinWSRepositoryRoot }
                } catch {}
                if (-not [string]::IsNullOrWhiteSpace($repo) -and (Get-Command Initialize-WinWSUiMountHygiene -ErrorAction SilentlyContinue)) {
                    Initialize-WinWSUiMountHygiene -RepositoryRoot $repo
                }
            }
            if (Get-Command Invoke-WinWSUiWithHostRunspace -ErrorAction SilentlyContinue) {
                Invoke-WinWSUiWithHostRunspace -HostRunspace $hr -Script $closingWork
            } else {
                & $closingWork
            }
        }
        catch {
            Write-Verbose "Mount hygiene on window close: $($_.Exception.Message)"
        }
    })
}
