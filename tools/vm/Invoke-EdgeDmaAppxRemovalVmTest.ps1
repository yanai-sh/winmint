#Requires -Version 7.3
<#
.SYNOPSIS
    Run the Edge DMA AppX removal reboot test inside a Hyper-V WinMint VM.

.DESCRIPTION
    Uses PowerShell Direct to copy Test-EdgeDmaAppxRemoval.ps1 into a running
    guest, starts the first pass, waits for the reboot and after-reboot task, then
    pulls result.json back to the host.

    Run from an elevated host PowerShell. The guest must be booted, reachable over
    PowerShell Direct, and have the provided local account credentials.

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\Invoke-EdgeDmaAppxRemovalVmTest.ps1
#>
[CmdletBinding()]
param(
    [string]$VMName = 'WinMint-ARM-Test',
    [string]$GuestUser = 'dev',
    [string]$GuestPassword = 'winmint',
    [string]$OutDir,
    [int]$TimeoutMinutes = 10
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$guestWorkDir = 'C:\ProgramData\WinMint\EdgeDmaAppxRemovalTest'
$guestScript = Join-Path $guestWorkDir 'Test-EdgeDmaAppxRemoval.ps1'
$guestResult = Join-Path $guestWorkDir 'result.json'
$localScript = Join-Path $PSScriptRoot 'Test-EdgeDmaAppxRemoval.ps1'
if (-not $OutDir) { $OutDir = Join-Path $repoRoot 'output\edge-dma-appx-test' }

function Test-HostAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-GuestSession {
    param([pscredential]$Credential, [datetime]$Deadline)
    do {
        try {
            return New-PSSession -VMName $VMName -Credential $Credential -ErrorAction Stop
        }
        catch {
            if ((Get-Date) -ge $Deadline) { throw }
            Start-Sleep -Seconds 5
        }
    } while ($true)
}

if (-not (Test-HostAdmin)) {
    throw 'Run this in an elevated PowerShell - Hyper-V PowerShell Direct requires Administrator.'
}
if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
    throw 'Hyper-V PowerShell module not found.'
}
if (-not (Test-Path -LiteralPath $localScript)) {
    throw "Test script not found: $localScript"
}

$vm = Get-VM -Name $VMName -ErrorAction Stop
if ($vm.State -ne 'Running') {
    throw "VM '$VMName' must be running; current state is $($vm.State)."
}

$null = New-Item -ItemType Directory -Path $OutDir -Force
$cred = [pscredential]::new($GuestUser, (ConvertTo-SecureString $GuestPassword -AsPlainText -Force))
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$session = $null

try {
    Write-Host "Opening PowerShell Direct session to '$VMName' as $GuestUser ..."
    $session = New-GuestSession -Credential $cred -Deadline $deadline
    Invoke-Command -Session $session -ScriptBlock {
        param($WorkDir)
        $null = New-Item -ItemType Directory -Path $WorkDir -Force
        Remove-Item -LiteralPath (Join-Path $WorkDir 'result.json') -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $WorkDir 'state.json') -Force -ErrorAction SilentlyContinue
    } -ArgumentList $guestWorkDir
    Copy-Item -LiteralPath $localScript -Destination $guestScript -ToSession $session -Force

    Write-Host 'Starting first pass in the guest; it will reboot the VM.'
    Invoke-Command -Session $session -ScriptBlock {
        param($ScriptPath, $WorkDir)
        $pwsh = if (Test-Path 'C:\Program Files\PowerShell\7\pwsh.exe') {
            'C:\Program Files\PowerShell\7\pwsh.exe'
        }
        else {
            'powershell.exe'
        }
        Start-Process -FilePath $pwsh -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            $ScriptPath,
            '-WorkDir',
            $WorkDir
        ) -WindowStyle Hidden
    } -ArgumentList $guestScript, $guestWorkDir
}
finally {
    if ($session) {
        Remove-PSSession $session -ErrorAction SilentlyContinue
        $session = $null
    }
}

Write-Host 'Waiting for the guest to reboot and write result.json ...'
do {
    if ((Get-Date) -ge $deadline) {
        throw "Timed out waiting for $guestResult in '$VMName'."
    }
    Start-Sleep -Seconds 10
    try {
        $session = New-PSSession -VMName $VMName -Credential $cred -ErrorAction Stop
        $exists = Invoke-Command -Session $session -ScriptBlock {
            param($Path)
            Test-Path -LiteralPath $Path
        } -ArgumentList $guestResult
        if ($exists) { break }
    }
    catch {
        # Expected while the VM is rebooting or WinRM/PowerShell Direct is not ready.
    }
    finally {
        if ($session) {
            Remove-PSSession $session -ErrorAction SilentlyContinue
            $session = $null
        }
    }
} while ($true)

$session = New-PSSession -VMName $VMName -Credential $cred -ErrorAction Stop
try {
    Copy-Item -FromSession $session -Path $guestResult -Destination (Join-Path $OutDir 'result.json') -Force
    $localResult = Join-Path $OutDir 'result.json'
    $result = Get-Content -LiteralPath $localResult -Raw | ConvertFrom-Json
    Write-Host "Verdict: $($result.verdict)"
    Write-Host "Result: $localResult"
}
finally {
    if ($session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
}
