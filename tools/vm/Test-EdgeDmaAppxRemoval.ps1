<#
.SYNOPSIS
    Empirically test whether Remove-AppxPackage removes the Edge browser on a
    DMA/EEA Windows 11 install after a reboot.

.DESCRIPTION
    Run inside an elevated WinMint test VM. The first pass records Edge/AppX
    state, removes Edge AppX registrations for all users, registers a one-shot
    startup task, and reboots. The after-reboot pass records the final state and
    writes a verdict JSON.

    This is a test harness only. It does not delete Edge files, patch region
    policy JSON, remove WebView2, or modify shipped WinMint setup behavior.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\vm\Test-EdgeDmaAppxRemoval.ps1
#>
[CmdletBinding()]
param(
    [string]$WorkDir = 'C:\ProgramData\WinMint\EdgeDmaAppxRemovalTest',
    [switch]$AfterReboot,
    [switch]$NoReboot
)

$ErrorActionPreference = 'Stop'
$taskName = 'WinMint-EdgeDmaAppxRemovalTest'
$scriptPath = Join-Path $WorkDir 'Test-EdgeDmaAppxRemoval.ps1'
$resultPath = Join-Path $WorkDir 'result.json'
$statePath = Join-Path $WorkDir 'state.json'

function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-EdgeDmaProbe {
    $programFilesX86 = ${env:ProgramFiles(x86)}
    $edgePaths = @(
        if ($programFilesX86) { Join-Path $programFilesX86 'Microsoft\Edge\Application' }
        if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Microsoft\Edge\Application' }
    )
    $webViewPaths = @(
        if ($programFilesX86) { Join-Path $programFilesX86 'Microsoft\EdgeWebView\Application' }
        if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Microsoft\EdgeWebView\Application' }
    )
    $edgePackages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
        Where-Object {
            [string]$_.Name -match '^(Microsoft\.MicrosoftEdge\.Stable|Microsoft\.Edge)$' -or
            [string]$_.PackageFullName -match 'MicrosoftEdge|Microsoft\.Edge'
        } |
        Sort-Object PackageFullName |
        Select-Object Name, PackageFullName, PackageUserInformation, NonRemovable, SignatureKind, InstallLocation)
    $webViewPackages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
        Where-Object { [string]$_.Name -match 'WebView|EdgeWebView' -or [string]$_.PackageFullName -match 'WebView|EdgeWebView' } |
        Sort-Object PackageFullName |
        Select-Object Name, PackageFullName, NonRemovable, SignatureKind, InstallLocation)
    $edgeUninstall = @(Get-ChildItem -LiteralPath @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        ) -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue } |
        Where-Object { [string]$_.DisplayName -match '^Microsoft Edge$' } |
        Select-Object DisplayName, DisplayVersion, UninstallString, SystemComponent)

    [ordered]@{
        capturedAt = Get-Date -Format o
        edgeApplicationPaths = @($edgePaths | ForEach-Object {
                [ordered]@{ path = $_; exists = [bool](Test-Path -LiteralPath $_ -PathType Container) }
            })
        webView2ApplicationPaths = @($webViewPaths | ForEach-Object {
                [ordered]@{ path = $_; exists = [bool](Test-Path -LiteralPath $_ -PathType Container) }
            })
        edgeAppx = $edgePackages
        webViewAppx = $webViewPackages
        edgeUninstallEntries = $edgeUninstall
    }
}

function Save-Json {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

if (-not (Test-Admin)) {
    throw 'Run this inside the VM from an elevated PowerShell session.'
}

$null = New-Item -ItemType Directory -Path $WorkDir -Force
if ($PSCommandPath -and $PSCommandPath -ne $scriptPath) {
    Copy-Item -LiteralPath $PSCommandPath -Destination $scriptPath -Force
}

if ($AfterReboot) {
    $state = if (Test-Path -LiteralPath $statePath) { Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } else { $null }
    $after = Get-EdgeDmaProbe
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    $edgeStillOnDisk = [bool](@($after.edgeApplicationPaths | Where-Object { $_.exists }).Count)
    $edgeBrowserStillRegistered = [bool](@($after.edgeAppx | Where-Object {
                [string]$_.Name -match '^(Microsoft\.MicrosoftEdge\.Stable|Microsoft\.Edge)$'
            }).Count)
    $webView2Present = [bool](@($after.webView2ApplicationPaths | Where-Object { $_.exists }).Count)
    $verdict = if (-not $edgeStillOnDisk -and -not $edgeBrowserStillRegistered -and $webView2Present) {
        'EdgeRemovedWebView2Preserved'
    }
    elseif ($edgeStillOnDisk -and -not $edgeBrowserStillRegistered -and $webView2Present) {
        'AppxUnregisteredWin32Remained'
    }
    elseif ($edgeBrowserStillRegistered) {
        'EdgeBrowserAppxStillRegistered'
    }
    else {
        'Inconclusive'
    }

    Save-Json -Path $resultPath -Value ([ordered]@{
            generatedAt = Get-Date -Format o
            verdict = $verdict
            before = if ($state) { $state.before } else { $null }
            removal = if ($state) { $state.removal } else { $null }
            after = $after
        })
    Write-Host "Edge DMA AppX removal verdict: $verdict"
    Write-Host "Result: $resultPath"
    return
}

$before = Get-EdgeDmaProbe
$removal = [System.Collections.Generic.List[object]]::new()
foreach ($pkg in @($before.edgeAppx)) {
    try {
        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
        $removal.Add([ordered]@{
                package = [string]$pkg.PackageFullName
                status = 'ok'
                error = $null
            }) | Out-Null
    }
    catch {
        $removal.Add([ordered]@{
                package = [string]$pkg.PackageFullName
                status = 'failed'
                error = [string]$_.Exception.Message
            }) | Out-Null
    }
}

Save-Json -Path $statePath -Value ([ordered]@{
        startedAt = Get-Date -Format o
        before = $before
        removal = @($removal)
    })

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -WorkDir `"$WorkDir`" -AfterReboot"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

Write-Host "Recorded first pass in $statePath"
if ($NoReboot) {
    Write-Host "NoReboot set. Reboot manually, then run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -WorkDir `"$WorkDir`" -AfterReboot"
    return
}

Write-Host 'Rebooting now so the after-reboot pass can record the final Edge state.'
Restart-Computer -Force
