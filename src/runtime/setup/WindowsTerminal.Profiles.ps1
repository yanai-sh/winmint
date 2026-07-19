#Requires -Version 5.1

function Get-WinMintDisabledTerminalProfileSources {
    @(
        'Windows.Terminal.WindowsPowerShell'
        'Windows.Terminal.PowershellCore'
        'Windows.Terminal.Azure'
        'Windows.Terminal.VisualStudio'
    )
}

function Convert-WinMintWslTerminalDistroName {
    param([string]$Distro)

    switch -Regex ([string]$Distro) {
        '^(NixOS-WSL|NixOS|nixos-wsl)$' { return 'NixOS' }
        '^(Fedora|FedoraLinux|FedoraLinux-\d+)$' { return 'FedoraLinux' }
        '^(Arch(?: Linux)?|archlinux)$' { return 'archlinux' }
        '^(Pengwin|pengwin)$' { return 'pengwin' }
        '^Ubuntu-\d+\.\d+$' { return 'Ubuntu' }
        default { return ([string]$Distro).Trim() }
    }
}

function Get-WinMintProfileWslDistros {
    param([string]$AgentProfilePath)

    if ([string]::IsNullOrWhiteSpace($AgentProfilePath) -or -not (Test-Path -LiteralPath $AgentProfilePath)) {
        return @()
    }
    try {
        $agentProfile = Get-Content -LiteralPath $AgentProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $distros = @()
        if ($agentProfile.modules -and $agentProfile.modules.wsl) {
            if ($agentProfile.modules.wsl.PSObject.Properties['distros']) {
                $distros = @($agentProfile.modules.wsl.distros)
            }
            elseif ($agentProfile.modules.wsl.PSObject.Properties['distro']) {
                $distros = @([string]$agentProfile.modules.wsl.distro)
            }
        }
        return @(
            $distros |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and [string]$_ -ne 'None' } |
                ForEach-Object { ([string]$_) -split ',' } |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and [string]$_ -ne 'None' } |
                ForEach-Object { Convert-WinMintWslTerminalDistroName -Distro ([string]$_) } |
                Select-Object -Unique
        )
    }
    catch {
        return @()
    }
}

function New-WinMintWindowsTerminalPowerShellProfile {
    [ordered]@{
        guid = '{2c7d8c64-fb18-43d0-9bd0-bf9f6d5c4e22}'
        name = 'PowerShell'
        commandline = 'pwsh.exe -NoLogo'
        startingDirectory = '%USERPROFILE%'
        icon = 'ms-appx:///ProfileIcons/pwsh.png'
        tabTitle = 'pwsh'
    }
}

function New-WinMintWslTerminalProfile {
    param([Parameter(Mandatory)][string]$Distro)

    $wslName = Convert-WinMintWslTerminalDistroName -Distro $Distro
    $displayName = switch ($wslName) {
        'FedoraLinux' { 'Fedora' }
        'archlinux' { 'Arch Linux' }
        default { $wslName }
    }
    $tabTitle = switch ($wslName) {
        'FedoraLinux' { 'fedora' }
        'archlinux' { 'archlinux' }
        default { $wslName.ToLowerInvariant() }
    }
    $guid = switch ($wslName) {
        'Ubuntu' { '{9f23b5e0-8f73-4a90-9d8d-11e8b43d0001}' }
        'FedoraLinux' { '{9f23b5e0-8f73-4a90-9d8d-11e8b43d0002}' }
        'archlinux' { '{9f23b5e0-8f73-4a90-9d8d-11e8b43d0003}' }
        'NixOS' { '{9f23b5e0-8f73-4a90-9d8d-11e8b43d0004}' }
        'pengwin' { '{9f23b5e0-8f73-4a90-9d8d-11e8b43d0005}' }
        default { "{9f23b5e0-8f73-4a90-9d8d-$(([Math]::Abs($wslName.GetHashCode()) % 10000000000).ToString('0000000000'))}" }
    }
    $icon = switch ($wslName) {
        'Ubuntu' { 'ms-appx:///ProfileIcons/ubuntu.png' }
        'FedoraLinux' { 'ms-appx:///ProfileIcons/fedora.png' }
        'archlinux' { 'ms-appx:///ProfileIcons/archlinux.png' }
        'NixOS' { 'ms-appx:///ProfileIcons/nixos.png' }
        'pengwin' { 'ms-appx:///ProfileIcons/pengwin.png' }
        default { $null }
    }

    $terminalProfile = [ordered]@{
        guid = $guid
        name = $displayName
        commandline = "wsl.exe -d $wslName"
        startingDirectory = '~'
        tabTitle = $tabTitle
    }
    if ($icon) { $terminalProfile.icon = $icon }
    return $terminalProfile
}

function Update-WinMintWindowsTerminalProfileList {
    # Hard-replace: only WinMint pwsh + curated WSL profiles. Stock leftovers (cmd,
    # duplicate PowerShell, auto-WSL clones) must not linger in profiles.list.
    param(
        [Parameter(Mandatory)][hashtable]$Settings,
        [string[]]$WslDistros = @()
    )

    $list = [System.Collections.Generic.List[object]]::new()
    $list.Add((New-WinMintWindowsTerminalPowerShellProfile)) | Out-Null
    $curatedDistros = @(
        $WslDistros |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { Convert-WinMintWslTerminalDistroName -Distro ([string]$_) } |
            Select-Object -Unique
    )
    foreach ($distro in $curatedDistros) {
        $list.Add((New-WinMintWslTerminalProfile -Distro $distro)) | Out-Null
    }
    $Settings.profiles.list = @($list)
}

function Set-WinMintWindowsTerminalProfiles {
    param(
        [string[]]$WslDistros = @(),
        [switch]$MockWslProfiles
    )

    $settingsPath = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    if (-not (Test-Path -LiteralPath $settingsPath)) { return 'missing-terminal-settings' }

    $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    if (-not $settings.ContainsKey('profiles')) { $settings.profiles = [ordered]@{} }
    if (-not $settings.profiles.ContainsKey('defaults')) { $settings.profiles.defaults = [ordered]@{} }
    if (-not $settings.profiles.defaults.ContainsKey('font')) { $settings.profiles.defaults.font = [ordered]@{} }
    if (-not $settings.profiles.ContainsKey('list')) { $settings.profiles.list = @() }

    $settings.profiles.defaults.font.face = 'Cascadia Code NF'
    $settings.profiles.defaults.colorScheme = 'One Half Dark'
    $settings.profiles.defaults.bellStyle = 'none'
    $settings.profiles.defaults.opacity = 80
    $settings.centerOnLaunch = $true
    $settings.launchMode = 'default'
    $settings.firstWindowPreference = 'defaultNewWindow'
    $settings.defaultProfile = '{2c7d8c64-fb18-43d0-9bd0-bf9f6d5c4e22}'
    $settings.disabledProfileSources = @(Get-WinMintDisabledTerminalProfileSources)
    $settings.newTabMenu = @([ordered]@{ type = 'remainingProfiles' })

    Update-WinMintWindowsTerminalProfileList -Settings $settings -WslDistros $WslDistros

    $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    $distroCount = @($WslDistros | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count
    if ($distroCount -eq 0) { return 'updated' }
    if ($MockWslProfiles) { return 'updated-with-wsl-mock' }
    return 'updated-with-wsl'
}
