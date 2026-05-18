#Requires -Version 7.3

# Minimal logging used by src\WinMint\Private\Media.ps1 when the full engine is not loaded.
if (-not (Get-Command Log -ErrorAction SilentlyContinue)) {
    function Log {
        param([Parameter(Mandatory)][string]$Message)
        Write-Verbose "[WinMint] $Message"
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

function Get-WinMintUiIsoMountJournalFile {
    $dir = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'WinMint'
    return (Join-Path $dir 'ui_iso_verify_mount.txt')
}

function Set-WinMintUiIsoMountJournalPath {
    param([Parameter(Mandatory)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $journal = Get-WinMintUiIsoMountJournalFile
    Set-WinMintUtf8NoBomTextFile -LiteralPath $journal -Content $full
}

function Clear-WinMintUiIsoMountJournal {
    $journal = Get-WinMintUiIsoMountJournalFile
    if (Test-Path -LiteralPath $journal) {
        Remove-Item -LiteralPath $journal -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-WinMintUiDismountJournalIsoMounts {
    # End Task / crash: next session dismounts the ISO path we were verifying.
    # Caller must have dot-sourced Media.ps1 so Dismount-Win11IsoDiskImageLiteral exists.
    $journal = Get-WinMintUiIsoMountJournalFile
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
    Clear-WinMintUiIsoMountJournal
}

function Initialize-WinMintUiMountHygiene {
    <#
    .SYNOPSIS
        Dismounts orphaned WinMint ISO/WIM artifacts under %TEMP% before the UI runs DISM again.
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
    $script:WinMintRepositoryRoot = $RepositoryRoot
    $core = Join-Path $RepositoryRoot 'src\WinMint\Core.ps1'
    if (Test-Path -LiteralPath $core -PathType Leaf) {
        . $core
    }
    $runtime = Get-WinMintPath -Name EngineRoot -ChildPath 'Private\Runtime.ps1'
    $media = Get-WinMintPath -Name EngineRoot -ChildPath 'Private\Media.ps1'
    $self = Get-WinMintPath -Name LegacyWpfApp -ChildPath 'Services\MountCleanup.ps1'
    if (-not (Test-Path -LiteralPath $runtime) -or -not (Test-Path -LiteralPath $media)) {
        Write-Verbose 'Initialize-WinMintUiMountHygiene: engine Media/Runtime scripts not found; skip.'
        return
    }

    $cleanupBlock = {
        param([string]$RuntimePath, [string]$MediaPath, [string]$ThisFile)
        $ProgressPreference = 'SilentlyContinue'
        $InformationPreference = 'SilentlyContinue'
        . $RuntimePath
        . $MediaPath
        if (Test-Path -LiteralPath $ThisFile) { . $ThisFile }
        try { Import-Module Dism -ErrorAction SilentlyContinue | Out-Null } catch {}
        try { Import-Module Storage -ErrorAction SilentlyContinue | Out-Null } catch {}
        try { Invoke-WinMintUiDismountJournalIsoMounts } catch {}
        try { Invoke-Win11IsoStartupCleanup } catch {}
    }

    $job = $null
    try {
        $job = Start-ThreadJob -Name 'WinMintMountHygiene' -ScriptBlock $cleanupBlock -ArgumentList $runtime, $media, $self
        if ($Async) {
            return
        }
        $done = Wait-Job -Job $job -Timeout $TimeoutSec
        if (-not $done) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Write-Warning (
                "WinMint UI: mount cleanup exceeded ${TimeoutSec}s (likely a stuck DISM mount). Opening the wizard anyway. " +
                "If ISO verification fails, run an elevated prompt: dism /cleanup-wim"
            )
        }
        $null = Receive-Job -Job $job -ErrorAction SilentlyContinue
    }
    catch {
        Write-Verbose "Initialize-WinMintUiMountHygiene job: $($_.Exception.Message)"
    }
    finally {
        if (-not $Async -and $null -ne $job) {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    }
}

function Register-WinMintUiMountHygieneWindowHooks {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [System.Management.Automation.Runspaces.Runspace]$HostRunspace = $null
    )
    if ($null -eq $HostRunspace) {
        $HostRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
    }
    Set-WinMintUiHostRunspacePin -Runspace $HostRunspace
    if ([bool](Get-Variable -Name WinMintUiMountHygieneHooksRegistered -Scope Script -ValueOnly -ErrorAction SilentlyContinue)) {
        return
    }
    $script:WinMintUiMountHygieneHooksRegistered = $true
    $Window.Add_Closing({
        param($cleanupSender, $e)
        [void]$cleanupSender
        try {
            $hr = Get-WinMintUiHostRunspacePin
            $closingWork = {
                if (Get-Command Stop-WinMintUiIsoVerification -ErrorAction SilentlyContinue) {
                    Stop-WinMintUiIsoVerification
                }
                $repo = $null
                try {
                    $ctx = Get-WinMintUiAppContextOptional
                    if ($null -ne $ctx) { $repo = [string]$ctx.RepositoryRoot }
                    if ([string]::IsNullOrWhiteSpace($repo)) { $repo = [string]$script:WinMintRepositoryRoot }
                } catch {}
                if (-not [string]::IsNullOrWhiteSpace($repo) -and (Get-Command Initialize-WinMintUiMountHygiene -ErrorAction SilentlyContinue)) {
                    Initialize-WinMintUiMountHygiene -RepositoryRoot $repo
                }
            }
            if (Get-Command Invoke-WinMintUiWithHostRunspace -ErrorAction SilentlyContinue) {
                Invoke-WinMintUiWithHostRunspace -HostRunspace $hr -Script $closingWork
            } else {
                & $closingWork
            }
        }
        catch {
            Write-Verbose "Mount hygiene on window close: $($_.Exception.Message)"
        }
    })
}
