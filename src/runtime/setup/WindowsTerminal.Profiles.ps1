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

function Get-WinMintWslTerminalProfileDistroName {
    param($TerminalProfileEntry)

    $commandline = [string]$TerminalProfileEntry.commandline
    if ($commandline -match 'wsl\.exe\s+-d\s+"?([^"\s]+)"?') {
        return $matches[1]
    }
    return $null
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
    param(
        [Parameter(Mandatory)][hashtable]$Settings,
        [string[]]$WslDistros = @()
    )

    $pwshProfile = New-WinMintWindowsTerminalPowerShellProfile
    $pwshGuid = '{2c7d8c64-fb18-43d0-9bd0-bf9f6d5c4e22}'
    $disabledSources = Get-WinMintDisabledTerminalProfileSources
    $curatedDistros = @(
        $WslDistros |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { Convert-WinMintWslTerminalDistroName -Distro ([string]$_) } |
            Select-Object -Unique
    )
    $curatedGuids = @(
        foreach ($distro in $curatedDistros) {
            [string](New-WinMintWslTerminalProfile -Distro $distro).guid
        }
    ) | Select-Object -Unique
    $list = [System.Collections.Generic.List[object]]::new()
    $pwshAdded = $false

    foreach ($terminalProfile in @($Settings.profiles.list)) {
        $source = if ($terminalProfile.ContainsKey('source')) { [string]$terminalProfile.source } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($source) -and ($disabledSources -contains $source)) {
            continue
        }
        $profileGuid = if ($terminalProfile.ContainsKey('guid')) { [string]$terminalProfile.guid } else { '' }
        if ($curatedGuids -contains $profileGuid) {
            continue
        }
        if ($source -eq 'Windows.Terminal.Wsl') {
            $autoDistro = Get-WinMintWslTerminalProfileDistroName -TerminalProfileEntry $terminalProfile
            if ($autoDistro -and ($curatedDistros -contains $autoDistro)) {
                continue
            }
        }
        if ($profileGuid -eq $pwshGuid) {
            $list.Add($pwshProfile) | Out-Null
            $pwshAdded = $true
            continue
        }
        $list.Add($terminalProfile) | Out-Null
    }
    if (-not $pwshAdded) {
        $list.Insert(0, $pwshProfile) | Out-Null
    }
    foreach ($distro in $curatedDistros) {
        $list.Add((New-WinMintWslTerminalProfile -Distro $distro)) | Out-Null
    }
    $Settings.profiles.list = @($list)
}

function Set-WinMintWindowsTerminalProfiles {
    param([string[]]$WslDistros = @())

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
    $settings.centerOnLaunch = $true
    $settings.defaultProfile = '{2c7d8c64-fb18-43d0-9bd0-bf9f6d5c4e22}'
    $settings.disabledProfileSources = @(Get-WinMintDisabledTerminalProfileSources)
    $settings.newTabMenu = @([ordered]@{ type = 'remainingProfiles' })

    Update-WinMintWindowsTerminalProfileList -Settings $settings -WslDistros $WslDistros

    $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    if (@($WslDistros | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0) {
        return 'updated'
    }
    return 'updated-with-wsl'
}
