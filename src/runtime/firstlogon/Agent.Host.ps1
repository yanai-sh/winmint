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
    $pwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    if (Test-Path -LiteralPath $pwsh) { return $pwsh }
    throw "PowerShell 7 is required for WinMint Agent but was not found: $pwsh"
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
        if (-not ('WinMint.TokenElevation' -as [type])) {
            Add-Type -Namespace WinMint -Name TokenElevation -MemberDefinition @'
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct TOKEN_ELEVATION {
    public int TokenIsElevated;
}
[System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError = true)]
public static extern bool OpenProcessToken(System.IntPtr ProcessHandle, uint DesiredAccess, out System.IntPtr TokenHandle);
[System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError = true)]
public static extern bool GetTokenInformation(System.IntPtr TokenHandle, int TokenInformationClass, out TOKEN_ELEVATION TokenInformation, int TokenInformationLength, out int ReturnLength);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern bool CloseHandle(System.IntPtr hObject);
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern System.IntPtr GetCurrentProcess();
'@
        }
        $TOKEN_QUERY = 0x0008
        $TokenElevation = 20
        $tokenHandle = [IntPtr]::Zero
        if (-not [WinMint.TokenElevation]::OpenProcessToken([WinMint.TokenElevation]::GetCurrentProcess(), [uint32]$TOKEN_QUERY, [ref]$tokenHandle)) {
            return $false
        }
        try {
            $elevation = New-Object WinMint.TokenElevation+TOKEN_ELEVATION
            $returnLength = 0
            $size = [System.Runtime.InteropServices.Marshal]::SizeOf($elevation)
            if ([WinMint.TokenElevation]::GetTokenInformation($tokenHandle, $TokenElevation, [ref]$elevation, $size, [ref]$returnLength)) {
                return ($elevation.TokenIsElevated -ne 0)
            }
            return $false
        }
        finally {
            if ($tokenHandle -ne [IntPtr]::Zero) {
                [WinMint.TokenElevation]::CloseHandle($tokenHandle) | Out-Null
            }
        }
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
