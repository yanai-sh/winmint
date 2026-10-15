#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Purge OneDrive from this PC, including the OneDrive folder.
.DESCRIPTION
  Maintainer working tree. Not ready for anyone else to run.
  Windows PowerShell 5.1 and PowerShell 7. Run elevated.
  This file stands alone. The working directory does not matter.
  Files that were stored inside an OneDrive folder are moved into the normal
  profile folders first. The OneDrive directory is then deleted.
  A hidden OneDrive metadata folder stays with that directory and is deleted with it.
  OneDriveTemp is deleted without moving its contents.
  Sync is blocked, and known folders are pointed at the normal profile paths.
  A second run leaves OneDrive uninstalled and writes the same policies.
  -DryRun lists what would be removed and changes nothing.
#>
param([switch] $DryRun)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# PowerShell 7 can promote reg.exe / takeown.exe failures into errors. Keep 5.1 behavior.
if (Test-Path -LiteralPath 'variable:PSNativeCommandUseErrorActionPreference') {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Stop-OneDriveProcess {
    $procs = @(Get-Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ProcessName -eq 'OneDrive' -or
                $_.ProcessName -eq 'OneDriveSetup' -or
                $_.ProcessName -eq 'FileCoAuth'
            })
    if ($procs.Count -eq 0) {
        return
    }

    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Invoke-NativeContinue {
    param([Parameter(Mandatory)][scriptblock] $Command)
    # Redirected native stderr ends the script on Windows PowerShell 5.1 while Stop is in effect.
    $ErrorActionPreference = 'Continue'
    & $Command | ForEach-Object { "$_" }
}

function Invoke-RegQuiet {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]] $RegArgs)
    Invoke-NativeContinue { & reg.exe @RegArgs 2>&1 | Out-Null }
}

function Clear-OneDriveRunKey {
    param([Parameter(Mandatory)][string] $KeyPath)
    $query = Invoke-NativeContinue { & reg.exe query $KeyPath 2>&1 }
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
            Invoke-RegQuiet delete $KeyPath /v $name /f
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
        Invoke-NativeContinue { & takeown.exe /F $Path /A /R /D Y 2>&1 | Out-Null }
        Invoke-NativeContinue { & icacls.exe $Path /grant '*S-1-5-32-544:(OI)(CI)F' /T /C 2>&1 | Out-Null }
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $Path) {
        Write-Output "still present: $Path"
    }
    else {
        Write-Output "deleted $Path"
    }
}

function Get-OneDriveRoots {
    param([Parameter(Mandatory)][string] $ProfileRoot)
    if (-not (Test-Path -LiteralPath $ProfileRoot)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $ProfileRoot -Force -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq 'OneDrive' -or
                $_.Name -eq 'OneDriveTemp' -or
                $_.Name -like 'OneDrive - *'
            })
}

function Move-OneDriveChildren {
    param([Parameter(Mandatory)][string] $Source, [Parameter(Mandatory)][string] $Destination)
    if (-not (Test-Path -LiteralPath $Source)) {
        return
    }

    foreach ($child in @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction SilentlyContinue)) {
        if ($child.Name -eq 'desktop.ini') {
            continue
        }

        # OneDrive's own metadata directory. It is deleted with the OneDrive root.
        if ($child.Name -match '^\.[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$') {
            continue
        }

        $target = Join-Path $Destination $child.Name
        if (Test-Path -LiteralPath $target) {
            $existing = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
            if ($null -ne $existing) {
                $targetProp = $existing.PSObject.Properties['Target']
                if ($null -ne $targetProp -and @($targetProp.Value) -contains $child.FullName) {
                    continue
                }
            }
        }

        if ($child.PSIsContainer) {
            if (-not (Test-Path -LiteralPath $target)) {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
            }

            Move-OneDriveChildren -Source $child.FullName -Destination $target
        }
        else {
            Move-Item -LiteralPath $child.FullName -Destination $target -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $child.FullName)) {
                Write-Output "moved $($child.Name) to $Destination"
            }
        }
    }
}

function Reset-ShellFoldersOutOfOneDrive {
    $usf = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    if (-not (Test-Path -LiteralPath $usf)) {
        return
    }

    $profile = $env:USERPROFILE.TrimEnd('\')
    $key = Get-Item -LiteralPath $usf
    foreach ($name in @($key.GetValueNames())) {
        $raw = [string] $key.GetValue($name)
        if ($raw -notlike '*OneDrive*') {
            continue
        }

        $expanded = [Environment]::ExpandEnvironmentVariables($raw)
        if ($expanded -notmatch '^[A-Za-z]:\\Users\\[^\\]+\\OneDrive( - [^\\]+)?(.*)$') {
            continue
        }

        $local = $profile + $Matches[2]
        if (-not (Test-Path -LiteralPath $local)) {
            New-Item -ItemType Directory -Path $local -Force | Out-Null
        }

        $stored = $local
        if ($stored.StartsWith($profile, [System.StringComparison]::OrdinalIgnoreCase)) {
            $stored = '%USERPROFILE%' + $stored.Substring($profile.Length)
        }

        New-ItemProperty -LiteralPath $usf -Name $name -Value $stored -PropertyType ExpandString -Force | Out-Null
        Write-Output "shell folder $name -> $stored"
    }
}

function Remove-TrustedInstallerFile {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    Invoke-NativeContinue { & takeown.exe /F $Path /A 2>&1 | Out-Null }
    Invoke-NativeContinue { & icacls.exe $Path /grant '*S-1-5-32-544:F' 2>&1 | Out-Null }
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Write-Output "OneDrive setup still present: $Path"
    }
    else {
        Write-Output "deleted $Path"
    }
}

function Set-OneDriveBlock {
    $pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
    foreach ($name in @(
            'DisableFileSyncNGSC'
            'DisableFileSync'
            'DisableMeteredNetworkFileSync'
            'PreventNetworkTrafficPreUserSignIn'
        )) {
        if ($DryRun) {
            Write-Output "dry-run: $pol $name = 1"
            continue
        }

        if (-not (Test-Path -LiteralPath $pol)) {
            New-Item -Path $pol -Force | Out-Null
        }

        New-ItemProperty -LiteralPath $pol -Name $name -Value 1 -PropertyType DWord -Force | Out-Null
    }
}

function Set-ProfileFolder {
    param([Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][string] $Value)
    $folders = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    if ($DryRun) {
        Write-Output "dry-run: $folders $Name = $Value"
        return
    }

    if (-not (Test-Path -LiteralPath $folders)) {
        New-Item -Path $folders -Force | Out-Null
    }

    New-ItemProperty -LiteralPath $folders -Name $Name -Value $Value -PropertyType ExpandString -Force | Out-Null
}

function Set-ProfileFolders {
    Set-ProfileFolder 'Desktop' '%USERPROFILE%\Desktop'
    Set-ProfileFolder 'Personal' '%USERPROFILE%\Documents'
    Set-ProfileFolder 'My Pictures' '%USERPROFILE%\Pictures'
    Set-ProfileFolder 'My Music' '%USERPROFILE%\Music'
    Set-ProfileFolder 'My Video' '%USERPROFILE%\Videos'
    Set-ProfileFolder 'Favorites' '%USERPROFILE%\Favorites'
    Set-ProfileFolder '{374DE290-123F-4565-9164-39C4925E467B}' '%USERPROFILE%\Downloads'
    Set-ProfileFolder '{F42EE2D3-909F-4907-8871-4C22FC0BF756}' '%USERPROFILE%\Documents'
    Set-ProfileFolder '{0DDD015D-B06C-45D5-8C4C-F59713854639}' '%USERPROFILE%\Pictures'
    Set-ProfileFolder '{A0C69A99-21C8-4671-8703-7934162FCF1D}' '%USERPROFILE%\Music'
    Set-ProfileFolder '{35286A68-3C57-41A1-BBB1-0EAE73D76C95}' '%USERPROFILE%\Videos'
    Set-ProfileFolder '{754AC886-DF64-4CBA-86B5-F7FBF4FBCEF5}' '%USERPROFILE%\Desktop'
}

function Invoke-OneDrivePurge {
    Set-OneDriveBlock
    if ($DryRun) {
        Write-Output 'dry-run: OneDrive purge. No files or registry will be changed.'
        foreach ($setup in @(
                (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe')
                (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe')
            )) {
            if (Test-Path -LiteralPath $setup) {
                Write-Output "dry-run: uninstall $setup"
            }
            else {
                Write-Output "dry-run: absent $setup"
            }
        }

        if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
            Write-Output 'dry-run: winget uninstall Microsoft.OneDrive'
        }

        $usersRoot = Join-Path $env:SystemDrive 'Users'
        if (Test-Path -LiteralPath $usersRoot) {
            foreach ($userDir in @(Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue)) {
                if ($userDir.Name -in @('Public', 'Default', 'Default User', 'All Users')) {
                    continue
                }

                foreach ($root in @(Get-OneDriveRoots -ProfileRoot $userDir.FullName)) {
                    if ($root.Name -eq 'OneDriveTemp') {
                        Write-Output "dry-run: delete $($root.FullName)"
                    }
                    else {
                        Write-Output "dry-run: move files out of $($root.FullName), then delete it"
                    }
                }

                foreach ($client in @(
                        (Join-Path $userDir.FullName 'AppData\Local\Microsoft\OneDrive')
                        (Join-Path $userDir.FullName 'AppData\Roaming\Microsoft\OneDrive')
                    )) {
                    if (Test-Path -LiteralPath $client) {
                        Write-Output "dry-run: delete $client"
                    }
                }
            }
        }

        Write-Output 'dry-run: clear OneDrive Run and RunOnce values, shortcuts, sync roots, and navigation-pane entries'
        Write-Output 'dry-run: disable OneSyncSvc'
        Write-Output 'dry-run: set HKLM\SOFTWARE\Microsoft\OneDrive PreventNetworkTrafficPreUserSignIn = 1'
        Set-ProfileFolders
        return
    }

    Stop-OneDriveProcess

    $setups = @()
    foreach ($setup in @(
            (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe')
            (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe')
        )) {
        if (Test-Path -LiteralPath $setup -PathType Leaf) {
            $setups += $setup
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
                    $setups += $found.FullName
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
        $wingetOut = Invoke-NativeContinue { & $winget.Source uninstall --id Microsoft.OneDrive --exact --accept-source-agreements --disable-interactivity 2>&1 }
        if ($LASTEXITCODE -eq 0) {
            Write-Output 'winget: Microsoft.OneDrive uninstalled'
        }
        elseif ($LASTEXITCODE -eq -1978335212 -or $LASTEXITCODE -eq 2316632084) {
            Write-Output 'winget: Microsoft.OneDrive is not installed'
        }
        else {
            Write-Output "winget OneDrive exit $LASTEXITCODE"
            foreach ($line in @($wingetOut)) {
                $text = "$line".Trim()
                if ($text) {
                    Write-Output $text
                }
            }
        }
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
            'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
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
            Invoke-RegQuiet query HKU\WinMintDefault
            if ($LASTEXITCODE -eq 0) {
                Invoke-RegQuiet unload HKU\WinMintDefault
            }

            Invoke-RegQuiet load HKU\WinMintDefault $defaultHive
            if ($LASTEXITCODE -eq 0) {
                $loadedDefault = $true
                Clear-OneDriveRunKey -KeyPath 'HKU\WinMintDefault\Software\Microsoft\Windows\CurrentVersion\Run'
                Clear-OneDriveRunKey -KeyPath 'HKU\WinMintDefault\Software\Microsoft\Windows\CurrentVersion\RunOnce'
                Invoke-RegQuiet delete 'HKU\WinMintDefault\Software\Microsoft\OneDrive' /f
                Invoke-RegQuiet delete 'HKU\WinMintDefault\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' /f
                foreach ($envName in @('OneDrive', 'OneDriveConsumer', 'OneDriveCommercial')) {
                    Invoke-RegQuiet delete 'HKU\WinMintDefault\Environment' /v $envName /f
                }
            }
            else {
                Write-Output 'default user hive was not loaded. Default-profile OneDrive cleanup skipped.'
            }
        }
    }
    finally {
        if ($loadedDefault) {
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            Invoke-RegQuiet unload HKU\WinMintDefault
        }
    }

    foreach ($setup in @(
            (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe')
            (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe')
        )) {
        Remove-TrustedInstallerFile -Path $setup
    }

    $clientDirs = @()
    $clientDirs += (Join-Path $env:ProgramData 'Microsoft OneDrive')
    $clientDirs += (Join-Path $env:ProgramData 'Microsoft\OneDrive')
    $programFiles = $env:ProgramFiles
    if ($programFiles) {
        $clientDirs += (Join-Path $programFiles 'Microsoft OneDrive')
    }

    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($programFilesX86) {
        $clientDirs += (Join-Path $programFilesX86 'Microsoft OneDrive')
    }

    if (Test-Path -LiteralPath $usersRoot) {
        foreach ($userDir in @(Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue)) {
            if ($userDir.Name -in @('Public', 'Default', 'Default User', 'All Users')) {
                continue
            }

            $clientDirs += (Join-Path $userDir.FullName 'AppData\Local\Microsoft\OneDrive')
            $clientDirs += (Join-Path $userDir.FullName 'AppData\Roaming\Microsoft\OneDrive')
            foreach ($root in @(Get-OneDriveRoots -ProfileRoot $userDir.FullName)) {
                if ($root.Name -ne 'OneDriveTemp') {
                    Move-OneDriveChildren -Source $root.FullName -Destination $userDir.FullName
                }

                $clientDirs += $root.FullName
            }
        }
    }

    Reset-ShellFoldersOutOfOneDrive

    foreach ($dir in @($clientDirs | Select-Object -Unique)) {
        Remove-OneDriveTree -Path $dir
    }

    $shortcutRoots = @()
    foreach ($root in @(
            [Environment]::GetFolderPath('Desktop')
            [Environment]::GetFolderPath('CommonDesktopDirectory')
            (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu')
            (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu')
            (Join-Path $env:SystemDrive 'Users\Default\Desktop')
            (Join-Path $env:SystemDrive 'Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu')
        )) {
        if ($root) {
            $shortcutRoots += $root
        }
    }

    if (Test-Path -LiteralPath $usersRoot) {
        foreach ($userDir in @(Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue)) {
            if ($userDir.Name -in @('Public', 'Default', 'Default User', 'All Users')) {
                continue
            }

            $shortcutRoots += (Join-Path $userDir.FullName 'Desktop')
            $shortcutRoots += (Join-Path $userDir.FullName 'AppData\Roaming\Microsoft\Windows\Start Menu')
        }
    }

    foreach ($root in @($shortcutRoots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        foreach ($lnk in @(Get-ChildItem -LiteralPath $root -Filter '*OneDrive*.lnk' -Recurse -File -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $lnk.FullName -Force -ErrorAction SilentlyContinue
            Write-Output "deleted $($lnk.FullName)"
        }
    }

    foreach ($namespace in @(
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
            'HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
            'HKCU:\Software\Microsoft\OneDrive'
            'HKCU:\Software\SyncEngines\Providers\OneDrive'
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\OneDrive'
        )) {
        if (Test-Path -LiteralPath $namespace) {
            Remove-Item -LiteralPath $namespace -Recurse -Force -ErrorAction SilentlyContinue
            Write-Output "removed $namespace"
        }
    }

    $syncRoots = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SyncRootManager'
    if (Test-Path -LiteralPath $syncRoots) {
        foreach ($root in @(Get-ChildItem -LiteralPath $syncRoots -ErrorAction SilentlyContinue)) {
            if ($root.PSChildName -like '*OneDrive*') {
                Remove-Item -LiteralPath $root.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Output "removed SyncRootManager $($root.PSChildName)"
            }
        }
    }

    foreach ($uninstallRoot in @(
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )) {
        if (-not (Test-Path -LiteralPath $uninstallRoot)) {
            continue
        }

        foreach ($entry in @(Get-ChildItem -LiteralPath $uninstallRoot -ErrorAction SilentlyContinue)) {
            $display = ''
            try {
                $display = [string] (Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction Stop).DisplayName
            }
            catch {
                $display = ''
            }

            if ($entry.PSChildName -like '*OneDrive*' -or $display -like '*OneDrive*') {
                Remove-Item -LiteralPath $entry.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Output "removed uninstall $($entry.PSChildName)"
            }
        }
    }

    foreach ($envName in @('OneDrive', 'OneDriveConsumer', 'OneDriveCommercial')) {
        [Environment]::SetEnvironmentVariable($envName, $null, 'User')
        Remove-ItemProperty -LiteralPath 'HKCU:\Environment' -Name $envName -ErrorAction SilentlyContinue
    }

    foreach ($service in @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'OneSyncSvc*' })) {
        $startType = $service.PSObject.Properties['StartType']
        if ($null -ne $startType -and [string]$startType.Value -eq 'Disabled') {
            continue
        }

        Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $service.Name -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Output "disabled service $($service.Name)"
    }

    # Keep the sync block after the client key is cleared.
    $block = 'HKLM:\SOFTWARE\Microsoft\OneDrive'
    if (-not (Test-Path -LiteralPath $block)) {
        New-Item -Path $block -Force | Out-Null
    }

    New-ItemProperty -LiteralPath $block -Name 'PreventNetworkTrafficPreUserSignIn' -Value 1 -PropertyType DWord -Force | Out-Null

    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\OneDrive') {
        $clientKey = Get-Item -LiteralPath 'HKLM:\SOFTWARE\Microsoft\OneDrive'
        foreach ($name in @($clientKey.GetValueNames())) {
            if ($name -ne 'PreventNetworkTrafficPreUserSignIn') {
                Remove-ItemProperty -LiteralPath $block -Name $name -ErrorAction SilentlyContinue
                Write-Output "cleared HKLM OneDrive $name"
            }
        }

        foreach ($sub in @(Get-ChildItem -LiteralPath $block -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $sub.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Output "removed $($sub.PSPath)"
        }
    }

    Set-ProfileFolders
}


Invoke-OneDrivePurge
if ($DryRun) {
    Write-Output 'dry-run: OneDrive purge not applied.'
}
else {
    Write-Output 'OneDrive purge applied. Sign out and back in.'
}
