#Requires -Version 7.6

function Update-AgentProcessPath {
    $segments = [System.Collections.Generic.List[string]]::new()
    foreach ($pathValue in @(
            [Environment]::GetEnvironmentVariable('Path', 'Machine'),
            [Environment]::GetEnvironmentVariable('Path', 'User'),
            $env:PATH
        )) {
        foreach ($part in ([string]$pathValue -split ';')) {
            if (-not [string]::IsNullOrWhiteSpace($part)) { $segments.Add($part.Trim()) | Out-Null }
        }
    }

    foreach ($candidate in @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'),
            (Join-Path $env:USERPROFILE 'scoop\shims'),
            (Join-Path $env:ProgramFiles 'PowerShell\7'),
            (Join-Path $env:ProgramFiles 'YASB'),
            (Join-Path $env:ProgramFiles 'komorebi'),
            (Join-Path $env:ProgramFiles 'komorebi\bin'),
            (Join-Path $env:ProgramFiles 'Windhawk')
        )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { $segments.Add($candidate) | Out-Null }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $env:PATH = @(
        $segments |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $seen.Add($_) }
    ) -join ';'
}

function Resolve-AgentPowerShellHost {
    Resolve-WinMintPowerShell7Host
}

function Test-AgentRebootPending {
    foreach ($path in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
            'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
        )) {
        try {
            if (-not (Test-Path -LiteralPath $path)) { continue }
            if ($path -like '*Session Manager') {
                $pending = (Get-ItemProperty -LiteralPath $path -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
                if ($pending) { return $true }
                continue
            }
            return $true
        }
        catch {
            Write-AgentLog "Reboot pending probe warning: $path :: $($_.Exception.Message)"
        }
    }
    return $false
}

function Remove-AgentDesktopShortcuts {
    $desktopPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in @(
            [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory),
            [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonDesktopDirectory),
            (Join-Path $env:PUBLIC 'Desktop')
        )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $desktopPaths.Add($candidate) | Out-Null }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $removed = [System.Collections.Generic.List[string]]::new()
    foreach ($desktopPath in @($desktopPaths | Where-Object { $seen.Add($_) })) {
        if (-not (Test-Path -LiteralPath $desktopPath -PathType Container)) { continue }
        foreach ($shortcut in @(Get-ChildItem -LiteralPath $desktopPath -Filter '*.lnk' -File -Force -ErrorAction SilentlyContinue)) {
            try {
                Remove-Item -LiteralPath $shortcut.FullName -Force -ErrorAction Stop
                $removed.Add($shortcut.FullName) | Out-Null
            }
            catch {
                Write-AgentLog "Desktop shortcut cleanup warning: $($shortcut.FullName) :: $($_.Exception.Message)"
            }
        }
    }

    if ($removed.Count -gt 0) {
        Write-AgentLog "Removed desktop shortcut(s): $($removed -join ', ')"
        Write-AgentEvent -Type 'cleanup' -Status 'ok' -Message 'Removed desktop shortcuts created by installers.' -Data @{
            shortcuts = @($removed)
        }
    }
    else {
        Write-AgentLog 'No desktop shortcuts found after live package installs.'
    }
}

function Test-AgentProcessElevated {
    try {
        return Test-WinMintProcessElevated
    }
    catch {
        Write-AgentLog "Elevation check warning: $($_.Exception.Message)"
        return $false
    }
}

function Get-AgentProcessorArchitecture {
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch -Regex ([string]$arch) {
        '^ARM64$' { return 'arm64' }
        '^(AMD64|IA64)$' { return 'amd64' }
        '^x86$' { return 'x86' }
        default { return ([string]$arch).ToLowerInvariant() }
    }
}

function Get-AgentTargetArchitecture {
    $ctx = Get-WinMintAgentContext
    if (-not [string]::IsNullOrWhiteSpace([string]$ctx.TargetArchitecture)) {
        return ([string]$ctx.TargetArchitecture).ToLowerInvariant()
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$script:AgentTargetArchitecture)) {
        return ([string]$script:AgentTargetArchitecture).ToLowerInvariant()
    }
    return Get-AgentProcessorArchitecture
}

function ConvertTo-AgentWingetArchitecture {
    param([Parameter(Mandatory)][string]$Architecture)
    switch ($Architecture) {
        'amd64' { return 'x64' }
        'arm64' { return 'arm64' }
        'x86' { return 'x86' }
        default { return $null }
    }
}

function Get-AgentToolWingetArchitecture {
    param(
        [Parameter(Mandatory)]$Tool,
        [string]$HostArchitecture = (Get-AgentProcessorArchitecture),
        [string]$TargetArchitecture = (Get-AgentTargetArchitecture)
    )

    $target = ([string]$TargetArchitecture).ToLowerInvariant()
    if ($target -ne 'arm64') {
        return $null
    }

    $nativeWingetArchitecture = ConvertTo-AgentWingetArchitecture -Architecture $target

    if ($Tool.PSObject.Properties['architectures']) {
        $supported = @($Tool.architectures | ForEach-Object { ([string]$_).ToLowerInvariant() })
        if ($supported -contains $target -and $nativeWingetArchitecture) {
            return $nativeWingetArchitecture
        }
    }

    if ($Tool.PSObject.Properties['wingetArchitectureByTarget']) {
        $override = $Tool.wingetArchitectureByTarget.PSObject.Properties[$target]
        if ($override -and -not [string]::IsNullOrWhiteSpace([string]$override.Value)) {
            return [string]$override.Value
        }
    }

    if ($Tool.PSObject.Properties['wingetArchitectureByHost']) {
        $override = $Tool.wingetArchitectureByHost.PSObject.Properties[$HostArchitecture]
        if ($override -and -not [string]::IsNullOrWhiteSpace([string]$override.Value)) {
            return [string]$override.Value
        }
    }

    return $null
}
