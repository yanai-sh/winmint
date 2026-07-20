#Requires -Version 7.6

$setupScriptsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$terminalProfilesScript = Join-Path $setupScriptsRoot 'WindowsTerminal.Profiles.ps1'
if (-not (Test-Path -LiteralPath $terminalProfilesScript)) {
    $terminalProfilesScript = Join-Path (Split-Path -Parent $setupScriptsRoot) 'setup\WindowsTerminal.Profiles.ps1'
}
. $terminalProfilesScript

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

function Complete-WinMintAgentWslAdvisorySkip {
    param(
        [string[]]$Distros = @(),
        [Parameter(Mandatory)][string]$Reason,
        [string[]]$Messages = @()
    )

    $messages = [System.Collections.Generic.List[string]]::new()
    foreach ($message in @($Messages)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$message)) {
            $messages.Add([string]$message)
        }
    }
    Write-AgentLog $Reason
    $messages.Add($Reason)
    $selectedDistros = @($Distros | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($selectedDistros.Count -gt 0) {
        try {
            # Advisory skip means distros were not installed — still stage curated
            # Terminal profiles (mock) so VM smoke shows Fedora/etc. in the dropdown.
            $terminalStatus = Set-WinMintWindowsTerminalProfiles -WslDistros @($selectedDistros) -MockWslProfiles
            if ($terminalStatus) { $messages.Add("Windows Terminal defaults: $terminalStatus") }
        }
        catch {
            Write-AgentLog "Windows Terminal defaults update warning: $($_.Exception.Message)"
            $messages.Add('Windows Terminal defaults not updated.')
        }
    }
    [pscustomobject]@{
        Id      = 'wsl'
        Status  = 'skipped'
        Message = ($messages -join '; ')
    }
}

function New-WinMintWslConfigContent {
    @'
# Managed by WinMint. Edit or delete this file if you want different WSL defaults.
[wsl2]
# memory is an absolute size only (no % syntax). Omitting it → 50% RAM / 25% swap, per-machine = portable.
pageReporting=true
networkingMode=mirrored
dnsTunneling=true
firewall=true
# NAT-only — uncomment if you switch networkingMode back to nat, then wsl --shutdown:
# localhostForwarding=true  # ignored when networkingMode=mirrored
# autoProxy=true            # redundant with mirrored; can force NAT fallback with localhost proxies
# nestedVirtualization omitted — ARM64 no-op.

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true

# --- Reference: /etc/wsl.conf (per-distro, inside Linux — WinMint does not create this file) ---
# Copy or adapt into each distro after first launch (e.g. sudo tee /etc/wsl.conf), then wsl --shutdown.
#
# [boot]
# systemd=true
# # Prefer systemd units for services; use `command=` only for early root one-shots.
#
# [user]
# default=<your-username>
#
# [interop]
# enabled=true                 # still allow launching Windows .exe by full path
# appendWindowsPath=false      # keep the Windows PATH off the Linux $PATH (faster exec, no pollution)
#
# [automount]
# enabled=true
# mountFsTab=true              # honor /etc/fstab (SMB / extra mounts)
# options=metadata,umask=22,fmask=11,case=off   # real Linux perms on /mnt/c; no more 777-everything
#
# [network]
# generateHosts=true
# generateResolvConf=true      # WSL-managed DNS (pairs with host-side dnsTunneling)
#
# [gpu]
# enabled=true                 # ARM64 GPU para-virtualization (D3D12/Dozen)
#
# [time]
# useWindowsTimezone=true
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

function Update-WinMintWslRuntime {
    param([Parameter(Mandatory)][string]$WslPath)

    Write-AgentUserNotice -Level Info -Message 'Updating the WSL runtime.'
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
    if (Test-WinMintAgentWslRuntimeValidationSkipped -AgentProfile $AgentProfile) {
        $reason = 'WSL runtime validation skipped by profile diagnostics (wslRuntimeValidation=skip).'
        return (Complete-WinMintAgentWslAdvisorySkip -Distros @($distros) -Reason $reason -Messages @(
                if (@($distros).Count -gt 0) { 'terminalProfile=mock (WSL install skipped; Terminal profiles still staged)' }
            ))
    }
    $requestedDistros = @($distros | Select-Object -Unique)
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $wsl) { throw 'wsl.exe was not found after WSL feature enablement.' }

    $wslConfigStatus = Install-WinMintWslConfig
    $messages = [System.Collections.Generic.List[string]]::new()
    if ($wslConfigStatus) { $messages.Add(".wslconfig: $wslConfigStatus") }

    if (Test-WinMintHyperVGuestWithoutNestedVirtualization) {
        return Complete-WinMintAgentWslAdvisorySkip -Distros $distros -Reason (New-WinMintNestedVirtualizationMessage) -Messages @($messages)
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
        Write-AgentUserNotice -Level Info -Message 'Setting WSL 2 as the default version.'
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
                Write-AgentEvent -Type 'install' -Status 'running' -Step "wsl:$distro" -Message "Installing $distro."
                if ($distro -eq 'NixOS') {
                    Install-WinMintNixOsWslDistribution -WslPath $wsl.Source
                }
                else {
                    Invoke-AgentNative -FilePath $wsl.Source -ArgumentList @('--install', '--no-launch', '-d', $distro) `
                        -ProgressMessage "Installing $distro"
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

    if ($distros.Count -gt 0) {
        try {
            $terminalStatus = Set-WinMintWindowsTerminalProfiles -WslDistros @($distros)
            if ($terminalStatus) { $messages.Add("Windows Terminal defaults: $terminalStatus") }
        }
        catch {
            Write-AgentLog "Windows Terminal defaults update warning: $($_.Exception.Message)"
            $messages.Add('Windows Terminal defaults not updated.')
        }
    }

    [pscustomobject]@{
        Id      = 'wsl'
        Status  = (($missing.Count -gt 0) -or $needsReboot) ? 'needsReboot' : 'ok'
        Message = $messages -join '; '
    }
}

