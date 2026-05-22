#Requires -Version 7.3
[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$SchemeName = 'Windows 11 Modern',
    [switch]$RestoreBackup
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell session so cursor files can be copied into %SystemRoot%\Cursors.'
}

$sourceDir = Join-Path $RepositoryRoot 'assets\runtime\cursors\Windows11ModernLight'
$destSegment = 'Windows11Modern'
$destDir = Join-Path $env:SystemRoot "Cursors\$destSegment"
$backupPath = Join-Path $env:LOCALAPPDATA 'WinMint\cursor-backup-current-user.json'

$roleFiles = [ordered]@{
    'Arrow.cur'       = 'Arrow.cur'
    'Help.cur'        = 'Help.cur'
    'Work.ani'        = 'Work.ani'
    'Busy.ani'        = 'Busy.ani'
    'Cross.cur'       = 'Cross.cur'
    'IBeam.cur'       = 'IBeam.cur'
    'Handwriting.cur' = 'Handwriting.cur'
    'Unavailable.cur' = 'Unavailable.cur'
    'SizeNS.cur'      = 'SizeNS.cur'
    'SizeWE.cur'      = 'SizeWE.cur'
    'SizeNWSE.cur'    = 'SizeNWSE.cur'
    'SizeNESW.cur'    = 'SizeNESW.cur'
    'Move.cur'        = 'Move.cur'
    'Alternate.cur'   = 'Alternate.cur'
    'Link.cur'        = 'Link.cur'
    'Pin.cur'         = 'Pin.cur'
    'Person.cur'      = 'Person.cur'
}

$schemeOrder = @(
    'Arrow.cur', 'Help.cur', 'Work.ani', 'Busy.ani', 'Cross.cur', 'IBeam.cur', 'Handwriting.cur', 'Unavailable.cur',
    'SizeNS.cur', 'SizeWE.cur', 'SizeNWSE.cur', 'SizeNESW.cur', 'Move.cur', 'Alternate.cur', 'Link.cur',
    'Pin.cur', 'Person.cur'
)

$cursorPairs = @(
    @{ Name = 'Arrow'; File = 'Arrow.cur' }
    @{ Name = 'Help'; File = 'Help.cur' }
    @{ Name = 'AppStarting'; File = 'Work.ani' }
    @{ Name = 'Wait'; File = 'Busy.ani' }
    @{ Name = 'Crosshair'; File = 'Cross.cur' }
    @{ Name = 'IBeam'; File = 'IBeam.cur' }
    @{ Name = 'NWPen'; File = 'Handwriting.cur' }
    @{ Name = 'No'; File = 'Unavailable.cur' }
    @{ Name = 'SizeNS'; File = 'SizeNS.cur' }
    @{ Name = 'SizeWE'; File = 'SizeWE.cur' }
    @{ Name = 'SizeNWSE'; File = 'SizeNWSE.cur' }
    @{ Name = 'SizeNESW'; File = 'SizeNESW.cur' }
    @{ Name = 'SizeAll'; File = 'Move.cur' }
    @{ Name = 'UpArrow'; File = 'Alternate.cur' }
    @{ Name = 'Hand'; File = 'Link.cur' }
    @{ Name = 'Pin'; File = 'Pin.cur' }
    @{ Name = 'Person'; File = 'Person.cur' }
)

$cursorsKeyPath = 'Control Panel\Cursors'
$schemesKeyPath = 'Control Panel\Cursors\Schemes'
$cursorsKey = "HKCU:\$cursorsKeyPath"
$schemesKey = "HKCU:\$schemesKeyPath"

function Save-CurrentCursorBackup {
    if (Test-Path -LiteralPath $backupPath) {
        Write-Host "Keeping existing cursor backup: $backupPath"
        return
    }

    $backupDir = Split-Path -Parent $backupPath
    $null = New-Item -Path $backupDir -ItemType Directory -Force

    $cursorKeyItem = Get-Item -LiteralPath $cursorsKey
    $schemeKeyItem = Get-Item -LiteralPath $schemesKey -ErrorAction SilentlyContinue
    $cursorValues = [ordered]@{}
    foreach ($name in @('') + ($cursorPairs | ForEach-Object { $_.Name })) {
        $valueName = if ($name -eq '') { '(default)' } else { $name }
        try {
            $value = if ($name -eq '') {
                $cursorKeyItem.GetValue('')
            }
            else {
                $cursorKeyItem.GetValue($name)
            }
            $cursorValues[$valueName] = $value
        }
        catch {
            $cursorValues[$valueName] = $null
        }
    }

    $schemeValues = [ordered]@{}
    if ($schemeKeyItem) {
        foreach ($name in $schemeKeyItem.GetValueNames()) {
            $schemeValues[$name] = $schemeKeyItem.GetValue($name)
        }
    }

    [pscustomobject]@{
        createdAt = (Get-Date).ToString('o')
        cursors = $cursorValues
        schemes = $schemeValues
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $backupPath -Encoding UTF8
}

function Restore-CurrentCursorBackup {
    if (-not (Test-Path -LiteralPath $backupPath)) {
        throw "No cursor backup found at $backupPath"
    }
    $backup = Get-Content -LiteralPath $backupPath -Raw | ConvertFrom-Json
    $cursorKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($cursorsKeyPath)

    foreach ($property in $backup.cursors.PSObject.Properties) {
        $name = if ($property.Name -eq '(default)') { '' } else { $property.Name }
        if ($null -ne $property.Value) {
            $cursorKey.SetValue($name, [string]$property.Value, [Microsoft.Win32.RegistryValueKind]::ExpandString)
        }
    }
    $cursorKey.Close()
}

function Update-CursorSystemParameters {
    Add-Type -Namespace WinMint.Native -Name User32 -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SystemParametersInfo(int uiAction, int uiParam, IntPtr pvParam, int fWinIni);
'@
    $spiSetCursors = 0x0057
    $spifUpdateIniFile = 0x01
    $spifSendChange = 0x02
    [WinMint.Native.User32]::SystemParametersInfo($spiSetCursors, 0, [IntPtr]::Zero, ($spifUpdateIniFile -bor $spifSendChange)) | Out-Null
}

if ($RestoreBackup) {
    Restore-CurrentCursorBackup
    Update-CursorSystemParameters
    Write-Host "Restored cursor settings from $backupPath"
    exit 0
}

if (-not (Test-Path -LiteralPath $sourceDir)) {
    throw "Cursor source folder not found: $sourceDir"
}

foreach ($entry in $roleFiles.GetEnumerator()) {
    $sourcePath = Join-Path $sourceDir $entry.Value
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Cursor source file missing: $sourcePath"
    }
}

Save-CurrentCursorBackup
$null = New-Item -Path $destDir -ItemType Directory -Force
foreach ($entry in $roleFiles.GetEnumerator()) {
    Copy-Item -LiteralPath (Join-Path $sourceDir $entry.Value) -Destination (Join-Path $destDir $entry.Key) -Force
}

$base = "%SystemRoot%\Cursors\$destSegment"
$schemeList = ($schemeOrder | ForEach-Object { "$base\$_" }) -join ','
$cursorKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($cursorsKeyPath)
$schemeKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($schemesKeyPath)
$schemeKey.SetValue($SchemeName, $schemeList, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$cursorKey.SetValue('', $SchemeName, [Microsoft.Win32.RegistryValueKind]::String)
foreach ($pair in $cursorPairs) {
    $cursorKey.SetValue($pair.Name, "$base\$($pair.File)", [Microsoft.Win32.RegistryValueKind]::ExpandString)
}
$schemeKey.Close()
$cursorKey.Close()

Update-CursorSystemParameters
Write-Host "Installed $SchemeName for the current user."
Write-Host "Backup: $backupPath"
