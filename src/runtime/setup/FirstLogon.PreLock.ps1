#Requires -Version 7.6
# Runs from autounattend FirstLogonCommands before FirstLogon.ps1 — earliest user-session cover.
# Starts the provisioning splash immediately so Explorer is never left as the visible surface.
$ErrorActionPreference = 'SilentlyContinue'
$payloadRoot = $PSScriptRoot
. (Join-Path $payloadRoot 'ProvisioningGuard.ps1')

Enable-WinMintProvisioningGuard
Invoke-WinMintProvisioningDismissStartMenu

# Paint WinMint chrome before/under the host so any brief gap is not stock light Windows.
try {
    $wallpaper = 'C:\Windows\Web\Wallpaper\Windows\WinMint-Bloom.jpg'
    & reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' /v AppsUseLightTheme /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    & reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' /v SystemUsesLightTheme /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    if (Test-Path -LiteralPath $wallpaper) {
        & reg.exe add 'HKCU\Control Panel\Desktop' /v Wallpaper /t REG_SZ /d $wallpaper /f 2>&1 | Out-Null
        & reg.exe add 'HKCU\Control Panel\Desktop' /v WallpaperStyle /t REG_SZ /d 10 /f 2>&1 | Out-Null
        & reg.exe add 'HKCU\Control Panel\Desktop' /v TileWallpaper /t REG_SZ /d 0 /f 2>&1 | Out-Null
    }
}
catch { }

Start-WinMintProvisioningHostEarly -PayloadRoot $payloadRoot | Out-Null
