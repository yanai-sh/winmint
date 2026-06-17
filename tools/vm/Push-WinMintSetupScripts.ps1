#Requires -Version 7.6
<#
.SYNOPSIS
    Fast-iterate WinMint setup/agent scripts in a RUNNING Hyper-V test VM without a
    full rebuild.

.DESCRIPTION
    Pushes the repo's current src\runtime\setup and src\runtime\firstlogon into the guest's
    C:\Windows\Setup\Scripts over PowerShell Direct (VMBus - no network, no ESM,
    works on any Windows edition incl. Home), optionally re-runs the FirstLogon
    agent, then pulls the guest logs + agent state back to the host. Use after one
    full install to validate FirstLogon / SetupComplete / agent fixes in ~30s
    instead of a ~10-minute rebuild. Only schema/staging/answer-file changes still
    need a real rebuild.

    Requires an elevated host shell (PowerShell Direct needs Administrator) and the
    guest running with a known local account (the password WinMint baked into the
    profile). The generated WinMintAgent\BuildProfile.json / WinMintSetupProfile.json /
    packages.json in the guest are left in place - only code files are pushed.

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\Push-WinMintSetupScripts.ps1
    # push current scripts, re-run the agent, pull logs to .\output\vm-logs
#>
[CmdletBinding()]
param(
    [string]$VMName = 'WinMint-ARM-Test',
    [string]$GuestUser = 'dev',
    [string]$GuestPassword = 'winmint',
    [switch]$NoRerun,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run this in an elevated PowerShell - Hyper-V PowerShell Direct requires Administrator.' }
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) { throw "VM '$VMName' not found." }
if ($vm.State -ne 'Running') { throw "VM '$VMName' is not running (state: $($vm.State)). Start it and sign in first." }
if (-not $OutDir) { $OutDir = Join-Path $repoRoot 'output\vm-logs' }
$null = New-Item -ItemType Directory -Path $OutDir -Force

$cred = [pscredential]::new($GuestUser, (ConvertTo-SecureString $GuestPassword -AsPlainText -Force))
Write-Host "Opening PowerShell Direct session to '$VMName' as $GuestUser ..."
$session = New-PSSession -VMName $VMName -Credential $cred -ErrorAction Stop
try {
    $guestScripts = 'C:\Windows\Setup\Scripts'
    $guestAgent = "$guestScripts\WinMintAgent"

    Write-Host 'Pushing src\runtime\setup (scripts + SetupComplete modules) ...'
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src\runtime\setup') -File) {
        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $guestScripts $f.Name) -ToSession $session -Force
    }
    Copy-Item -Path (Join-Path $repoRoot 'src\runtime\setup\SetupComplete\*') -Destination "$guestScripts\SetupComplete" -ToSession $session -Recurse -Force

    Write-Host 'Pushing src\runtime\firstlogon (code; preserving generated guest profiles/packages) ...'
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src\runtime\firstlogon') -File) {
        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $guestAgent $f.Name) -ToSession $session -Force
    }
    Copy-Item -Path (Join-Path $repoRoot 'src\runtime\firstlogon\Modules\*') -Destination "$guestAgent\Modules" -ToSession $session -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'config\packages.json') -Destination (Join-Path $guestAgent 'packages.json') -ToSession $session -Force

    if (-not $NoRerun) {
        Write-Host 'Re-running the FirstLogon agent in the guest (-Force) ...'
        Invoke-Command -Session $session -ScriptBlock {
            $pwsh = if (Test-Path 'C:\Program Files\PowerShell\7\pwsh.exe') { 'C:\Program Files\PowerShell\7\pwsh.exe' } else { 'powershell.exe' }
            & $pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File 'C:\Windows\Setup\Scripts\WinMintAgent\Start-WinMintAgent.ps1' -Force *>&1 | Out-Null
        }
    }

    Write-Host 'Pulling guest logs + agent state back to host ...'
    Invoke-Command -Session $session -ScriptBlock {
        $dst = 'C:\Windows\Temp\winmint-pull'
        Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue
        $null = New-Item -ItemType Directory -Path $dst -Force
        Copy-Item -LiteralPath 'C:\ProgramData\WinMint\Logs' -Destination (Join-Path $dst 'ProgramData-Logs') -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath "$env:LOCALAPPDATA\WinMint") {
            Copy-Item -LiteralPath "$env:LOCALAPPDATA\WinMint" -Destination (Join-Path $dst 'LocalAppData-WinMint') -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Copy-Item -FromSession $session -Path 'C:\Windows\Temp\winmint-pull\*' -Destination $OutDir -Recurse -Force
    Write-Host "Done. Guest logs + state pulled to: $OutDir"
    $statePath = Join-Path $OutDir 'LocalAppData-WinMint\state.json'
    if (Test-Path -LiteralPath $statePath) {
        Write-Host '--- agent run summary ---'
        $st = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        "run.status = $($st.run.status); failedSteps = $(@($st.run.failedSteps) -join ', ')"
    }
}
finally {
    Remove-PSSession $session -ErrorAction SilentlyContinue
}

