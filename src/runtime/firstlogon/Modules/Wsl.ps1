#Requires -Version 7.6

function Convert-WinMintWslDistroAlias {
    param([string]$Distro)

    $value = ([string]$Distro).Trim()
    switch -Regex ($value) {
        '^Ubuntu-\d+\.\d+$' { return 'Ubuntu' }
        '^Fedora(?:Linux)?-\d+$' { return 'FedoraLinux' }
        '^(Fedora|FedoraLinux)$' { return 'FedoraLinux' }
        '^(Arch(?: Linux)?|archlinux)$' { return 'archlinux' }
        '^(NixOS-WSL|NixOS|nixos-wsl)$' { return 'NixOS' }
        '^(Pengwin|pengwin)$' { return 'pengwin' }
        default             { return $value }
    }
}

function Get-WinMintOnlineWslDistributions {
    param([Parameter(Mandatory)][string]$WslPath)

    try {
        $lines = @(& $WslPath --list --online 2>$null)
    }
    catch {
        Write-AgentLog "WSL online catalog warning: $($_.Exception.Message)"
        return @()
    }

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        $clean = ([string]$line -replace "`0", '').Trim()
        if ([string]::IsNullOrWhiteSpace($clean)) { continue }
        if ($clean -match '^(NAME|The following|Install using)') { continue }
        if ($clean -match '^([A-Za-z0-9_.-]+)(\s+|$)') {
            $name = $matches[1]
            if (-not $names.Contains($name)) { $names.Add($name) }
        }
    }
    return $names.ToArray()
}

function Resolve-WinMintWslDistro {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [string[]]$OnlineNames = @()
    )

    $alias = Convert-WinMintWslDistroAlias -Distro $Distro
    if ($alias -eq 'NixOS') {
        return 'NixOS'
    }
    if ($alias -match '^FedoraLinux-\d+$') {
        if ($OnlineNames -contains $alias) { return $alias }
        throw "Requested Fedora WSL distribution is not available from `wsl --list --online`: $alias"
    }
    if ($alias -eq 'FedoraLinux') {
        if ($OnlineNames -contains 'FedoraLinux') { return 'FedoraLinux' }

        $latest = $null
        foreach ($name in @($OnlineNames)) {
            if ($name -match '^FedoraLinux-(\d+)$') {
                $version = [int]$matches[1]
                if ($null -eq $latest -or $version -gt $latest.Version) {
                    $latest = [pscustomobject]@{ Name = $name; Version = $version }
                }
            }
        }
        if ($latest) { return $latest.Name }
        throw 'Unable to resolve the latest Fedora WSL distribution from `wsl --list --online`.'
    }

    return $alias
}

function Get-WinMintNixOsWslReleaseAssetUri {
    param(
        [string]$Repository = 'nix-community/NixOS-WSL',
        [string]$Architecture = (Get-AgentProcessorArchitecture)
    )

    $uri = "https://api.github.com/repos/$Repository/releases/latest"
    $headers = @{ 'User-Agent' = 'WinMint' }
    $release = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
    $assetNames = switch ([string]$Architecture) {
        'arm64' { @('nixos.aarch64.wsl', 'nixos.arm64.wsl', 'nixos.wsl') }
        'amd64' { @('nixos.wsl', 'nixos.x86_64.wsl', 'nixos.amd64.wsl') }
        default { @('nixos.wsl') }
    }
    $asset = $null
    foreach ($assetName in $assetNames) {
        $asset = @($release.assets | Where-Object { [string]$_.name -eq $assetName } | Select-Object -First 1)
        if ($asset) { break }
    }
    if (-not $asset) {
        throw "Could not find a NixOS-WSL asset for $Architecture in the latest release for $Repository. Tried: $($assetNames -join ', ')."
    }
    [pscustomobject]@{
        name = [string]$asset.name
        uri = [string]$asset.browser_download_url
        tag = [string]$release.tag_name
        architecture = [string]$Architecture
    }
}

function Install-WinMintNixOsWslDistribution {
    param([Parameter(Mandatory)][string]$WslPath)

    $cacheRoot = Join-Path $env:LOCALAPPDATA 'WinMint\cache\wsl\NixOS-WSL'
    $null = New-Item -ItemType Directory -Path $cacheRoot -Force
    $release = Get-WinMintNixOsWslReleaseAssetUri -Architecture (Get-AgentProcessorArchitecture)
    $assetPath = Join-Path $cacheRoot $release.name
    if (-not (Test-Path -LiteralPath $assetPath)) {
        Invoke-WebRequest -Uri $release.uri -OutFile $assetPath -Headers @{ 'User-Agent' = 'WinMint' } -ErrorAction Stop
    }

    Invoke-AgentNative -FilePath $WslPath -ArgumentList @('--install', '--from-file', $assetPath)
}

function Test-WinMintWslRetryableVirtualizationError {
    param([Parameter(Mandatory)][string]$Message)

    return ($Message -match 'HCS_E_HYPERV_NOT_INSTALLED' -or
        $Message -match 'virtualization is not enabled' -or
        $Message -match 'Please enable the Virtual Machine Platform Windows feature and ensure virtualization is enabled in the BIOS' -or
        $Message -match 'HYPERV_NOT_INSTALLED' -or
        $Message -match 'could not be started because a required feature is not installed')
}

function Test-WinMintHyperVGuestWithoutNestedVirtualization {
    try {
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $isHyperVGuest = ([string]$computer.Manufacturer -match 'Microsoft' -and [string]$computer.Model -match 'Virtual Machine')
        if (-not $isHyperVGuest) { return $false }

        $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
        if ($processors.Count -eq 0) { return $false }

        $virtualizationExposed = $false
        foreach ($processor in $processors) {
            $vmMonitorMode = if ($processor.PSObject.Properties['VMMonitorModeExtensions']) { [bool]$processor.VMMonitorModeExtensions } else { $false }
            $firmwareEnabled = if ($processor.PSObject.Properties['VirtualizationFirmwareEnabled']) { [bool]$processor.VirtualizationFirmwareEnabled } else { $false }
            $slat = if ($processor.PSObject.Properties['SecondLevelAddressTranslationExtensions']) { [bool]$processor.SecondLevelAddressTranslationExtensions } else { $false }
            if ($vmMonitorMode -and $firmwareEnabled -and $slat) {
                $virtualizationExposed = $true
                break
            }
        }

        return (-not $virtualizationExposed)
    }
    catch {
        Write-AgentLog "WSL nested virtualization probe warning: $($_.Exception.Message)"
        return $false
    }
}

function New-WinMintNestedVirtualizationMessage {
    return (
        'WSL2 distro installation skipped: this Windows install is running inside a Hyper-V VM, ' +
        'but nested virtualization is not exposed. On the Hyper-V host, run: ' +
        'Set-VMProcessor -VMName "<vm name>" -ExposeVirtualizationExtensions $true, then fully shut down and start the VM.'
    )
}

function New-WinMintWslConfigContent {
    @'
# Managed by WinMint. Edit or delete this file if you want different WSL defaults.
[wsl2]
networkingMode=nat
dnsTunneling=true
autoProxy=true
localhostForwarding=true
firewall=true

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
'@.Trim() + [Environment]::NewLine
}

function Install-WinMintWslConfig {
    param([string]$Path = (Join-Path $env:USERPROFILE '.wslconfig'))

    $content = New-WinMintWslConfigContent
    if (Test-Path -LiteralPath $Path) {
        $existing = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
        if ($existing -eq $content) {
            Write-AgentLog ".wslconfig already matches WinMint WSL2-first defaults: $Path"
            return 'already-current'
        }
        if ($existing -notmatch 'Managed by WinMint') {
            Write-AgentLog "Preserving existing user .wslconfig: $Path"
            return 'preserved-existing'
        }
    }

    $content | Set-Content -LiteralPath $Path -Encoding UTF8
    Write-AgentLog "Wrote WSL2-first .wslconfig: $Path"
    return 'written'
}

function Get-WinMintWslTerminalIconPath {
    param([Parameter(Mandatory)][string]$Distro)

    $terminalLocalState = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
    $iconRoot = Join-Path $terminalLocalState 'Icons'
    switch ($Distro) {
        'Ubuntu' { return (Join-Path $iconRoot 'ubuntu.png') }
        'FedoraLinux' { return (Join-Path $iconRoot 'fedora.png') }
        'archlinux' { return (Join-Path $iconRoot 'archlinux.png') }
        'NixOS' { return (Join-Path $iconRoot 'nixos.png') }
        'pengwin' { return (Join-Path $iconRoot 'pengwin.png') }
        default { throw "Unsupported WSL distro icon mapping: $Distro" }
    }
}

function New-WinMintWslTerminalProfile {
    param([Parameter(Mandatory)][string]$Distro)

    $commandDistro = switch ($Distro) {
        'Ubuntu' { 'Ubuntu' }
        'FedoraLinux' { 'FedoraLinux' }
        'archlinux' { 'archlinux' }
        'NixOS' { 'NixOS' }
        'pengwin' { 'pengwin' }
        default { throw "Unsupported WSL distro profile mapping: $Distro" }
    }

    $displayName = switch ($Distro) {
        'Ubuntu' { 'Ubuntu' }
        'FedoraLinux' { 'Fedora' }
        'archlinux' { 'Arch Linux' }
        'NixOS' { 'NixOS' }
        'pengwin' { 'Pengwin' }
        default { $Distro }
    }

    $guid = switch ($Distro) {
        'Ubuntu' { '{9f23b5e0-8f73-4a90-9d8d-11e8b43d0001}' }
        'FedoraLinux' { '{9f23b5e0-8f73-4a90-9d8d-11e8b43d0002}' }
        'archlinux' { '{9f23b5e0-8f73-4a90-9d8d-11e8b43d0003}' }
        'NixOS' { '{9f23b5e0-8f73-4a90-9d8d-11e8b43d0004}' }
        'pengwin' { '{9f23b5e0-8f73-4a90-9d8d-11e8b43d0005}' }
        default { throw "Unsupported WSL distro profile GUID mapping: $Distro" }
    }

    $iconPath = Get-WinMintWslTerminalIconPath -Distro $Distro
    $terminalProfile = [ordered]@{
        guid = $guid
        name = $displayName
        commandline = "wsl.exe -d $commandDistro"
        startingDirectory = '%USERPROFILE%'
    }
    if (Test-Path -LiteralPath $iconPath) {
        $terminalProfile.icon = $iconPath
    }
    else {
        Write-AgentLog "WSL terminal icon missing; profile will fall back to the terminal default icon: $iconPath"
    }

    return $terminalProfile
}

function New-WinMintWindowsTerminalPowerShellProfile {
    [ordered]@{
        guid = '{2c7d8c64-fb18-43d0-9bd0-bf9f6d5c4e22}'
        name = 'PowerShell'
        commandline = '"%ProgramFiles%\PowerShell\7\pwsh.exe" -NoLogo'
        icon = '%ProgramFiles%\PowerShell\7\pwsh.exe'
        startingDirectory = '%USERPROFILE%'
    }
}

function Install-WinMintWindowsTerminalWslProfiles {
    param([Parameter(Mandatory)][string[]]$Distros)

    $distros = @($Distros | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)

    $settingsPath = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        Write-AgentLog "Windows Terminal settings file not found; skipping WSL profile wiring: $settingsPath"
        return 'missing-terminal-settings'
    }

    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -AsHashtable
    if (-not $settings.ContainsKey('profiles')) {
        $settings.profiles = [ordered]@{}
    }
    if (-not $settings.profiles.ContainsKey('defaults')) {
        $settings.profiles.defaults = [ordered]@{}
    }
    if (-not $settings.profiles.defaults.ContainsKey('font')) {
        $settings.profiles.defaults.font = [ordered]@{}
    }
    $settings.profiles.defaults.font.face = 'Cascadia Code NF'
    $settings.profiles.defaults.colorScheme = 'One Half Dark'
    $settings.profiles.defaults.bellStyle = 'none'
    $settings.centerOnLaunch = $true
    if (-not $settings.profiles.ContainsKey('list')) {
        $settings.profiles.list = @()
    }
    $settings.defaultProfile = '{2c7d8c64-fb18-43d0-9bd0-bf9f6d5c4e22}'
    $settings.disabledProfileSources = @(
        'Windows.Terminal.WindowsPowerShell',
        'Windows.Terminal.PowershellCore',
        'Windows.Terminal.Azure',
        'Windows.Terminal.SSH',
        'Windows.Terminal.Wsl'
    )
    $settings.newTabMenu = @(
        [ordered]@{ type = 'remainingProfiles' }
    )

    $terminalProfiles = [System.Collections.Generic.List[object]]::new()
    $terminalProfiles.Add((New-WinMintWindowsTerminalPowerShellProfile))

    foreach ($distro in $distros) {
        $terminalProfiles.Add((New-WinMintWslTerminalProfile -Distro $distro))
    }

    $settings.profiles.list = @($terminalProfiles)
    $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    Write-AgentLog "Updated Windows Terminal WSL profiles: $($distros -join ', ')"
    if ($distros.Count -eq 0) { return 'updated-base-only' }
    return 'updated'
}

function Update-WinMintWslRuntime {
    param([Parameter(Mandatory)][string]$WslPath)

    Write-AgentConsoleLine -Level Info -Message 'Updating the WSL runtime.'
    Invoke-AgentNative -FilePath $WslPath -ArgumentList @('--update', '--web-download')
}

function Invoke-WinMintAgentWslBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    [void]$State
    $cfg = if ($AgentProfile.modules -and $AgentProfile.modules.PSObject.Properties['wsl']) {
        $AgentProfile.modules.wsl
    } else {
        $null
    }
    $distros = @()
    if ($cfg -and $cfg.PSObject.Properties['distros']) {
        $distros = @($cfg.distros)
    } elseif ($cfg -and $cfg.PSObject.Properties['distro']) {
        $distros = @([string]$cfg.distro)
    }
    $distros = @(
        $distros |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and [string]$_ -ne 'None' } |
            ForEach-Object { ([string]$_) -split ',' } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and [string]$_ -ne 'None' } |
            ForEach-Object { Convert-WinMintWslDistroAlias -Distro ([string]$_) } |
            Select-Object -Unique
    )
    $requestedDistros = @($distros | Select-Object -Unique)
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $wsl) { throw 'wsl.exe was not found after WSL feature enablement.' }

    $wslConfigStatus = Install-WinMintWslConfig
    $messages = [System.Collections.Generic.List[string]]::new()
    if ($wslConfigStatus) { $messages.Add(".wslconfig: $wslConfigStatus") }

    if (Test-WinMintHyperVGuestWithoutNestedVirtualization) {
        $nestedMessage = New-WinMintNestedVirtualizationMessage
        Write-AgentLog $nestedMessage
        $messages.Add($nestedMessage)
        try {
            $terminalStatus = Install-WinMintWindowsTerminalWslProfiles -Distros $distros
            if ($terminalStatus) { $messages.Add("Windows Terminal WSL profiles: $terminalStatus") }
        }
        catch {
            Write-AgentLog "Windows Terminal WSL profile update warning: $($_.Exception.Message)"
            $messages.Add('Windows Terminal WSL profiles not updated.')
        }
        [pscustomobject]@{
            Id      = 'wsl'
            Status  = 'skipped'
            Message = $messages -join '; '
        }
        return
    }

    $needsReboot = $false
    $wslRuntimeUpdated = $true

    try {
        Update-WinMintWslRuntime -WslPath $wsl.Source
    }
    catch {
        $needsReboot = $true
        $wslRuntimeUpdated = $false
        Write-AgentLog "WSL update warning: $($_.Exception.Message)"
    }

    try {
        Write-AgentConsoleLine -Level Info -Message 'Setting WSL 2 as the default version.'
        Invoke-AgentNative -FilePath $wsl.Source -ArgumentList @('--set-default-version', '2')
    }
    catch {
        $needsReboot = $true
        Write-AgentLog "WSL default-version warning: $($_.Exception.Message)"
    }

    $installedNow = [System.Collections.Generic.List[string]]::new()
    $alreadyInstalled = [System.Collections.Generic.List[string]]::new()
    $missing = @()
    if ($requestedDistros.Count -gt 0 -and $wslRuntimeUpdated) {
        $onlineNames = @(Get-WinMintOnlineWslDistributions -WslPath $wsl.Source)
        $resolvedMap = @{}
        foreach ($requested in $requestedDistros) {
            $resolvedMap[$requested] = Resolve-WinMintWslDistro -Distro $requested -OnlineNames $onlineNames
        }
        $distros = @($distros | ForEach-Object { $resolvedMap[$_] } | Select-Object -Unique)

        $installed = @(& $wsl.Source --list --quiet 2>$null | ForEach-Object { ([string]$_ -replace "`0", '').Trim() })
        foreach ($distro in $distros) {
            if ($installed -contains $distro) {
                $alreadyInstalled.Add($distro)
                continue
            }
            try {
                if ($distro -eq 'NixOS') {
                    Install-WinMintNixOsWslDistribution -WslPath $wsl.Source
                }
                else {
                    Invoke-AgentNative -FilePath $wsl.Source -ArgumentList @('--install', '--no-launch', '-d', $distro)
                }
                $installedNow.Add($distro)
            }
            catch {
                if (Test-WinMintWslRetryableVirtualizationError -Message $_.Exception.Message) {
                    $needsReboot = $true
                    Write-AgentLog "WSL install for '$distro' reported retryable virtualization state: $($_.Exception.Message)"
                    $missing = @($missing + $distro)
                    continue
                }
                throw
            }
        }

        # Re-list to verify the requested distros actually registered. On a fresh
        # ARM64 install, `wsl --install` often returns 0 but the distro doesn't
        # appear until the VirtualMachinePlatform kernel component initialises after
        # a reboot. If anything we just tried to install is still missing, return
        # needsReboot — Invoke-AgentProfileModule writes that to state.json and the
        # next agent run (after reboot) re-attempts.
        $postInstall = @(& $wsl.Source --list --quiet 2>$null | ForEach-Object { ([string]$_ -replace "`0", '').Trim() })
        $missing = @($installedNow | Where-Object { $postInstall -notcontains $_ })
    }
    elseif ($requestedDistros.Count -gt 0 -and -not $wslRuntimeUpdated) {
        $messages.Add('WSL runtime update pending; distro installs deferred until the next first-logon run.')
    }

    if ($installedNow.Count -gt 0) { $messages.Add("Installed WSL distro(s): $($installedNow -join ', ')") }
    if ($alreadyInstalled.Count -gt 0) { $messages.Add("Already installed: $($alreadyInstalled -join ', ')") }
    if ($missing.Count -gt 0) { $messages.Add("Reboot required to finish registering: $($missing -join ', ')") }
    if ($requestedDistros.Count -eq 0) { $messages.Add('WSL2 configured; no distro selected.') }

    try {
        $terminalStatus = Install-WinMintWindowsTerminalWslProfiles -Distros $distros
        if ($terminalStatus) { $messages.Add("Windows Terminal WSL profiles: $terminalStatus") }
    }
    catch {
        Write-AgentLog "Windows Terminal WSL profile update warning: $($_.Exception.Message)"
        $messages.Add('Windows Terminal WSL profiles not updated.')
    }

    [pscustomobject]@{
        Id      = 'wsl'
        Status  = (($missing.Count -gt 0) -or $needsReboot) ? 'needsReboot' : 'ok'
        Message = $messages -join '; '
    }
}

