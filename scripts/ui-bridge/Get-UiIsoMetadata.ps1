#Requires -Version 7.3
<#
.SYNOPSIS
  Reads Windows 11 ISO install image metadata for UI bridge callers (JSON on stdout).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$result = [ordered]@{
    Ok           = $false
    Architecture = ''
    Editions     = [string[]]@()
    Error        = ''
}

try {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw 'ISO path not found.'
    }

    Import-Module Dism -ErrorAction Stop
    Import-Module Storage -ErrorAction Stop

    $iso = Mount-DiskImage -ImagePath $Path -Access ReadOnly -NoDriveLetter -PassThru -ErrorAction Stop
    try {
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
    }
} catch {
    $result.Error = $_.Exception.Message
    [Console]::Error.WriteLine($result.Error)
    exit 1
}

[pscustomobject]@{
    Ok           = [bool]$result.Ok
    Architecture = [string]$result.Architecture
    Editions     = @($result.Editions)
    Error        = [string]$result.Error
} | ConvertTo-Json -Compress -Depth 8
