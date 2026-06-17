#Requires -Version 7.6

# Baseline: enable Win32 long-path support (paths > 260 chars). Part of the
# Tier 1 dev-QoL defaults promised in AGENTS.md ("show extensions, hidden files,
# long paths") that previously had no implementation.

Add-WinMintRegistryTweakModule @{
    id = 'longpaths-policy'
    description = 'Enable Win32 long path support (LongPathsEnabled)'
    scope = 'offline registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Allow applications that opt in via manifest to use paths longer than MAX_PATH, matching modern developer expectations.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSYSTEM\ControlSet001\Control\FileSystem'; name = 'LongPathsEnabled'; type = 'REG_DWORD'; value = '1'; undo = @{ type = 'REG_DWORD'; value = '0' } }
    )
    remove = @()
}

