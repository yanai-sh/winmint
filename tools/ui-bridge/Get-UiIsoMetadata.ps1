#Requires -Version 5.1
<#
.SYNOPSIS
  Reads Windows 11 ISO install image metadata for UI bridge callers (JSON on stdout).
.DESCRIPTION
  Mounting an ISO and reading its install image with DISM both require administrator
  rights. When invoked from a non-elevated session this script performs an explicit
  UAC handoff (the same pattern as the CLI's Invoke-SelfElevate): it relaunches itself
  elevated, has that child write the JSON result to -ResultPath, then forwards it to
  stdout. -ResultPath is internal and set only on the elevated relaunch.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [string]$ResultPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'WinMint.UiBridgeProtocol.ps1')
Import-Module (Join-Path $repositoryRoot 'src\runtime\modules\WinMint.Bootstrap\WinMint.Bootstrap.psd1') -Force
$bootstrap = Invoke-WinMintRuntimeBootstrap -Entrypoint $PSCommandPath -Arguments @('-Path', $Path, '-ResultPath', $ResultPath)
if ($bootstrap.Relaunched) {
    exit $bootstrap.ExitCode
}

$result = [ordered]@{
    Ok           = $false
    Architecture = ''
    Editions     = [string[]]@()
    Error        = ''
}

function Test-WinMintUiAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-WinMintUiProbeResult {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Result, [string]$ResultPath)
    Write-WinMintUiBridgeResult -Result ([ordered]@{
            Ok           = [bool]$Result.Ok
            Architecture = [string]$Result.Architecture
            Editions     = @($Result.Editions)
            Error        = [string]$Result.Error
        }) -ResultPath $ResultPath
}

# ── UAC handoff: relaunch elevated and capture the child's result via a temp file ──
if (-not (Test-WinMintUiAdministrator) -and [string]::IsNullOrEmpty($ResultPath)) {
    $relayPath = Join-Path ([System.IO.Path]::GetTempPath()) ("winmint-ui-probe-" + [guid]::NewGuid().ToString('N') + '.json')
    try {
        $pwsh = (Get-Process -Id $PID).Path
        $childArgs = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath,
            '-Path', $Path, '-ResultPath', $relayPath
        )
        Start-Process -FilePath $pwsh -ArgumentList $childArgs -Verb RunAs -WindowStyle Hidden -Wait | Out-Null
    } catch {
        $result.Error = "Administrator access is required to read the ISO. UAC was declined or elevation failed: $($_.Exception.Message)"
        Write-WinMintUiProbeResult -Result $result -ResultPath ''
        [Console]::Error.WriteLine($result.Error)
        exit 1
    }

    $json = if (Test-Path -LiteralPath $relayPath) { Get-Content -LiteralPath $relayPath -Raw } else { '' }
    Remove-Item -LiteralPath $relayPath -Force -ErrorAction SilentlyContinue

    if ([string]::IsNullOrWhiteSpace($json)) {
        $result.Error = 'The elevated ISO probe returned no metadata (it may have been cancelled).'
        Write-WinMintUiProbeResult -Result $result -ResultPath ''
        [Console]::Error.WriteLine($result.Error)
        exit 1
    }

    Write-Output $json.Trim()
    exit 0
}

function Push-WinMintUiAutoPlaySuppression {
    $states = [System.Collections.Generic.List[object]]::new()
    foreach ($key in @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    )) {
        $existed = Test-Path -LiteralPath $key
        if (-not $existed) { $null = New-Item -Path $key -Force -ErrorAction SilentlyContinue }
        $hadValue = $false
        $oldValue = $null
        try {
            $item = Get-Item -LiteralPath $key -ErrorAction Stop
            if ($item.Property -contains 'NoDriveTypeAutoRun') {
                $hadValue = $true
                $oldValue = (Get-ItemProperty -LiteralPath $key).NoDriveTypeAutoRun
            }
            $null = Set-ItemProperty -Path $key -Name 'NoDriveTypeAutoRun' -Value 255 -Type DWord -Force
            $states.Add([pscustomobject]@{ Key = $key; Existed = $existed; HadValue = $hadValue; Value = $oldValue })
        } catch {
            Write-Verbose "AutoPlay suppression skipped for ${key}: $($_.Exception.Message)"
        }
    }
    return $states.ToArray()
}

function Pop-WinMintUiAutoPlaySuppression {
    param([object[]]$State)
    foreach ($entry in @($State)) {
        try {
            if ($entry.HadValue) {
                $null = Set-ItemProperty -Path $entry.Key -Name 'NoDriveTypeAutoRun' -Value $entry.Value -Force
            } else {
                $null = Remove-ItemProperty -Path $entry.Key -Name 'NoDriveTypeAutoRun' -Force -ErrorAction SilentlyContinue
                if (-not $entry.Existed) {
                    $keyItem = Get-Item -LiteralPath $entry.Key -ErrorAction SilentlyContinue
                    if ($keyItem -and $keyItem.Property.Count -eq 0) {
                        $null = Remove-Item -LiteralPath $entry.Key -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        } catch {
            Write-Verbose "AutoPlay restore skipped for $($entry.Key): $($_.Exception.Message)"
        }
    }
}

try {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw 'ISO path not found.'
    }

    Import-Module Dism -ErrorAction Stop
    Import-Module Storage -ErrorAction Stop

    [object[]]$autoPlayState = @(Push-WinMintUiAutoPlaySuppression)
    try {
        $iso = Mount-DiskImage -ImagePath $Path -Access ReadOnly -NoDriveLetter -PassThru -ErrorAction Stop
        $volume = $iso | Get-Volume -ErrorAction Stop | Select-Object -First 1
        $root = if ($volume.DriveLetter) {
            "$($volume.DriveLetter):\"
        } elseif ($volume.Path) {
            [string]$volume.Path
        } else {
            throw 'ISO mounted, but Windows did not expose a readable volume.'
        }

        $wim = Join-Path $root 'sources\install.wim'
        $esd = Join-Path $root 'sources\install.esd'
        $imagePath = if (Test-Path -LiteralPath $wim) {
            $wim
        } elseif (Test-Path -LiteralPath $esd) {
            $esd
        } else {
            throw 'This ISO is missing sources\install.wim or sources\install.esd.'
        }

        $images = @(Get-WindowsImage -ImagePath $imagePath -ErrorAction Stop | Sort-Object ImageIndex)
        if ($images.Count -lt 1) { throw 'No install images found in the source ISO.' }

        $firstIndex = [int]$images[0].ImageIndex
        $info = Get-WindowsImage -ImagePath $imagePath -Index $firstIndex -ErrorAction Stop
        $result.Architecture = switch ([int]$info.Architecture) {
            9 { 'amd64' }
            12 { 'arm64' }
            0 { 'x86' }
            default { "arch$([int]$info.Architecture)" }
        }
        $result.Editions = @($images | ForEach-Object { [string]$_.ImageName })
        $result.Ok = $true
    } finally {
        Dismount-DiskImage -ImagePath $Path -ErrorAction SilentlyContinue | Out-Null
        Pop-WinMintUiAutoPlaySuppression -State $autoPlayState
    }
} catch {
    $result.Error = $_.Exception.Message
    Write-WinMintUiProbeResult -Result $result -ResultPath $ResultPath
    [Console]::Error.WriteLine($result.Error)
    exit 1
}

Write-WinMintUiProbeResult -Result $result -ResultPath $ResultPath
