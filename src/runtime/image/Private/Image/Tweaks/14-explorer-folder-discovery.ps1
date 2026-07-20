#Requires -Version 7.6

# Baseline: disable Explorer automatic folder-type discovery (content sniffing
# that picks Pictures/Music/Documents templates). Matches the well-known
# WinUtil / community stamp FolderType=NotSpecified under Bags\AllFolders\Shell.
# Offline Default User hive only — no Bags/BagMRU wipe (empty on a fresh hive).

Add-WinMintRegistryTweakModule @{
    id = 'explorer-folder-discovery'
    description = 'Disable Explorer automatic folder type discovery'
    scope = 'default user registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Skip per-folder content sniffing so Explorer opens large folders faster and keeps a consistent General items view; undo deletes FolderType so stock discovery returns.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{
            path = 'zNTUSER\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell'
            name = 'FolderType'
            type = 'REG_SZ'
            value = 'NotSpecified'
            undo = @{ action = 'delete' }
        }
    )
    remove = @()
}
