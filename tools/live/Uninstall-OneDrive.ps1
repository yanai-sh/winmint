#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Purge OneDrive from this PC.
.DESCRIPTION
  Windows PowerShell 5.1 and PowerShell 7. Run elevated.
  Leaves %USERPROFILE%\OneDrive in place.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# PowerShell 7 can promote reg.exe / takeown.exe failures into errors. Keep 5.1 behavior.
if (Test-Path -LiteralPath 'variable:PSNativeCommandUseErrorActionPreference') {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Stop-OneDriveProcess {
    $procs = @(Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessName -eq 'OneDrive' -or $_.ProcessName -eq 'OneDriveSetup' })
    if ($procs.Count -eq 0) {
        return
    }

    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Clear-OneDriveRunKey {
    param([Parameter(Mandatory)][string] $KeyPath)
    $query = & reg.exe query $KeyPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        return
    }

    foreach ($line in @($query)) {
        if ($line -notmatch '^\s+(\S+)\s+REG_\w+\s+(.*)$') {
            continue
        }

        $name = $Matches[1]
        $data = $Matches[2]
        if ($name -like '*OneDrive*' -or $data -like '*OneDrive*') {
            & reg.exe delete $KeyPath /v $name /f | Out-Null
            Write-Output "cleared $KeyPath\$name"
        }
    }
}

function Remove-OneDriveTree {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Path) {
        Write-Output "still present: $Path"
    }
    else {
        Write-Output "deleted $Path"
    }
}

function Remove-TrustedInstallerFile {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    & takeown.exe /F $Path /A | Out-Null
    & icacls.exe $Path /grant '*S-1-5-32-544:F' | Out-Null
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Write-Output "OneDrive setup still present: $Path"
    }
    else {
        Write-Output "deleted $Path"
    }
}

function Invoke-OneDrivePurge {
    Stop-OneDriveProcess

    $setups = [System.Collections.Generic.List[string]]::new()
    foreach ($setup in @(
            (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe')
            (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe')
        )) {
        if (Test-Path -LiteralPath $setup -PathType Leaf) {
            $setups.Add($setup)
        }
    }

    $usersRoot = Join-Path $env:SystemDrive 'Users'
    if (Test-Path -LiteralPath $usersRoot) {
        foreach ($userDir in @(Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue)) {
            if ($userDir.Name -in @('Public', 'Default', 'Default User', 'All Users')) {
                continue
            }

            $userSetup = Join-Path $userDir.FullName 'AppData\Local\Microsoft\OneDrive'
            if (Test-Path -LiteralPath $userSetup) {
                foreach ($found in @(Get-ChildItem -LiteralPath $userSetup -Filter 'OneDriveSetup.exe' -Recurse -File -ErrorAction SilentlyContinue)) {
                    $setups.Add($found.FullName)
                }
            }
        }
    }

    $ran = $false
    foreach ($setup in @($setups | Select-Object -Unique)) {
        $ran = $true
        $proc = Start-Process -FilePath $setup -ArgumentList '/uninstall' -Wait -PassThru -WindowStyle Hidden
        Write-Output "OneDriveSetup exit $($proc.ExitCode): $setup"
    }

    if (-not $ran) {
        Write-Output 'OneDriveSetup.exe is not on this PC.'
    }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        & $winget.Source uninstall --id Microsoft.OneDrive --exact --accept-source-agreements --disable-interactivity
        Write-Output "winget OneDrive exit $LASTEXITCODE"
    }

    Stop-OneDriveProcess

    try {
        Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -like '*OneDrive*' } |
            ForEach-Object {
                Unregister-ScheduledTask -InputObject $_ -Confirm:$false -ErrorAction SilentlyContinue
                Write-Output "removed task $($_.TaskName)"
            }
    }
    catch {
        Write-Output "scheduled task cleanup skipped: $($_.Exception.Message)"
    }

    foreach ($run in @(
            'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
            'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
            'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'
        )) {
        Clear-OneDriveRunKey -KeyPath $run
    }

    $defaultHive = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT'
    $loadedDefault = $false
    try {
        if (Test-Path -LiteralPath $defaultHive -PathType Leaf) {
            & reg.exe load HKU\WinMintDefault $defaultHive | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $loadedDefault = $true
                Clear-OneDriveRunKey -KeyPath 'HKU\WinMintDefault\Software\Microsoft\Windows\CurrentVersion\Run'
                Clear-OneDriveRunKey -KeyPath 'HKU\WinMintDefault\Software\Microsoft\Windows\CurrentVersion\RunOnce'
            }
        }
    }
    finally {
        if ($loadedDefault) {
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            & reg.exe unload HKU\WinMintDefault | Out-Null
        }
    }

    foreach ($setup in @(
            (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe')
            (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe')
        )) {
        Remove-TrustedInstallerFile -Path $setup
    }

    $clientDirs = [System.Collections.Generic.List[string]]::new()
    $clientDirs.Add((Join-Path $env:ProgramData 'Microsoft OneDrive'))
    $clientDirs.Add((Join-Path $env:ProgramData 'Microsoft\OneDrive'))
    $programFiles = $env:ProgramFiles
    if ($programFiles) {
        $clientDirs.Add((Join-Path $programFiles 'Microsoft OneDrive'))
    }

    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($programFilesX86) {
        $clientDirs.Add((Join-Path $programFilesX86 'Microsoft OneDrive'))
    }

    if (Test-Path -LiteralPath $usersRoot) {
        foreach ($userDir in @(Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue)) {
            if ($userDir.Name -in @('Public', 'Default', 'Default User', 'All Users')) {
                continue
            }

            $clientDirs.Add((Join-Path $userDir.FullName 'AppData\Local\Microsoft\OneDrive'))
        }
    }

    foreach ($dir in @($clientDirs | Select-Object -Unique)) {
        Remove-OneDriveTree -Path $dir
    }

    $shortcutRoots = [System.Collections.Generic.List[string]]::new()
    foreach ($root in @(
            [Environment]::GetFolderPath('Desktop')
            [Environment]::GetFolderPath('CommonDesktopDirectory')
            (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu')
            (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu')
            (Join-Path $env:SystemDrive 'Users\Default\Desktop')
            (Join-Path $env:SystemDrive 'Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu')
        )) {
        if ($root) {
            $shortcutRoots.Add($root)
        }
    }

    foreach ($root in @($shortcutRoots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        foreach ($lnk in @(Get-ChildItem -LiteralPath $root -Filter 'OneDrive.lnk' -Recurse -File -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $lnk.FullName -Force -ErrorAction SilentlyContinue
            Write-Output "deleted $($lnk.FullName)"
        }
    }

    $namespace = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
    if (Test-Path -LiteralPath $namespace) {
        Remove-Item -LiteralPath $namespace -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output 'removed OneDrive navigation-pane entry'
    }

    $clientState = 'HKCU:\Software\Microsoft\OneDrive'
    if (Test-Path -LiteralPath $clientState) {
        Remove-Item -LiteralPath $clientState -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output 'removed HKCU OneDrive client state'
    }

    $syncFolder = Join-Path $env:USERPROFILE 'OneDrive'
    if (Test-Path -LiteralPath $syncFolder) {
        Write-Output "left user folder: $syncFolder"
    }
}


Invoke-OneDrivePurge
Write-Output 'OneDrive purge applied. Sign out and back in.'
