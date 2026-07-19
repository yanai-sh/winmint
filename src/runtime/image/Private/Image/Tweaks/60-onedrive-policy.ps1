#Requires -Version 7.6

# Applied when Microsoft-apps removal is on (default). Removes OneDrive
# integration, blocks sync/reinstall policies, hides the Explorer namespace, and
# forces known folders back to local user-profile paths for new users.

Add-WinMintRegistryTweakModule @{
    id = 'onedrive-policy'
    description = 'OneDrive: remove integration, block sync/reinstall, and force known folders back to local profile paths'
    scope = 'machine and default user registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Remove OneDrive pressure and keep known folders local for new users.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\OneDrive'; name = 'DisableFileSync'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\OneDrive'; name = 'DisableFileSyncNGSC'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\OneDrive'; name = 'DisablePersonalSync';  type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\OneDrive'; name = 'DisableLibrariesDefaultSaveToOneDrive'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Wow6432Node\Policies\Microsoft\Windows\OneDrive'; name = 'DisableFileSync'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Wow6432Node\Policies\Microsoft\Windows\OneDrive'; name = 'DisableFileSyncNGSC'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Wow6432Node\Policies\Microsoft\Windows\OneDrive'; name = 'DisablePersonalSync'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Wow6432Node\Policies\Microsoft\Windows\OneDrive'; name = 'DisableLibrariesDefaultSaveToOneDrive'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'; name = 'System.IsPinnedToNameSpaceTree'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Classes\WOW6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'; name = 'System.IsPinnedToNameSpaceTree'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'; name = 'Desktop'; type = 'REG_EXPAND_SZ'; value = '%USERPROFILE%\Desktop'; undo = @{ type = 'REG_EXPAND_SZ'; value = '%USERPROFILE%\Desktop' } },
        @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'; name = 'Personal'; type = 'REG_EXPAND_SZ'; value = '%USERPROFILE%\Documents'; undo = @{ type = 'REG_EXPAND_SZ'; value = '%USERPROFILE%\Documents' } },
        @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'; name = 'My Pictures'; type = 'REG_EXPAND_SZ'; value = '%USERPROFILE%\Pictures'; undo = @{ type = 'REG_EXPAND_SZ'; value = '%USERPROFILE%\Pictures' } },
        @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'; name = 'My Music'; type = 'REG_EXPAND_SZ'; value = '%USERPROFILE%\Music'; undo = @{ type = 'REG_EXPAND_SZ'; value = '%USERPROFILE%\Music' } },
        @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'; name = 'My Video'; type = 'REG_EXPAND_SZ'; value = '%USERPROFILE%\Videos'; undo = @{ type = 'REG_EXPAND_SZ'; value = '%USERPROFILE%\Videos' } },
        @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'; name = '{374DE290-123F-4565-9164-39C4925E467B}'; type = 'REG_EXPAND_SZ'; value = '%USERPROFILE%\Downloads'; undo = @{ type = 'REG_EXPAND_SZ'; value = '%USERPROFILE%\Downloads' } }
    )
    remove = @(
        @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\OneDrive'; irreversible = $true; irreversibleReason = 'OneDrive Run residue has no stock restore payload on a clean image.' },
        @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\OneDriveSetup'; irreversible = $true; irreversibleReason = 'OneDriveSetup Run residue has no stock restore payload on a clean image.' },
        @{ path = 'zDEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\OneDrive'; irreversible = $true; irreversibleReason = 'OneDrive Run residue has no stock restore payload on a clean image.' },
        @{ path = 'zDEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\OneDriveSetup'; irreversible = $true; irreversibleReason = 'OneDriveSetup Run residue has no stock restore payload on a clean image.' }
    )
}

