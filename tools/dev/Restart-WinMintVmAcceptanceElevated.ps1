#Requires -Version 7.6
#Requires -RunAsAdministrator
param(
    [string]$ProfilePath = 'tests\profiles\hyper-v-smoke-arm64.json',
    [switch]$ForceBuild,
    [switch]$PushOnly,
    [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot
. (Join-Path $repoRoot 'tools\vm\WinMint-VmConsole.ps1')

$managedPath = Get-WinMintVmManagedRunPath -RepoRoot $repoRoot
$prev = Read-WinMintVmManagedRunState -Path $managedPath
if ($prev -and $prev.pid -and (Test-WinMintVmProcessAlive -ProcessId ([int]$prev.pid))) {
    Write-Host "Stopping stale acceptance worker pid=$($prev.pid)"
    Stop-WinMintVmProcessTree -ProcessId ([int]$prev.pid)
    Start-Sleep -Seconds 3
}

Write-Host 'Clearing WinMint build caches...'
foreach ($sub in @('iso-stage', 'serviced-wim', 'host-drivers')) {
    $path = Join-Path $env:LOCALAPPDATA "WinMint\cache\$sub"
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  removed $path"
    }
}

Write-Host 'Checking for orphaned DISM mounts under temp...'
try {
    foreach ($image in @(Get-WindowsImage -Mounted -ErrorAction SilentlyContinue)) {
        $path = [string]$image.Path
        if ($path -match 'WinMint|Win11ISO') {
            Write-Host "Dismounting $path"
            try { Dismount-WindowsImage -Path $path -Discard -ErrorAction Stop }
            catch {
                & dism.exe /English /Unmount-Image "/MountDir:$path" /Discard 2>$null | Out-Null
            }
        }
    }
}
catch { Write-Warning $_.Exception.Message }

$args = @(
    '-NoProfile', '-File', (Join-Path $repoRoot 'tools\vm\Start-WinMintVmAcceptanceManaged.ps1'),
    '-ProfilePath', $ProfilePath,
    '-Force', '-NoObserve', '-NoLogViewer'
)
if ($ForceBuild) {
    $args += '-ForceBuild'
    $args += '-SmartBuild:$false'
}
if ($PushOnly) { $args += '-PushOnly' }
if ($SkipBuild) { $args += '-SkipBuild' }
& pwsh @args
