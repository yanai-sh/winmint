#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Install the Surface catalog driver MSI on this PC.
.DESCRIPTION
  Maintainer working tree. Not ready for anyone else to run.
  Windows PowerShell 5.1 and PowerShell 7. Run elevated.
  This file stands alone. The working directory does not matter.
  Optional. The image build injects a classified INF subset offline. This script
  runs Microsoft's Surface driver MSI on the live PC.
  A second run reuses a signed MSI already on disk. An MSI version that is already
  installed is left in place.
  -DryRun resolves the MSI name and does not download or install.

  pwsh -NoProfile -File .\Install-SurfaceDrivers.ps1 -DryRun
  pwsh -NoProfile -File .\Install-SurfaceDrivers.ps1 -DeviceId surface-laptop-7
#>
param(
    [switch] $DryRun,
    [string] $DeviceId = 'surface-laptop-7'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath 'variable:PSNativeCommandUseErrorActionPreference') {
    $PSNativeCommandUseErrorActionPreference = $false
}

# Same row as SurfaceDriverCatalog in the product. SL7 is the only wired device.
$catalog = @{
    'surface-laptop-7' = @{
        Architecture = 'arm64'
        DetailsUrl   = 'https://www.microsoft.com/en-us/download/details.aspx?id=106120'
        FilePattern  = '^SurfaceLaptop7_ARM_Win11_26100_\d{2}\.\d{3}\.\d+\.\d+\.msi$'
        MinimumBuild = 26100
    }
}

function Invoke-NativeContinue {
    param([Parameter(Mandatory)][scriptblock] $Command)
    # Redirected native stderr ends the script on Windows PowerShell 5.1 while Stop is in effect.
    $ErrorActionPreference = 'Continue'
    & $Command | ForEach-Object { "$_" }
}

function Test-MicrosoftDownloadUri {
    param([string] $Uri)
    $parsed = $null
    if (-not [System.Uri]::TryCreate($Uri, [System.UriKind]::Absolute, [ref]$parsed)) {
        return $false
    }

    if ($parsed.Scheme -ne 'https') {
        return $false
    }

    return $parsed.Host -in @('download.microsoft.com', 'www.microsoft.com')
}

function Get-SurfaceDevice {
    param([Parameter(Mandatory)][string] $Id)
    foreach ($key in @($catalog.Keys)) {
        if ($key -eq $Id) {
            return $catalog[$key]
        }
    }

    $known = @($catalog.Keys) -join ', '
    throw "Unknown Surface device '$Id'. Known: $known"
}

function Get-MachineArchitecture {
    if ($env:PROCESSOR_ARCHITEW6432) {
        return $env:PROCESSOR_ARCHITEW6432
    }

    return $env:PROCESSOR_ARCHITECTURE
}

function Resolve-SurfaceMsi {
    param([Parameter(Mandatory)] $Device)
    if (-not (Test-MicrosoftDownloadUri -Uri $Device.DetailsUrl)) {
        throw "Surface driver details URL is not Microsoft-owned: $($Device.DetailsUrl)"
    }

    $content = (Invoke-WebRequest -Uri $Device.DetailsUrl -UseBasicParsing).Content
    $urls = @(
        [regex]::Matches($content, 'https://download\.microsoft\.com/[^"''\s<>]+?\.msi') |
            ForEach-Object { $_.Value } |
            Select-Object -Unique
    )
    if ($urls.Count -lt 1) {
        throw "No direct Microsoft MSI download URL was found on: $($Device.DetailsUrl)"
    }

    $first = [string]($urls | Select-Object -First 1)
    if (-not (Test-MicrosoftDownloadUri -Uri $first)) {
        throw "Surface driver page exposed a non-Microsoft MSI URL: $first"
    }

    $fileName = [IO.Path]::GetFileName(([Uri]$first).AbsolutePath)
    if ($fileName -notmatch $Device.FilePattern) {
        throw "Surface MSI '$fileName' does not match $($Device.FilePattern)"
    }

    return [pscustomobject]@{ DownloadUrl = $first; FileName = $fileName }
}

function Save-SurfaceMsi {
    param([Parameter(Mandatory)][string] $Uri, [Parameter(Mandatory)][string] $Destination)
    $bitsadmin = Join-Path $env:SystemRoot 'System32\bitsadmin.exe'
    if (-not (Test-Path -LiteralPath $bitsadmin)) {
        throw 'bitsadmin.exe is missing, so the Surface MSI cannot be downloaded.'
    }

    $dir = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Force
    }

    $job = 'WinMintSurface-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    Invoke-NativeContinue { & $bitsadmin /create /download $job 2>&1 | Out-Null }
    if ($LASTEXITCODE -ne 0) { throw "BITS /create failed ($LASTEXITCODE)" }
    Invoke-NativeContinue { & $bitsadmin /addfile $job $Uri $Destination 2>&1 | Out-Null }
    if ($LASTEXITCODE -ne 0) { throw "BITS /addfile failed ($LASTEXITCODE): $Uri" }
    Invoke-NativeContinue { & $bitsadmin /setpriority $job FOREGROUND 2>&1 | Out-Null }
    Invoke-NativeContinue { & $bitsadmin /resume $job 2>&1 | Out-Null }
    if ($LASTEXITCODE -ne 0) { throw "BITS /resume failed ($LASTEXITCODE): $Uri" }

    $wait = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $lines = @(Invoke-NativeContinue { & $bitsadmin /rawreturn /getstate $job 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ } })
        if ($LASTEXITCODE -ne 0) { throw "BITS /getstate failed ($LASTEXITCODE)" }
        $state = if ($lines.Count) { [string]$lines[-1] } else { 'UNKNOWN' }
        if ($state -eq 'TRANSFERRED') { break }
        if ($state -in @('ERROR', 'CANCELLED', 'ACKNOWLEDGED')) { throw "BITS $state : $Uri" }
        if ($state -eq 'SUSPENDED') { Invoke-NativeContinue { & $bitsadmin /resume $job 2>&1 | Out-Null } }
        if ($wait.Elapsed.TotalMinutes -ge 45) { throw "BITS timed out after 45 minutes: $Uri" }
        Start-Sleep -Seconds 15
    }

    Invoke-NativeContinue { & $bitsadmin /complete $job 2>&1 | Out-Null }
    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        throw "BITS completed but file missing: $Destination"
    }
}

function Test-MicrosoftSignedMsi {
    param([Parameter(Mandatory)][string] $Path)
    $sig = Get-AuthenticodeSignature -LiteralPath $Path
    return ([string]$sig.Status -eq 'Valid' -and [string]$sig.SignerCertificate.Subject -match 'Microsoft Corporation')
}

$device = Get-SurfaceDevice -Id $DeviceId
$arch = Get-MachineArchitecture
$buildText = [string](Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
$build = 0
if ($buildText) { $build = [int]$buildText }

Write-Output "Surface drivers: $DeviceId ($($device.Architecture), build $($device.MinimumBuild)+)"
Write-Output "This PC: $arch build $build"
Write-Output "Catalog page: $($device.DetailsUrl)"

if ($arch -ne $device.Architecture) {
    throw "This PC is $arch. $DeviceId requires $($device.Architecture)."
}

if ($build -lt [int]$device.MinimumBuild) {
    throw "This PC is build $build. $DeviceId requires build $($device.MinimumBuild) or newer."
}

$resolved = $null
try {
    $resolved = Resolve-SurfaceMsi -Device $device
    Write-Output "MSI: $($resolved.FileName)"
    Write-Output "Download: $($resolved.DownloadUrl)"
}
catch {
    if (-not $DryRun) { throw }
    Write-Output "dry-run: MSI name was not resolved: $($_.Exception.Message)"
}

if ($DryRun) {
    Write-Output 'dry-run: would download that MSI, require a Microsoft signature, then run msiexec /i /qn /norestart.'
    Write-Output 'dry-run: Surface drivers not installed.'
    return
}

if ($null -eq $resolved) {
    throw 'Surface MSI URL was not resolved.'
}

$destination = Join-Path (Join-Path $env:ProgramData 'WinMint\surface-drivers') $resolved.FileName
$reuse = $false
if ((Test-Path -LiteralPath $destination -PathType Leaf) -and (Test-MicrosoftSignedMsi -Path $destination)) {
    $reuse = $true
    Write-Output "using signed MSI already on disk: $destination"
}

if (-not $reuse) {
    Write-Output "downloading $($resolved.FileName)"
    Save-SurfaceMsi -Uri $resolved.DownloadUrl -Destination $destination
}

if (-not (Test-MicrosoftSignedMsi -Path $destination)) {
    throw "Surface driver package is not signed by Microsoft: $destination"
}

$proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $destination, '/qn', '/norestart') -Wait -PassThru
if ($proc.ExitCode -eq 0) {
    Write-Output 'Surface drivers installed.'
}
elseif ($proc.ExitCode -eq 3010 -or $proc.ExitCode -eq 1641) {
    Write-Output 'Surface drivers installed. Reboot to finish.'
}
elseif ($proc.ExitCode -eq 1638) {
    Write-Output 'Surface drivers already installed. Left the existing version in place.'
}
else {
    throw "msiexec failed (exit $($proc.ExitCode)): $destination"
}
