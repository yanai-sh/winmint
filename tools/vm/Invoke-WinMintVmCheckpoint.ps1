#Requires -Version 7.6

<#

.SYNOPSIS

    Save, restore, or list Hyper-V checkpoints for WinMint VM iteration.



.DESCRIPTION

    Checkpoints amortize Windows Setup across FirstLogon/setup iterations. A

    PostSetup checkpoint is valid only after setup completes and before the agent

    reaches a terminal run.status.



    Restoring a checkpoint does not re-validate autounattend or WIM changes — rebuild

    the ISO and reinstall when those change. Use Build-And-TestVm.ps1 -UseCheckpoint

    to restore automatically when the build fingerprint sidecar matches.



.EXAMPLE

    pwsh -NoProfile -File .\tools\vm\Invoke-WinMintVmCheckpoint.ps1 -Action Save -Name PostSetup



.EXAMPLE

    pwsh -NoProfile -File .\tools\vm\Invoke-WinMintVmCheckpoint.ps1 -Action Restore -Name PostSetup

#>

[CmdletBinding()]

param(

    [Parameter(Mandatory)][ValidateSet('Save', 'Restore', 'List')]

    [string]$Action,

    [string]$Name = 'PostSetup',

    [string]$VMName = 'WinMint-ARM-Test',

    [string]$GuestUser = 'dev',

    [string]$GuestPassword = 'winmint',

    [string]$SwitchName,

    [string]$Fingerprint

)



$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'WinMint-VmConsole.ps1')

$repoRoot = Set-WinMintVmRepoRoot -ToolsVmRoot $PSScriptRoot



$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {

    throw 'Run this in an elevated PowerShell - Hyper-V management requires Administrator.'

}



$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue

if (-not $vm) { throw "VM '$VMName' not found." }



function Resolve-WinMintVmCheckpointFingerprint {

    param([string]$ExplicitFingerprint)



    if (-not [string]::IsNullOrWhiteSpace($ExplicitFingerprint)) { return $ExplicitFingerprint }

    $buildSidecar = Join-Path $repoRoot 'output\.vm-build-fingerprint.json'

    if (-not (Test-Path -LiteralPath $buildSidecar)) {

        throw "No -Fingerprint supplied and build sidecar missing: $buildSidecar. Run Build-And-TestVm.ps1 once or pass -Fingerprint."

    }

    $prev = Get-Content -LiteralPath $buildSidecar -Raw | ConvertFrom-Json

    if ([string]::IsNullOrWhiteSpace([string]$prev.fingerprint)) {

        throw "Build sidecar at $buildSidecar has no fingerprint field."

    }

    return [string]$prev.fingerprint

}



switch ($Action) {

    'List' {

        $snapshots = @(Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue | Sort-Object CreationTime)

        if ($snapshots.Count -eq 0) {

            Write-Host "No checkpoints on '$VMName'."

            exit 0

        }

        $snapshots | ForEach-Object {

            Write-Host "$($_.Name)  created=$($_.CreationTime.ToString('o'))  parent=$($_.Parent.Name)"

        }

        exit 0

    }

    'Save' {

        if ($vm.State -ne 'Running') {

            throw "VM '$VMName' must be running to validate the post-setup boundary (state: $($vm.State))."

        }

        $cred = [pscredential]::new($GuestUser, (ConvertTo-SecureString $GuestPassword -AsPlainText -Force))

        $fp = Resolve-WinMintVmCheckpointFingerprint -ExplicitFingerprint $Fingerprint

        if (-not (Save-WinMintVmPostSetupCheckpoint -VMName $VMName -Credential $cred -Fingerprint $fp -RepoRoot $repoRoot -CheckpointName $Name)) {

            $ready = Test-WinMintVmPostSetupCheckpointReady -VmName $VMName -Credential $cred

            throw "Refusing to save '$Name': setupComplete=$($ready.SetupComplete), agentTerminal=$($ready.AgentTerminal). Save after Setup completes and before FirstLogon agent finishes."

        }

        exit 0

    }

    'Restore' {

        Restore-WinMintVmPostSetupCheckpoint -VMName $VMName -CheckpointName $Name -SwitchName $SwitchName

        exit 0

    }

}

