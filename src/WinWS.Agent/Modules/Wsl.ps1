#Requires -Version 7.3

function Convert-WinWSWslDistroAlias {
    param([string]$Distro)

    $value = ([string]$Distro).Trim()
    switch -Regex ($value) {
        '^Ubuntu-\d+\.\d+$' { return 'Ubuntu' }
        default             { return $value }
    }
}

function Get-WinWSOnlineWslDistributions {
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

function Resolve-WinWSWslDistro {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [string[]]$OnlineNames = @()
    )

    $alias = Convert-WinWSWslDistroAlias -Distro $Distro
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

function New-WinWSWslConfigContent {
    @'
# Managed by WinWS. Edit or delete this file if you want different WSL defaults.
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

function Install-WinWSWslConfig {
    param([string]$Path = (Join-Path $env:USERPROFILE '.wslconfig'))

    $content = New-WinWSWslConfigContent
    if (Test-Path -LiteralPath $Path) {
        $existing = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
        if ($existing -eq $content) {
            Write-AgentLog ".wslconfig already matches WinWS WSL2-first defaults: $Path"
            return 'already-current'
        }
        if ($existing -notmatch 'Managed by WinWS') {
            Write-AgentLog "Preserving existing user .wslconfig: $Path"
            return 'preserved-existing'
        }
    }

    $content | Set-Content -LiteralPath $Path -Encoding UTF8
    Write-AgentLog "Wrote WSL2-first .wslconfig: $Path"
    return 'written'
}

function Invoke-WinWSAgentWslBootstrap {
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
            ForEach-Object { Convert-WinWSWslDistroAlias -Distro ([string]$_) } |
            Select-Object -Unique
    )
    $requestedDistros = @($distros | Select-Object -Unique)
    if ($requestedDistros.Count -eq 0) {
        return [pscustomobject]@{
            Id      = 'wsl'
            Status  = 'skipped'
            Message = 'No WSL distros selected.'
        }
    }

    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $wsl) { throw 'wsl.exe was not found after WSL feature enablement.' }

    $wslConfigStatus = Install-WinWSWslConfig

    try {
        Invoke-AgentNative -FilePath $wsl.Source -ArgumentList @('--set-default-version', '2')
    }
    catch {
        Write-AgentLog "WSL default-version warning: $($_.Exception.Message)"
    }

    $onlineNames = @(Get-WinWSOnlineWslDistributions -WslPath $wsl.Source)
    $resolvedMap = @{}
    foreach ($requested in $requestedDistros) {
        $resolvedMap[$requested] = Resolve-WinWSWslDistro -Distro $requested -OnlineNames $onlineNames
    }
    $distros = @($distros | ForEach-Object { $resolvedMap[$_] } | Select-Object -Unique)

    $installed = @(& $wsl.Source --list --quiet 2>$null | ForEach-Object { ([string]$_ -replace "`0", '').Trim() })
    $installedNow = [System.Collections.Generic.List[string]]::new()
    $alreadyInstalled = [System.Collections.Generic.List[string]]::new()
    foreach ($distro in $distros) {
        if ($installed -contains $distro) {
            $alreadyInstalled.Add($distro)
            continue
        }
        Invoke-AgentNative -FilePath $wsl.Source -ArgumentList @('--install', '--no-launch', '-d', $distro)
        $installedNow.Add($distro)
    }

    # Re-list to verify the requested distros actually registered. On a fresh
    # ARM64 install, `wsl --install` often returns 0 but the distro doesn't
    # appear until the VirtualMachinePlatform kernel component initialises after
    # a reboot. If anything we just tried to install is still missing, return
    # needsReboot — Invoke-AgentProfileModule writes that to state.json and the
    # next agent run (after reboot) re-attempts.
    $postInstall = @(& $wsl.Source --list --quiet 2>$null | ForEach-Object { ([string]$_ -replace "`0", '').Trim() })
    $missing = @($installedNow | Where-Object { $postInstall -notcontains $_ })

    $messages = [System.Collections.Generic.List[string]]::new()
    if ($installedNow.Count -gt 0) { $messages.Add("Installed WSL distro(s): $($installedNow -join ', ')") }
    if ($alreadyInstalled.Count -gt 0) { $messages.Add("Already installed: $($alreadyInstalled -join ', ')") }
    if ($wslConfigStatus) { $messages.Add(".wslconfig: $wslConfigStatus") }
    if ($missing.Count -gt 0) { $messages.Add("Reboot required to finish registering: $($missing -join ', ')") }

    [pscustomobject]@{
        Id      = 'wsl'
        Status  = ($missing.Count -gt 0) ? 'needsReboot' : 'ok'
        Message = $messages -join '; '
    }
}
