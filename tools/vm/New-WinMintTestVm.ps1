#Requires -Version 7.3
<#
.SYNOPSIS
    Create and boot a Hyper-V Gen 2 VM (UEFI + Secure Boot + vTPM) from a WinMint
    ISO to test the install end to end.

.DESCRIPTION
    Builds the kind of VM Windows 11 requires (Generation 2, Secure Boot with the
    Microsoft Windows template, and a virtual TPM) from the newest ISO in .\output
    (or a -IsoPath you pass), attaches the Default Switch for internet if present,
    sets the DVD as the first boot device, starts the VM, and opens vmconnect.

    The guest architecture follows the Hyper-V host (an ARM64 host produces ARM64
    guests), so run this on the same architecture as the ISO you built.

    Requires an elevated PowerShell (Hyper-V management needs Administrator).

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\New-WinMintTestVm.ps1

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\New-WinMintTestVm.ps1 -Recreate -DiskGB 128 -MemoryGB 8
#>
[CmdletBinding()]
param(
    [string]$IsoPath,
    [string]$VMName = 'WinMint-ARM-Test',
    [int]$MemoryGB = 6,
    [int]$DiskGB = 100,
    [int]$CpuCount = 4,
    [string]$SwitchName,
    [switch]$DelayNetworkUntilFirstLogon,
    [string]$GuestUser = 'dev',
    [string]$GuestPassword = 'winmint',
    [switch]$ExposeNestedVirtualization,
    [switch]$Recreate,
    [switch]$NoConnect
)

$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw 'Run this in an elevated PowerShell — Hyper-V management requires Administrator.'
}
if (-not (Get-Command New-VM -ErrorAction SilentlyContinue)) {
    throw 'Hyper-V PowerShell module not found. Enable it: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All'
}

# Resolve the ISO: explicit -IsoPath, else the newest WinMint-*.iso in .\output.
if (-not $IsoPath) {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $outputDir = Join-Path $repoRoot 'output'
    $latest = Get-ChildItem -LiteralPath $outputDir -Filter 'WinMint-*.iso' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { throw "No WinMint-*.iso found in $outputDir. Pass -IsoPath explicitly." }
    $IsoPath = $latest.FullName
}
if (-not (Test-Path -LiteralPath $IsoPath)) { throw "ISO not found: $IsoPath" }

# Recreate or refuse if the VM already exists.
$existing = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($existing) {
    if (-not $Recreate) {
        throw "VM '$VMName' already exists. Re-run with -Recreate to delete and rebuild it (this destroys its disk)."
    }
    if ($existing.State -ne 'Off') { Stop-VM -Name $VMName -TurnOff -Force }
    $oldVhds = @($existing.HardDrives.Path)
    Remove-VM -Name $VMName -Force
    foreach ($p in $oldVhds) { if ($p -and (Test-Path -LiteralPath $p)) { Remove-Item -LiteralPath $p -Force } }
}

$vhdDir = Join-Path $env:USERPROFILE 'Hyper-V'
New-Item -ItemType Directory -Force -Path $vhdDir | Out-Null
$vhd = Join-Path $vhdDir "$VMName.vhdx"
if (Test-Path -LiteralPath $vhd) { Remove-Item -LiteralPath $vhd -Force }

# Attach the NAT "Default Switch" for internet unless the caller suppresses the
# VM network path. When DelayNetworkUntilFirstLogon is selected, keep the adapter
# disconnected until the first sign-in breadcrumb appears so OOBE does not see a
# live network and trigger ZDP while the guest is still in setup.
if (-not $SwitchName) {
    if (Get-VMSwitch -Name 'Default Switch' -ErrorAction SilentlyContinue) { $SwitchName = 'Default Switch' }
}
if ($NoConnect) { $SwitchName = '' }

Write-Host "Creating $VMName from $IsoPath"
$null = New-VM -Name $VMName -Generation 2 -MemoryStartupBytes ($MemoryGB * 1GB) -NewVHDPath $vhd -NewVHDSizeBytes ($DiskGB * 1GB)
Set-VMProcessor -VMName $VMName -Count $CpuCount
if ($ExposeNestedVirtualization) {
    # WSL2 in a guest VM requires nested virtualization. Keep this opt-in so
    # hosts that do not support nested virtualization can still boot the test VM.
    try {
        Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true
    }
    catch {
        Write-Warning "Could not expose virtualization extensions for nested WSL2: $($_.Exception.Message)"
    }
}
# Static memory: Windows Setup is happier with a fixed allocation than dynamic.
Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false -StartupBytes ($MemoryGB * 1GB)
if ($SwitchName -and -not $DelayNetworkUntilFirstLogon) { Connect-VMNetworkAdapter -VMName $VMName -SwitchName $SwitchName }
Add-VMDvdDrive -VMName $VMName -Path $IsoPath
# Windows 11 prerequisites: Secure Boot (Windows template) + virtual TPM.
Set-VMFirmware -VMName $VMName -SecureBootTemplate MicrosoftWindows
Set-VMKeyProtector -VMName $VMName -NewLocalKeyProtector
Enable-VMTPM -VMName $VMName
Set-VMFirmware -VMName $VMName -FirstBootDevice (Get-VMDvdDrive -VMName $VMName)

Start-VM -Name $VMName
Write-Host ("Started {0}: {1} GB RAM, {2} vCPU, {3} GB disk, switch '{4}'." -f `
    $VMName, $MemoryGB, $CpuCount, $DiskGB, ($SwitchName ? $SwitchName : 'none'))
Write-Host "Logs after install: C:\ProgramData\WinMint\Logs (inside the guest)."

if ($SwitchName -and $DelayNetworkUntilFirstLogon) {
    $cred = [pscredential]::new($GuestUser, (ConvertTo-SecureString $GuestPassword -AsPlainText -Force))
    $breadcrumb = 'C:\ProgramData\WinMint\Logs\FirstLogonCommands-fired.txt'
    Write-Host "Delaying network connection until the first-logon breadcrumb appears: $breadcrumb"
    $deadline = (Get-Date).AddMinutes(45)
    while ((Get-Date) -lt $deadline) {
        try {
            $ready = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
                Test-Path -LiteralPath 'C:\ProgramData\WinMint\Logs\FirstLogonCommands-fired.txt'
            }
            if ($ready) {
                Connect-VMNetworkAdapter -VMName $VMName -SwitchName $SwitchName
                Write-Host "Reconnected $VMName to '$SwitchName' after first logon started."
                break
            }
        }
        catch {
            # Expected while the guest is still in OOBE or before the local account is
            # ready for PowerShell Direct. Keep polling until the breadcrumb appears.
        }
        Start-Sleep -Seconds 20
    }
    if ((Get-VMNetworkAdapter -VMName $VMName | Where-Object { $_.Connected -eq $false })) {
        Write-Warning "Timed out waiting for the first-logon breadcrumb; leaving the adapter disconnected."
    }
}

# VMConnect stores display settings per VM GUID under HKCU. A recreated VM gets a NEW
# GUID, so without this it reverts to the tiny default zoom each time. Pre-seed this
# VM's GUID with the host resolution + full-screen + smart-sizing so Enhanced Session
# opens at the right size (clipboard/drive redirection on too). Basic session during
# install is still limited by the guest's low resolution - switch to Enhanced Session
# (View -> Enhanced Session) once the desktop is up for the full-screen experience.
try {
    $vmGuid = (Get-VM -Name $VMName).Id.Guid
    $vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.CurrentHorizontalResolution -gt 0 } | Select-Object -First 1
    $hostW = if ($vc) { [int]$vc.CurrentHorizontalResolution } else { 1920 }
    $hostH = if ($vc) { [int]$vc.CurrentVerticalResolution } else { 1080 }
    $vmcKey = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Virtualization\$vmGuid"
    $null = New-Item -Path $vmcKey -Force
    foreach ($kv in @(
            @{ N = 'DesktopWidth'; V = $hostW }, @{ N = 'DesktopHeight'; V = $hostH },
            @{ N = 'FullScreen'; V = 0 }, @{ N = 'SmartSizing'; V = 1 }, @{ N = 'UseAllMonitors'; V = 0 },
            @{ N = 'RedirectClipboard'; V = 1 }, @{ N = 'RedirectDrives'; V = 1 }
        )) {
        $null = New-ItemProperty -Path $vmcKey -Name $kv.N -PropertyType DWord -Value $kv.V -Force
    }
    Write-Host ("VMConnect display preset for this VM: {0}x{1}, full-screen, smart-sizing, clipboard." -f $hostW, $hostH)
}
catch {
    Write-Warning "Could not preset VMConnect display settings: $($_.Exception.Message)"
}

if (-not $NoConnect) {
    vmconnect.exe localhost $VMName

    # VMConnect's Basic-session window opens tiny on high-DPI hosts (looks like ~20%
    # zoom), and the per-GUID registry preset above is not reliably honored on first
    # launch. With SmartSizing on, a maximized window scales the guest to fill it - so
    # maximize the window programmatically once it appears. Both this script and
    # vmconnect run elevated, so UIPI permits driving its window. This is what makes the
    # readable size persistent across recreates instead of a manual one-off.
    try {
        if (-not ('WinMint.Vmc' -as [type])) {
            Add-Type -Namespace WinMint -Name Vmc -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int n);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr h);
'@
        }
        $SW_MAXIMIZE = 3
        $deadline = (Get-Date).AddSeconds(15)
        $maximized = $false
        while ((Get-Date) -lt $deadline -and -not $maximized) {
            Start-Sleep -Milliseconds 500
            foreach ($p in @(Get-Process -Name 'vmconnect' -ErrorAction SilentlyContinue)) {
                if ($p.MainWindowHandle -ne [IntPtr]::Zero) {
                    [WinMint.Vmc]::ShowWindow($p.MainWindowHandle, $SW_MAXIMIZE) | Out-Null
                    [WinMint.Vmc]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
                    $maximized = $true
                }
            }
        }
        if ($maximized) { Write-Host 'Maximized the VMConnect window (smart-sizing scales the guest to fill it).' }
    }
    catch {
        Write-Warning "Could not maximize the VMConnect window: $($_.Exception.Message)"
    }
}
