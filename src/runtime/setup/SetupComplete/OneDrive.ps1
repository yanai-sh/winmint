# SetupComplete machine-phase module: OneDrive integration removal.
# Dot-sourced by SetupComplete.ps1; relies on its script-scope $logDir.

function Invoke-ScOneDriveRemoval {
    Write-ScLog 'Removing OneDrive machine integration.'
    foreach ($name in @('OneDrive', 'OneDriveSetup')) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    foreach ($setup in @(
            "$env:SystemRoot\System32\OneDriveSetup.exe",
            "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
        )) {
        if (Test-Path -LiteralPath $setup) {
            try {
                $p = Start-Process -FilePath $setup -ArgumentList '/uninstall' -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
                Write-ScLog "OneDriveSetup uninstall returned $($p.ExitCode): $setup"
            }
            catch {
                Write-ScWarn "OneDrive uninstall failed for ${setup}: $_"
            }
        }
    }

    foreach ($setupFile in @(
            "$env:SystemRoot\System32\OneDriveSetup.exe",
            "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
            "$env:SystemRoot\System32\OneDriveSetup.exe.bak",
            "$env:SystemRoot\SysWOW64\OneDriveSetup.exe.bak"
        )) {
        if (-not (Test-Path -LiteralPath $setupFile)) { continue }
        try {
            takeown.exe /f $setupFile | Out-Null
            icacls.exe $setupFile /grant '*S-1-5-32-544:F' | Out-Null
            Remove-Item -LiteralPath $setupFile -Force -ErrorAction Stop
            Write-ScLog "Removed OneDrive installer file: $setupFile"
        }
        catch {
            Write-ScWarn "OneDrive installer file removal failed for ${setupFile}: $_"
        }
    }

    foreach ($regArgs in @(
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableFileSync', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableFileSyncNGSC', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisablePersonalSync', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableLibrariesDefaultSaveToOneDrive', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableFileSync', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableFileSyncNGSC', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKCR\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}', '/v', 'System.IsPinnedToNameSpaceTree', '/t', 'REG_DWORD', '/d', '0', '/f'),
            @('add', 'HKCR\WOW6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}', '/v', 'System.IsPinnedToNameSpaceTree', '/t', 'REG_DWORD', '/d', '0', '/f')
        )) {
        & reg.exe @regArgs 2>$null
    }

    foreach ($runKey in @(
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run',
            'HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            'HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            'HKU\.DEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKU\.DEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKU\.DEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        )) {
        foreach ($value in @('OneDrive', 'OneDriveSetup')) {
            & reg.exe delete $runKey /v $value /f 2>$null
        }
    }

    foreach ($root in @(
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Active Setup\Installed Components',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Active Setup\Installed Components',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\App Paths',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
            'Registry::HKEY_USERS\.DEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SyncRootManager',
            'Registry::HKEY_USERS\.DEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace'
        )) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            $text = @(
                $key.PSChildName
                if ($props) { $props.PSObject.Properties | ForEach-Object { [string]$_.Value } }
            ) -join "`n"
            if ($text -match '(?i)OneDrive|OneDriveSetup\.exe') {
                try {
                    Remove-Item -LiteralPath $key.PSPath -Recurse -Force -ErrorAction Stop
                    Write-ScLog "Removed OneDrive registry residue: $($key.Name)"
                }
                catch {
                    Write-ScWarn "OneDrive registry residue removal failed for $($key.Name): $_"
                }
            }
        }
    }

    Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object {
            $_.TaskName -match '(?i)OneDrive' -or
            $_.TaskPath -match '(?i)OneDrive' -or
            @($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -match '(?i)OneDrive|OneDriveSetup\.exe'
        } |
        Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue

    Remove-Item -LiteralPath @(
        "$env:ProgramData\Microsoft OneDrive",
        "$env:SystemDrive\OneDriveTemp"
    ) -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\OneDrive*.lnk" -Force -ErrorAction SilentlyContinue
}
