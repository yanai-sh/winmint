#Requires -Version 7.6

# Baseline laptop-friendly cleanup: enable Storage Sense safe cleanup, but keep
# Downloads auto-cleanup explicitly disabled.

Add-WinMintRegistryTweakModule @{
    id = 'storage-sense-policy'
    description = 'Storage Sense safe cleanup with Downloads protected'
    scope = 'default user registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Enable safe laptop cleanup defaults while explicitly keeping Downloads auto-cleanup disabled.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; name = '01'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; name = '04'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; name = '08'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; name = '32'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } }
    )
    remove = @()
}

