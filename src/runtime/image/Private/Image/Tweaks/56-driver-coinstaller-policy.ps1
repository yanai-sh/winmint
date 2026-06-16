#Requires -Version 7.3

# Baseline driver hygiene: allow Windows Update drivers, but block vendor
# co-installers that commonly pull companion apps and tray utilities alongside
# otherwise functional drivers.

Add-WinMintRegistryTweakModule @{
    id = 'driver-coinstaller-policy'
    description = 'Block device-driver companion co-installers'
    scope = 'machine registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Prevent hardware vendors from auto-installing companion apps with drivers while preserving Windows Update driver delivery.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer'; name = 'DisableCoInstallers'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } }
    )
    remove = @()
}
