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

function Set-WinMintWslOobeComplete {
    # Suppress Welcome-to-WSL first-run UI (Microsoft WindowsDeveloperConfig InstallUbuntu pattern).
    $lxssPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path -LiteralPath $lxssPath)) {
        New-Item -Path $lxssPath -Force | Out-Null
    }
    Set-ItemProperty -Path $lxssPath -Name 'OOBEComplete' -Value 1 -Type DWord -Force
    Write-AgentLog 'Stamped Lxss OOBEComplete=1 to suppress Welcome-to-WSL UI.'
}

function Invoke-WinMintWslInstallProcess {
    param(
        [Parameter(Mandatory)][string]$WslPath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [string]$ProgressMessage = ''
    )

    # Launch without -NoNewWindow and without RedirectStandard* so Start-Process
    # allocates CREATE_NEW_CONSOLE. Console-less hosts + redirected Start-Process
    # make wsl --install fail with "The Windows Subsystem for Linux is not installed".
    $runningMessage = if (-not [string]::IsNullOrWhiteSpace($ProgressMessage)) {
        $ProgressMessage.Trim()
    }
    else {
        "Running wsl $($ArgumentList -join ' ')."
    }
    Write-AgentLog "RUN $WslPath $($ArgumentList -join ' ') (WslInstallProcess, no redirect)"
    Write-AgentEvent -Type 'command' -Status 'running' -Message $runningMessage -Data @{
        filePath    = $WslPath
        displayArgs = ($ArgumentList -join ' ')
    }
    $p = Start-Process -FilePath $WslPath -ArgumentList $ArgumentList -Wait -PassThru
    $exitCode = [int]$p.ExitCode
    if ($exitCode -ne 0) {
        Write-AgentEvent -Type 'command' -Status 'failed' -Message "wsl.exe exited $exitCode." -Data @{
            filePath = $WslPath
            exitCode = $exitCode
        }
        throw "$WslPath $($ArgumentList -join ' ') exited $exitCode."
    }
    Write-AgentEvent -Type 'command' -Status 'ok' -Message 'wsl.exe completed.' -Data @{
        filePath = $WslPath
        exitCode = $exitCode
    }
}

function Get-WinMintWslListOutput {
    param(
        [Parameter(Mandatory)][string]$WslPath,
        [Parameter(Mandatory)][string[]]$ArgumentList
    )

    # Isolate wsl.exe from the PowerShell host: call-operator leaks non-zero
    # $LASTEXITCODE / stderr into the session; Start-Process does not.
    $previousUtf8 = $env:WSL_UTF8
    $env:WSL_UTF8 = '1'
    $out = [System.IO.Path]::GetTempFileName()
    $err = [System.IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $WslPath -ArgumentList $ArgumentList `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $out -RedirectStandardError $err
        if ($p.ExitCode -ne 0) {
            return @()
        }
        return @(
            Get-Content -LiteralPath $out -Encoding utf8 -ErrorAction SilentlyContinue |
                ForEach-Object { ([string]$_ -replace "`0", '').Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
    }
    finally {
        Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue
        if ($null -eq $previousUtf8) {
            Remove-Item -Path Env:WSL_UTF8 -ErrorAction SilentlyContinue
        }
        else {
            $env:WSL_UTF8 = $previousUtf8
        }
    }
}

function Get-WinMintWslInstalledDistributions {
    param([Parameter(Mandatory)][string]$WslPath)

    return @(Get-WinMintWslListOutput -WslPath $WslPath -ArgumentList @('--list', '--quiet'))
}

function Get-WinMintOnlineWslDistributions {
    param([Parameter(Mandatory)][string]$WslPath)

    try {
        $lines = @(Get-WinMintWslListOutput -WslPath $WslPath -ArgumentList @('--list', '--online'))
    }
    catch {
        Write-AgentLog "WSL online catalog warning: $($_.Exception.Message)"
        return @()
    }

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        $clean = ([string]$line).Trim()
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

    Set-WinMintWslOobeComplete
    Invoke-WinMintWslInstallProcess -WslPath $WslPath -ArgumentList @('--install', '--from-file', $assetPath) `
        -ProgressMessage 'Installing NixOS'
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

function ConvertTo-WinMintLinuxNameToken {
    param(
        [string]$Value,
        [string]$Fallback = 'winmint',
        [int]$MaxLength = 32
    )

    $token = ([string]$Value).Trim().ToLowerInvariant()
    $token = $token -replace '[^a-z0-9_-]', '-'
    $token = $token -replace '-+', '-'
    $token = $token.Trim('-')
    if ([string]::IsNullOrWhiteSpace($token)) { $token = $Fallback }
    if ($token -match '^[0-9]') { $token = "u$token" }
    if ($token -notmatch '^[a-z_]') { $token = "u$token" }
    if ($token.Length -gt $MaxLength) {
        $token = $token.Substring(0, $MaxLength).TrimEnd('-')
    }
    if ([string]::IsNullOrWhiteSpace($token)) { $token = $Fallback }
    return $token
}

function ConvertTo-WinMintLinuxUserName {
    param([string]$AccountName)

    return (ConvertTo-WinMintLinuxNameToken -Value $AccountName -Fallback 'winmint' -MaxLength 32)
}

function ConvertTo-WinMintWslDistroHostnameSlug {
    param([Parameter(Mandatory)][string]$Distro)

    switch -Regex ([string]$Distro) {
        '^(?i)Ubuntu' { return 'ubuntu' }
        '^(?i)Fedora' { return 'fedora' }
        '^(?i)archlinux' { return 'archlinux' }
        '^(?i)pengwin' { return 'pengwin' }
        '^(?i)NixOS' { return 'nixos' }
        default { return (ConvertTo-WinMintLinuxNameToken -Value $Distro -Fallback 'linux' -MaxLength 24) }
    }
}

function ConvertTo-WinMintWslHostname {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$Distro
    )

    $hostPart = ConvertTo-WinMintLinuxNameToken -Value $ComputerName -Fallback 'winmint' -MaxLength 32
    $slug = ConvertTo-WinMintWslDistroHostnameSlug -Distro $Distro
    $name = "$hostPart-$slug"
    if ($name.Length -gt 63) {
        $name = $name.Substring(0, 63).TrimEnd('-')
    }
    return $name
}

function Get-WinMintWslCoreIdentity {
    param([Parameter(Mandatory)][object]$AgentProfile)

    $identity = $null
    if ($AgentProfile -is [System.Collections.IDictionary]) {
        if ($AgentProfile.Contains('identity')) { $identity = $AgentProfile['identity'] }
    }
    elseif ($AgentProfile.PSObject.Properties['identity']) {
        $identity = $AgentProfile.identity
    }

    $accountName = ''
    $computerName = ''
    if ($null -ne $identity) {
        if ($identity -is [System.Collections.IDictionary]) {
            if ($identity.Contains('accountName')) { $accountName = [string]$identity['accountName'] }
            if ($identity.Contains('computerName')) { $computerName = [string]$identity['computerName'] }
        }
        else {
            if ($identity.PSObject.Properties['accountName']) { $accountName = [string]$identity.accountName }
            if ($identity.PSObject.Properties['computerName']) { $computerName = [string]$identity.computerName }
        }
    }
    if ([string]::IsNullOrWhiteSpace($accountName)) { $accountName = [string]$env:USERNAME }
    if ([string]::IsNullOrWhiteSpace($computerName)) { $computerName = [string]$env:COMPUTERNAME }

    [pscustomobject]@{
        AccountName  = $accountName
        ComputerName = $computerName
        LinuxUser    = (ConvertTo-WinMintLinuxUserName -AccountName $accountName)
    }
}

function New-WinMintWslConfContent {
    param(
        [Parameter(Mandatory)][string]$LinuxUser,
        [Parameter(Mandatory)][string]$Hostname
    )

    @"
# Managed by WinMint. Re-runs replace this file.

[boot]
systemd=true

[user]
default=$LinuxUser

[interop]
enabled=true
appendWindowsPath=false

[automount]
enabled=true
mountFsTab=true
options=metadata,umask=22,fmask=11,case=off

[network]
hostname=$Hostname
generateHosts=true
generateResolvConf=true

[time]
useWindowsTimezone=true
"@.Trim() + [Environment]::NewLine
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

# Per-distro /etc/wsl.conf is written by Install-WinMintWslDistroCore after each
# selected distro registers (default user, hostname=<computerName>-<distroSlug>,
# systemd, interop, automount). Host .wslconfig stays global WSL2 VM settings only.
'@.Trim() + [Environment]::NewLine
}

function Invoke-WinMintWslDistroRoot {
    param(
        [Parameter(Mandatory)][string]$WslPath,
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string[]]$ArgumentList
    )

    $previousUtf8 = $env:WSL_UTF8
    $env:WSL_UTF8 = '1'
    $out = [System.IO.Path]::GetTempFileName()
    $err = [System.IO.Path]::GetTempFileName()
    $args = @('-d', $Distro, '-u', 'root', '--') + @($ArgumentList)
    try {
        Write-AgentLog "RUN $WslPath $($args -join ' ') (WslDistroRoot)"
        $p = Start-Process -FilePath $WslPath -ArgumentList $args `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $out -RedirectStandardError $err
        $stdout = ''
        $stderr = ''
        try { if (Test-Path -LiteralPath $out) { $stdout = (Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue) } } catch {}
        try { if (Test-Path -LiteralPath $err) { $stderr = (Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue) } } catch {}
        if ($p.ExitCode -ne 0) {
            $detail = (@($stdout, $stderr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine
            throw "wsl -d $Distro -u root exited $($p.ExitCode). $detail"
        }
        return $stdout
    }
    finally {
        Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue
        if ($null -eq $previousUtf8) {
            Remove-Item -Path Env:WSL_UTF8 -ErrorAction SilentlyContinue
        }
        else {
            $env:WSL_UTF8 = $previousUtf8
        }
    }
}

function Install-WinMintWslDistroCore {
    param(
        [Parameter(Mandatory)][string]$WslPath,
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$LinuxUser,
        [Parameter(Mandatory)][string]$Hostname
    )

    if ($Distro -eq 'NixOS') {
        Write-AgentLog "WSL core skipped for NixOS ($Distro): declarative distro; no in-distro user/wsl.conf mutation."
        return 'skipped-nixos'
    }

    $conf = New-WinMintWslConfContent -LinuxUser $LinuxUser -Hostname $Hostname
    $confUnix = $conf -replace "`r`n", "`n" -replace "`r", "`n"
    $confB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($confUnix))
    $userB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($LinuxUser))

    # Idempotent: create login user (bash), add sudo/wheel, write managed /etc/wsl.conf.
    # No password sync and no NOPASSWD — set a password later via: wsl -d DISTRO -u root -- passwd USER
    $script = @"
set -eu
USER_NAME=`$(printf '%s' '$userB64' | base64 -d)
CONF_B64='$confB64'
if ! id "`$USER_NAME" >/dev/null 2>&1; then
  if command -v useradd >/dev/null 2>&1; then
    useradd -m -s /bin/bash "`$USER_NAME"
  elif command -v adduser >/dev/null 2>&1; then
    adduser --disabled-password --gecos '' --shell /bin/bash "`$USER_NAME"
  else
    echo "WinMint WSL core: neither useradd nor adduser found" >&2
    exit 1
  fi
fi
ADMIN_GROUP=sudo
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  case "`${ID:-}" in
    fedora|rhel|centos|rocky|almalinux|arch|manjaro) ADMIN_GROUP=wheel ;;
  esac
fi
if getent group "`$ADMIN_GROUP" >/dev/null 2>&1; then
  usermod -aG "`$ADMIN_GROUP" "`$USER_NAME"
elif getent group sudo >/dev/null 2>&1; then
  usermod -aG sudo "`$USER_NAME"
elif getent group wheel >/dev/null 2>&1; then
  usermod -aG wheel "`$USER_NAME"
fi
printf '%s' "`$CONF_B64" | base64 -d > /etc/wsl.conf
chmod 644 /etc/wsl.conf
"@
    $scriptUnix = ($script -replace "`r`n", "`n" -replace "`r", "`n").Trim() + "`n"
    $scriptB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($scriptUnix))

    Invoke-WinMintWslDistroRoot -WslPath $WslPath -Distro $Distro -ArgumentList @(
        'bash', '-lc', "echo $scriptB64 | base64 -d | bash"
    ) | Out-Null

    Write-AgentLog "WSL core applied for $Distro (user=$LinuxUser hostname=$Hostname)."
    return 'applied'
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

        $installed = @(Get-WinMintWslInstalledDistributions -WslPath $wsl.Source)
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
                    Set-WinMintWslOobeComplete
                    Invoke-WinMintWslInstallProcess -WslPath $wsl.Source -ArgumentList @('--install', '--no-launch', '-d', $distro) `
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
        $postInstall = @(Get-WinMintWslInstalledDistributions -WslPath $wsl.Source)
        $missing = @($installedNow | Where-Object { $postInstall -notcontains $_ })

        # WSL core: managed /etc/wsl.conf + default user for each registered distro.
        $coreIdentity = Get-WinMintWslCoreIdentity -AgentProfile $AgentProfile
        $coreApplied = $false
        foreach ($distro in $distros) {
            if ($missing -contains $distro) { continue }
            if ($postInstall -notcontains $distro) { continue }
            if ($distro -eq 'NixOS') {
                $messages.Add('WSL core skipped for NixOS (declarative; no in-distro mutation).')
                continue
            }
            try {
                $hostname = ConvertTo-WinMintWslHostname -ComputerName $coreIdentity.ComputerName -Distro $distro
                $coreStatus = Install-WinMintWslDistroCore -WslPath $wsl.Source -Distro $distro `
                    -LinuxUser $coreIdentity.LinuxUser -Hostname $hostname
                if ($coreStatus -eq 'applied') {
                    $coreApplied = $true
                    $messages.Add("WSL core: $distro user=$($coreIdentity.LinuxUser) hostname=$hostname")
                }
            }
            catch {
                Write-AgentLog "WSL core warning for '$distro': $($_.Exception.Message)"
                $messages.Add("WSL core warning for ${distro}: $($_.Exception.Message)")
            }
        }
        if ($coreApplied) {
            try {
                Write-AgentLog 'Shutting down WSL so managed /etc/wsl.conf takes effect.'
                Invoke-AgentNative -FilePath $wsl.Source -ArgumentList @('--shutdown') -NoRedirect
            }
            catch {
                Write-AgentLog "WSL shutdown warning after core setup: $($_.Exception.Message)"
            }
        }
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

