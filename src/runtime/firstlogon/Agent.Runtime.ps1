#Requires -Version 7.6

function Read-AgentJson {
    param([string]$Path, [object]$Fallback)
    try {
        if (Test-Path -LiteralPath $Path) {
            return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    } catch {
        Write-AgentLog "JSON read failed: $Path :: $($_.Exception.Message)"
    }
    return $Fallback
}

function Save-AgentState {
    param([object]$State)
    $json = $State | ConvertTo-Json -Depth 12
    $tmp = "$statePath.tmp"
    $json | Set-Content -LiteralPath $tmp -Encoding UTF8
    $null = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
    Move-Item -LiteralPath $tmp -Destination $statePath -Force
}

function Set-AgentStateValue {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Name,
        $Value
    )
    if ($State -is [hashtable]) {
        $State[$Name] = $Value
        return
    }
    $prop = $State.PSObject.Properties[$Name]
    if ($prop) {
        $prop.Value = $Value
        return
    }
    Add-Member -InputObject $State -NotePropertyName $Name -NotePropertyValue $Value -Force
}

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

function Get-AgentStepAttempts {
    param([object]$Step)
    if (-not $Step) { return 0 }
    if ($Step -is [hashtable] -and $Step.ContainsKey('attempts')) { return [int]$Step.attempts }
    $prop = $Step.PSObject.Properties['attempts']
    if ($prop) { return [int]$prop.Value }
    return 0
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

function Invoke-AgentNative {
    param([string]$FilePath, [string[]]$ArgumentList)
    $script:AgentCommandCounter++
    $safeName = ([IO.Path]::GetFileNameWithoutExtension($FilePath) -replace '[^A-Za-z0-9_.-]', '_')
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'command' }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $baseName = '{0:000}-{1}-{2}' -f $script:AgentCommandCounter, $stamp, $safeName
    $stdoutPath = Join-Path $commandLogDir "$baseName.out.log"
    $stderrPath = Join-Path $commandLogDir "$baseName.err.log"
    Write-AgentLog "RUN $FilePath $($ArgumentList -join ' ')"
    Write-AgentLog "RUNLOG stdout=$stdoutPath stderr=$stderrPath"
    Write-AgentEvent -Type 'command' -Status 'running' -Message "Running $([IO.Path]::GetFileName($FilePath))." -Data @{
        filePath = $FilePath
        stdout = $stdoutPath
        stderr = $stderrPath
    }
    $displayArgs = $ArgumentList -join ' '
    if ($displayArgs.Length -gt 120) { $displayArgs = $displayArgs.Substring(0, 117) + '...' }
    Write-AgentConsoleLine -Level Info -Message "Running $([IO.Path]::GetFileName($FilePath)) $displayArgs"
    # WinMint's first-logon host self-elevates before the agent runs, so package
    # installs should execute under that full admin token rather than being
    # bounced through a second limited-user task. That extra hop was brittle and
    # produced "Access is denied" failures on winget-backed installs.
    $p = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -ErrorAction Stop
    $exitCode = [int]$p.ExitCode
    if ($exitCode -ne 0) {
        $stdoutTail = @()
        $stderrTail = @()
        try { if (Test-Path -LiteralPath $stdoutPath) { $stdoutTail = @(Get-Content -LiteralPath $stdoutPath -Tail 20 -ErrorAction SilentlyContinue) } } catch {}
        try { if (Test-Path -LiteralPath $stderrPath) { $stderrTail = @(Get-Content -LiteralPath $stderrPath -Tail 20 -ErrorAction SilentlyContinue) } } catch {}
        $details = [System.Collections.Generic.List[string]]::new()
        if ($stdoutTail.Count -gt 0) {
            $details.Add("stdout:") | Out-Null
            foreach ($line in @($stdoutTail)) { $details.Add([string]$line) | Out-Null }
        }
        if ($stderrTail.Count -gt 0) {
            if ($details.Count -gt 0) { $details.Add('') | Out-Null }
            $details.Add("stderr:") | Out-Null
            foreach ($line in @($stderrTail)) { $details.Add([string]$line) | Out-Null }
        }
        Write-AgentEvent -Type 'command' -Status 'failed' -Message "$([IO.Path]::GetFileName($FilePath)) exited $exitCode." -Data @{
            filePath = $FilePath
            exitCode = $exitCode
            stdout = $stdoutPath
            stderr = $stderrPath
        }
        $message = "$FilePath exited $exitCode. Logs: $stdoutPath $stderrPath"
        if ($details.Count -gt 0) {
            $message += [Environment]::NewLine + ($details -join [Environment]::NewLine)
        }
        throw $message
    }
    Write-AgentEvent -Type 'command' -Status 'ok' -Message "$([IO.Path]::GetFileName($FilePath)) completed." -Data @{
        filePath = $FilePath
        exitCode = $exitCode
        stdout = $stdoutPath
        stderr = $stderrPath
    }
}

function Get-WingetPath {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }

    foreach ($candidate in @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'),
            (Join-Path $env:USERPROFILE 'AppData\Local\Microsoft\WindowsApps\winget.exe')
        )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }

    $pkg = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg -and $pkg.InstallLocation) {
        $manifest = Join-Path $pkg.InstallLocation 'AppxManifest.xml'
        if (Test-Path -LiteralPath $manifest -PathType Leaf) {
            try {
                Add-AppxPackage -Register $manifest -DisableDevelopmentMode -ErrorAction Stop
                Start-Sleep -Seconds 2
            }
            catch {
                Write-AgentLog "winget alias registration warning: $($_.Exception.Message)"
            }
        }
    }

    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return $null
}

function Wait-WingetPath {
    for ($i = 0; $i -lt 24; $i++) {
        $p = Get-WingetPath
        if ($p) { return $p }
        Start-Sleep -Seconds 5
    }
    return $null
}

function Get-ScoopPath {
    $cmd = Get-Command scoop -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }

    foreach ($candidate in @(
            (Join-Path $env:USERPROFILE 'scoop\shims\scoop.ps1'),
            (Join-Path $env:USERPROFILE 'scoop\shims\scoop.cmd')
        )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Wait-ScoopPath {
    for ($i = 0; $i -lt 12; $i++) {
        Update-AgentProcessPath
        $p = Get-ScoopPath
        if ($p) { return $p }
        Start-Sleep -Seconds 5
    }
    return $null
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

function Get-AgentDirectToolCachePath {
    param([Parameter(Mandatory)]$Tool)

    $cacheRoot = Join-Path $env:LOCALAPPDATA 'WinMint\Cache\Packages'
    $null = New-Item -ItemType Directory -Path $cacheRoot -Force -ErrorAction Stop
    $fileName = [IO.Path]::GetFileName(([Uri][string]$Tool.url).AbsolutePath)
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = ([string]$Tool.id -replace '[^A-Za-z0-9_.-]', '_') + '.exe'
    }
    return (Join-Path $cacheRoot $fileName)
}

function Save-AgentDirectToolInstaller {
    param([Parameter(Mandatory)]$Tool)

    $url = [string]$Tool.url
    $expectedHash = ([string]$Tool.sha256).ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($expectedHash)) {
        throw "Direct package '$($Tool.id)' is missing url or sha256 metadata."
    }

    $installerPath = Get-AgentDirectToolCachePath -Tool $Tool
    $needsDownload = $true
    if (Test-Path -LiteralPath $installerPath -PathType Leaf) {
        $existingHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToUpperInvariant()
        if ($existingHash -eq $expectedHash) {
            $needsDownload = $false
        }
        else {
            Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        }
    }

    if ($needsDownload) {
        Write-AgentConsoleLine -Level Info -Message "Downloading $($Tool.id)."
        Invoke-WebRequest -Uri $url -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
    }

    $actualHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualHash -ne $expectedHash) {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        throw "Direct package '$($Tool.id)' SHA256 mismatch. Expected $expectedHash; got $actualHash."
    }

    return [pscustomobject]@{
        Path = $installerPath
        Url = $url
        Version = [string]$Tool.version
        Sha256 = $expectedHash
    }
}

function Invoke-AgentScoop {
    param([Parameter(Mandatory)][string[]]$ArgumentList)

    $scoop = Wait-ScoopPath
    if (-not $scoop) { throw 'scoop command not available after wait.' }
    $extension = [IO.Path]::GetExtension($scoop)
    if ($extension -ieq '.ps1') {
        $ps = Resolve-AgentPowerShellHost
        Invoke-AgentNative -FilePath $ps -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scoop) + $ArgumentList)
        return
    }
    Invoke-AgentNative -FilePath $scoop -ArgumentList $ArgumentList
}

function Install-AgentScoop {
    param([hashtable]$State)

    $key = 'package-manager:scoop'
    if (-not $Force -and $State.ContainsKey('steps') -and $State.steps.ContainsKey($key) -and [string]$State.steps[$key].status -eq 'ok') {
        Write-AgentConsoleLine -Level OK -Message 'Scoop already installed.'
        return
    }

    if (Get-ScoopPath) {
        $State.steps[$key] = @{ status = 'ok'; updatedAt = (Get-Date -Format o); source = 'existing' }
        Save-AgentState -State $State
        return
    }

    $installerPath = Join-Path $env:TEMP 'WinMint-Scoop-Install.ps1'
    Invoke-WebRequest -Uri 'https://get.scoop.sh' -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
    $ps = Resolve-AgentPowerShellHost
    Invoke-AgentNative -FilePath $ps -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $installerPath,
        '-RunAsAdmin'
    )
    Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    Update-AgentProcessPath
    if (-not (Wait-ScoopPath)) { throw 'Scoop installer completed, but scoop was not found on PATH.' }
    $State.steps[$key] = @{ status = 'ok'; updatedAt = (Get-Date -Format o); source = 'https://get.scoop.sh' }
    Save-AgentState -State $State
}

function Install-AgentTool {
    param($Tool, [hashtable]$State)
    $key = "tool:$($Tool.id)"
    $hostArch = Get-AgentProcessorArchitecture
    $targetArch = Get-AgentTargetArchitecture
    $directPayload = $null
    if (-not $Force -and $State.steps.ContainsKey($key) -and $State.steps[$key].status -eq 'ok') {
        Write-AgentLog "SKIP $key already ok"
        Write-AgentConsoleLine -Level OK -Message "$($Tool.id) already installed."
        return
    }
    try {
        Write-AgentConsoleLine -Level Section -Message "Installing $($Tool.id) for $targetArch."
        if ($Tool.PSObject.Properties['architectures']) {
            $supported = @($Tool.architectures | ForEach-Object { ([string]$_).ToLowerInvariant() })
            if ($supported.Count -gt 0 -and $supported -notcontains $targetArch) {
                $State.steps[$key] = @{
                    status = 'skipped'
                    updatedAt = (Get-Date -Format o)
                    architecture = $targetArch
                    reason = "Unsupported architecture: $targetArch"
                }
                Save-AgentState -State $State
                Write-AgentEvent -Type 'step' -Status 'skipped' -Step $key -Message "$($Tool.id) is not available for $targetArch."
                Write-AgentLog "SKIP $key unsupported architecture $targetArch"
                Write-AgentConsoleLine -Level Warn -Message "$($Tool.id) is not available for $targetArch."
                return
            }
        }
        $versionPolicy = if ($Tool.PSObject.Properties['versionPolicy']) { [string]$Tool.versionPolicy } else { 'latest' }
        $requestedVersion = if ($Tool.PSObject.Properties['version']) { [string]$Tool.version } else { '' }
        switch ($Tool.source) {
            'winget' {
                $winget = Wait-WingetPath
                if (-not $winget) { throw 'winget.exe not available after wait.' }
                $installArgs = @(
                    'install', '--exact', '--id', $Tool.id, '--source', 'winget', '--silent',
                    '--accept-source-agreements', '--accept-package-agreements'
                )
                $wingetArchitecture = Get-AgentToolWingetArchitecture -Tool $Tool -HostArchitecture $hostArch -TargetArchitecture $targetArch
                if ($wingetArchitecture) {
                    $installArgs += @('--architecture', $wingetArchitecture)
                }
                if ($versionPolicy -ne 'latest' -and -not [string]::IsNullOrWhiteSpace($requestedVersion)) {
                    $installArgs += @('--version', $requestedVersion)
                }
                Invoke-AgentNative -FilePath $winget -ArgumentList $installArgs
                Update-AgentProcessPath
            }
            'store' {
                $winget = Wait-WingetPath
                if (-not $winget) { throw 'winget.exe not available after wait.' }
                $installArgs = @(
                    'install', '--exact', '--id', $Tool.id, '--source', 'msstore', '--silent',
                    '--accept-source-agreements', '--accept-package-agreements'
                )
                $wingetArchitecture = Get-AgentToolWingetArchitecture -Tool $Tool -HostArchitecture $hostArch -TargetArchitecture $targetArch
                if ($wingetArchitecture) {
                    $installArgs += @('--architecture', $wingetArchitecture)
                }
                if ($versionPolicy -ne 'latest' -and -not [string]::IsNullOrWhiteSpace($requestedVersion)) {
                    $installArgs += @('--version', $requestedVersion)
                }
                Invoke-AgentNative -FilePath $winget -ArgumentList $installArgs
                Update-AgentProcessPath
            }
            'scoop' {
                Install-AgentScoop -State $State
                $installArgs = @('install', $Tool.id)
                if ($versionPolicy -ne 'latest' -and -not [string]::IsNullOrWhiteSpace($requestedVersion)) {
                    $installArgs = @('install', "$($Tool.id)@$requestedVersion")
                }
                if ($targetArch -eq 'arm64') {
                    Write-AgentLog "Scoop install for $($Tool.id): target architecture is arm64; relying on Scoop manifest architecture selection for native ARM64/aarch64 assets where available."
                }
                Invoke-AgentScoop -ArgumentList $installArgs
                Update-AgentProcessPath
            }
            'direct' {
                $directPayload = Save-AgentDirectToolInstaller -Tool $Tool
                $installArgs = @()
                if ($Tool.PSObject.Properties['silentArgs']) {
                    $installArgs = @($Tool.silentArgs | ForEach-Object { [string]$_ })
                }
                Invoke-AgentNative -FilePath ([string]$directPayload.Path) -ArgumentList $installArgs
                Update-AgentProcessPath
            }
            default {
                # WinMint installs tools through explicit package-manager owners:
                # winget/msstore for GUI/system apps, Scoop for developer CLIs,
                # and a narrow hash-pinned direct installer exception.
                throw "Unsupported install source '$($Tool.source)' for tool '$($Tool.id)'. WinMint only supports the 'winget', 'store', 'scoop', and approved 'direct' install sources."
            }
        }
        $record = @{
            status = 'ok'
            updatedAt = (Get-Date -Format o)
            architecture = $targetArch
        }
        if ($null -ne $directPayload) {
            $record.source = 'direct'
            $record.url = [string]$directPayload.Url
            $record.version = [string]$directPayload.Version
            $record.sha256 = [string]$directPayload.Sha256
            $record.path = [string]$directPayload.Path
        }
        $State.steps[$key] = $record
        Save-AgentState -State $State
        Write-AgentEvent -Type 'step' -Status 'ok' -Step $key -Message "$($Tool.id) installed." -Data @{
            architecture = $targetArch
            hostArchitecture = $hostArch
        }
        Write-AgentConsoleLine -Level OK -Message "$($Tool.id) installed."
    } catch {
        $State.steps[$key] = @{
            status = 'failed'
            updatedAt = (Get-Date -Format o)
            architecture = $targetArch
            hostArchitecture = $hostArch
            error = $_.Exception.Message
        }
        Save-AgentState -State $State
        Write-AgentEvent -Type 'step' -Status 'failed' -Step $key -Message "$($Tool.id) failed." -Data @{
            architecture = $targetArch
            hostArchitecture = $hostArch
            error = $_.Exception.Message
        }
        Write-AgentLog "FAIL $key :: $($_.Exception.Message)"
        Write-AgentConsoleLine -Level Error -Message "$($Tool.id) failed: $($_.Exception.Message)"
    }
}

function Get-AgentManifestTool {
    param(
        [Parameter(Mandatory)][string]$ToolId
    )

    if (-not $manifest -or -not $manifest.PSObject.Properties['tools']) {
        throw 'packages.json does not contain a tools manifest.'
    }
    $property = $manifest.tools.PSObject.Properties[$ToolId]
    if (-not $property) {
        throw "Tool '$ToolId' is not defined in packages.json."
    }

    return $property.Value
}

function Install-AgentManifestTool {
    param(
        [Parameter(Mandatory)][string]$ToolId,
        [Parameter(Mandatory)][hashtable]$State
    )

    $tool = Get-AgentManifestTool -ToolId $ToolId
    Install-AgentTool -Tool $tool -State $State
    $key = "tool:$($tool.id)"
    if (-not $State.steps.ContainsKey($key)) {
        throw "Tool '$ToolId' did not record install state."
    }
    $status = [string]$State.steps[$key].status
    if ($status -ne 'ok') {
        $reason = if ($State.steps[$key].error) {
            [string]$State.steps[$key].error
        }
        elseif ($State.steps[$key].reason) {
            [string]$State.steps[$key].reason
        }
        else {
            $status
        }
        throw "Tool '$ToolId' install did not complete: $reason"
    }
}

function Get-AgentModuleConfig {
    param([Parameter(Mandatory)][string]$Name)
    if (-not $agentProfile.modules) { return $null }
    $prop = $agentProfile.modules.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function Get-WinMintAgentModuleCatalog {
    return @(
        [pscustomobject]@{
            Id = 'profiles'
            RelativePath = 'Modules\Profiles.ps1'
            BootstrapFunction = 'Invoke-WinMintAgentProfileBootstrap'
            RuntimeStepName = 'profiles'
            Enablement = 'always'
            Title = 'Compose and normalize the live-user agent profile'
            Kind = 'first-logon-module'
            Default = $true
            Requires = @()
            SuppressedBy = @()
            UserControlled = $false
            Changes = @('Prepare normalized FirstLogon state and module intent before live installs begin')
            Artifacts = @('state.json', 'WinMintAgentProfile.json')
            Reversible = $false
            FailurePolicy = 'blocking'
            Phase = 'main'
            PostStepHook = ''
        }
        [pscustomobject]@{
            Id = 'packageManagers'
            RelativePath = 'Modules\PackageManagers.ps1'
            BootstrapFunction = 'Invoke-WinMintAgentPackageManagerBootstrap'
            RuntimeStepName = 'package-managers'
            Enablement = 'modules.packageManagers.enabled'
            Title = 'Bootstrap package managers for live-user installs'
            Kind = 'first-logon-module'
            Default = $true
            Requires = @('modules.packageManagers.enabled')
            SuppressedBy = @()
            UserControlled = $false
            Changes = @('Ensure winget and Scoop ownership paths are ready for live-user package installation')
            Artifacts = @('state.json', 'packages.json')
            Reversible = $true
            FailurePolicy = 'advisory'
            Phase = 'main'
            PostStepHook = ''
        }
        [pscustomobject]@{
            Id = 'wsl'
            RelativePath = 'Modules\Wsl.ps1'
            BootstrapFunction = 'Invoke-WinMintAgentWslBootstrap'
            RuntimeStepName = 'wsl'
            Enablement = 'modules.wsl.enabled'
            Title = 'Enable WSL baseline and install selected distros'
            Kind = 'first-logon-module'
            Default = $true
            Requires = @('modules.wsl.enabled')
            SuppressedBy = @()
            UserControlled = $false
            Changes = @('Configure WSL defaults and install selected distros when requested')
            Artifacts = @('state.json', 'WinMintAgentProfile.json')
            Reversible = $true
            FailurePolicy = 'advisory'
            Phase = 'main'
            PostStepHook = ''
        }
        [pscustomobject]@{
            Id = 'git'
            RelativePath = 'Modules\Git.ps1'
            BootstrapFunction = 'Invoke-WinMintAgentGitBootstrap'
            RuntimeStepName = 'git'
            Enablement = 'modules.git.enabled'
            Title = 'Apply optional Git configuration'
            Kind = 'first-logon-module'
            Default = $false
            Requires = @('modules.git.enabled')
            SuppressedBy = @()
            UserControlled = $true
            Changes = @('Configure Git defaults for the live user')
            Artifacts = @('state.json')
            Reversible = $true
            FailurePolicy = 'advisory'
            Phase = 'main'
            PostStepHook = ''
        }
        [pscustomobject]@{
            Id = 'dotfiles'
            RelativePath = 'Modules\Dotfiles.ps1'
            BootstrapFunction = 'Invoke-WinMintAgentDotfileBootstrap'
            RuntimeStepName = 'dotfiles'
            Enablement = 'modules.dotfiles.enabled'
            Title = 'Apply optional dotfiles bootstrap'
            Kind = 'first-logon-module'
            Default = $false
            Requires = @('modules.dotfiles.enabled')
            SuppressedBy = @()
            UserControlled = $true
            Changes = @('Clone and apply configured dotfiles for the live user')
            Artifacts = @('state.json')
            Reversible = $true
            FailurePolicy = 'advisory'
            Phase = 'main'
            PostStepHook = ''
        }
        [pscustomobject]@{
            Id = 'raycast'
            RelativePath = 'Modules\Raycast.ps1'
            BootstrapFunction = 'Invoke-WinMintAgentRaycastBootstrap'
            RuntimeStepName = 'raycast'
            Enablement = 'modules.raycast.enabled'
            Title = 'Install and configure the optional Raycast launcher'
            Kind = 'first-logon-module'
            Default = $false
            Requires = @('modules.raycast.enabled')
            SuppressedBy = @()
            UserControlled = $true
            Changes = @('Install Raycast and its curated extension/backend set')
            Artifacts = @('state.json', 'WinMintAgentProfile.json')
            Reversible = $true
            FailurePolicy = 'advisory'
            Phase = 'main'
            PostStepHook = ''
        }
        [pscustomobject]@{
            Id = 'launcherKey'
            RelativePath = 'Modules\LauncherKey.ps1'
            BootstrapFunction = 'Invoke-WinMintAgentLauncherKeyBootstrap'
            RuntimeStepName = 'launcher-key'
            Enablement = 'modules.launcherKey.enabled'
            Title = 'Bind the Copilot hardware-key chord to the selected launcher target'
            Kind = 'first-logon-module'
            Default = $true
            Requires = @('modules.launcherKey.enabled')
            SuppressedBy = @()
            UserControlled = $false
            Changes = @('Bind Win+Shift+F23 to Search or Raycast according to the selected launcher path')
            Artifacts = @('state.json', 'WinMintAgentProfile.json')
            Reversible = $true
            FailurePolicy = 'advisory'
            Phase = 'main'
            PostStepHook = ''
        }
        [pscustomobject]@{
            Id = 'phoneLink'
            RelativePath = 'Modules\PhoneLink.ps1'
            BootstrapFunction = 'Invoke-WinMintAgentPhoneLinkBootstrap'
            RuntimeStepName = 'phone-link'
            Enablement = 'modules.phoneLink.enabled'
            Title = 'Prepare optional Phone Link live-user posture'
            Kind = 'first-logon-module'
            Default = $false
            Requires = @('modules.phoneLink.enabled')
            SuppressedBy = @()
            UserControlled = $true
            Changes = @('Prepare Phone Link-related user settings without forcing device pairing')
            Artifacts = @('state.json')
            Reversible = $true
            FailurePolicy = 'advisory'
            Phase = 'main'
            PostStepHook = ''
        }
        [pscustomobject]@{
            Id = 'shell'
            RelativePath = 'Modules\TilingDesktop.ps1'
            BootstrapFunction = 'Invoke-WinMintAgentTilingDesktopBootstrap'
            RuntimeStepName = 'tiling-desktop'
            Enablement = 'modules.shell.enabled'
            Title = 'Install and configure selected shell layers'
            Kind = 'first-logon-module'
            Default = $false
            Requires = @('modules.shell.enabled')
            SuppressedBy = @()
            UserControlled = $true
            Changes = @('Configure selected shell layers such as YASB, thide, Komorebi, and Nilesoft Shell')
            Artifacts = @('state.json', 'WinMintAgentProfile.json')
            Reversible = $true
            FailurePolicy = 'advisory'
            Phase = 'main'
            PostStepHook = ''
        }
        [pscustomobject]@{
            Id = 'windhawk'
            RelativePath = 'Modules\Windhawk.ps1'
            BootstrapFunction = 'Invoke-WinMintAgentWindhawkBootstrap'
            RuntimeStepName = 'windhawk'
            Enablement = 'modules.windhawk.enabled'
            Title = 'Install the optional Windhawk desktop layer'
            Kind = 'first-logon-module'
            Default = $false
            Requires = @('modules.windhawk.enabled')
            SuppressedBy = @()
            UserControlled = $true
            Changes = @('Install Windhawk and apply the staged preset')
            Artifacts = @('state.json', 'WinMintAgentProfile.json')
            Reversible = $true
            FailurePolicy = 'advisory'
            Phase = 'main'
            PostStepHook = ''
        }
        [pscustomobject]@{
            Id = 'browsers'
            RelativePath = 'Modules\Browsers.ps1'
            BootstrapFunction = 'Invoke-WinMintAgentBrowsersBootstrap'
            RuntimeStepName = 'browsers'
            Enablement = 'browsers.count > 0'
            Title = 'Install selected browsers'
            Kind = 'first-logon-module'
            Default = $false
            Requires = @('browsers.count > 0')
            SuppressedBy = @()
            UserControlled = $true
            Changes = @('Install the selected browser set for the live user')
            Artifacts = @('state.json', 'packages.json')
            Reversible = $true
            FailurePolicy = 'advisory'
            Phase = 'main'
            PostStepHook = ''
        }
        [pscustomobject]@{
            Id = 'editors'
            RelativePath = 'Modules\Editors.ps1'
            BootstrapFunction = 'Invoke-WinMintAgentEditorBootstrap'
            RuntimeStepName = 'editors'
            Enablement = 'editors.count > 0'
            Title = 'Install selected editors'
            Kind = 'first-logon-module'
            Default = $false
            Requires = @('editors.count > 0')
            SuppressedBy = @()
            UserControlled = $true
            Changes = @('Install the selected editor set for the live user')
            Artifacts = @('state.json', 'packages.json')
            Reversible = $true
            FailurePolicy = 'advisory'
            Phase = 'main'
            PostStepHook = 'Set-WinMintAgentNeovimEnvironment'
        }
        [pscustomobject]@{
            Id = 'liveInstallAudit'
            RelativePath = 'Modules\LiveInstallAudit.ps1'
            BootstrapFunction = 'Invoke-WinMintAgentLiveInstallAuditBootstrap'
            RuntimeStepName = 'liveInstallAudit'
            Enablement = 'modules.liveInstallAudit.enabled'
            Title = 'Run optional live install audit reporting'
            Kind = 'first-logon-module'
            Default = $false
            Requires = @('modules.liveInstallAudit.enabled')
            SuppressedBy = @()
            UserControlled = $true
            Changes = @('Generate a non-blocking live install audit report after agent execution')
            Artifacts = @('state.json', 'LiveInstallAudit.json')
            Reversible = $false
            FailurePolicy = 'advisory'
            Phase = 'finalValidation'
            PostStepHook = ''
        }
    )
}

function Import-WinMintAgentRegisteredModules {
    param(
        [Parameter(Mandatory)][string]$AgentRoot
    )

    foreach ($moduleDefinition in @(Get-WinMintAgentModuleCatalog)) {
        $modulePath = Join-Path $AgentRoot $moduleDefinition.RelativePath
        if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
            throw "FirstLogon module '$($moduleDefinition.Id)' is missing: $modulePath"
        }

        . $modulePath

        $bootstrapFunction = [string]$moduleDefinition.BootstrapFunction
        if (-not (Get-Command $bootstrapFunction -ErrorAction SilentlyContinue)) {
            throw "FirstLogon module '$($moduleDefinition.Id)' did not register required function '$bootstrapFunction'."
        }
    }
}

function Test-AgentModuleEnabled {
    param([Parameter(Mandatory)][string]$Name)
    $cfg = Get-AgentModuleConfig -Name $Name
    if (-not $cfg) { return $false }
    $enabledProp = $cfg.PSObject.Properties['enabled']
    if ($enabledProp) { return [bool]$enabledProp.Value }
    foreach ($p in $cfg.PSObject.Properties) {
        if ($p.Value -is [bool] -and $p.Value) { return $true }
    }
    return $false
}

function Get-WinMintAgentModuleRuntimeState {
    param(
        [Parameter(Mandatory)]$ModuleDefinition
    )

    $moduleId = [string]$ModuleDefinition.Id
    $enablement = [string]$ModuleDefinition.Enablement
    switch ($enablement) {
        'always' { return $true }
        'modules.packageManagers.enabled' { return (Test-AgentModuleEnabled -Name 'packageManagers') }
        'modules.wsl.enabled' { return (Test-AgentModuleEnabled -Name 'wsl') }
        'modules.git.enabled' { return (Test-AgentModuleEnabled -Name 'git') }
        'modules.dotfiles.enabled' { return (Test-AgentModuleEnabled -Name 'dotfiles') }
        'modules.raycast.enabled' { return (Test-AgentModuleEnabled -Name 'raycast') }
        'modules.launcherKey.enabled' { return (Test-AgentModuleEnabled -Name 'launcherKey') }
        'modules.phoneLink.enabled' { return (Test-AgentModuleEnabled -Name 'phoneLink') }
        'modules.shell.enabled' { return (Test-AgentModuleEnabled -Name 'shell') }
        'modules.windhawk.enabled' { return (Test-AgentModuleEnabled -Name 'windhawk') }
        'modules.liveInstallAudit.enabled' { return (Test-AgentModuleEnabled -Name 'liveInstallAudit') }
        'browsers.count > 0' { return (@($agentProfile.browsers).Count -gt 0) }
        'editors.count > 0' { return (@($agentProfile.editors).Count -gt 0) }
        default { throw "Unsupported agent module enablement expression '$enablement' for '$moduleId'." }
    }
}

function Test-WinMintAgentStateStepOk {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][string]$Key
    )

    if (-not $State.steps.ContainsKey($Key)) { return $false }
    return ([string]$State.steps[$Key].status -eq 'ok')
}

function New-WinMintAgentRuntimeStepPlan {
    $steps = [System.Collections.Generic.List[object]]::new()
    foreach ($moduleDefinition in @(Get-WinMintAgentModuleCatalog)) {
        $steps.Add([pscustomobject]@{
                Id = "module:$([string]$moduleDefinition.RuntimeStepName)"
                Order = ($steps.Count + 1)
                Phase = [string]$moduleDefinition.Phase
                StepName = [string]$moduleDefinition.RuntimeStepName
                FunctionName = [string]$moduleDefinition.BootstrapFunction
                Enabled = (Get-WinMintAgentModuleRuntimeState -ModuleDefinition $moduleDefinition)
                Enablement = [string]$moduleDefinition.Enablement
                FailurePolicy = [string]$moduleDefinition.FailurePolicy
                PostStepHook = [string]$moduleDefinition.PostStepHook
            }) | Out-Null
    }

    return @($steps)
}

function Set-WinMintAgentNeovimEnvironment {
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    if (@($AgentProfile.editors) -notcontains 'neovim') { return }

    $stateKey = 'tool:neovim'
    try {
        $nvTool = Get-AgentManifestTool -ToolId 'neovim'
        $stateKey = "tool:$([string]$nvTool.id)"
    }
    catch {
        Write-AgentLog "Neovim manifest lookup for EDITOR/VISUAL: $($_.Exception.Message)"
    }

    if ((Test-WinMintAgentStateStepOk -State $State -Key $stateKey) -or
        (Test-WinMintAgentStateStepOk -State $State -Key 'tool:neovim')) {
        [Environment]::SetEnvironmentVariable('EDITOR', 'nvim', 'User')
        [Environment]::SetEnvironmentVariable('VISUAL', 'nvim', 'User')
    }
}

function Invoke-WinMintAgentPostStepHook {
    param(
        [string]$HookName
    )

    if ([string]::IsNullOrWhiteSpace($HookName)) { return }

    $cmd = Get-Command $HookName -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-AgentLog "Post-step hook not found: $HookName"
        Write-AgentConsoleLine -Level Warn -Message "Post-step hook not found: $HookName"
        return
    }

    try {
        & $HookName -AgentProfile $agentProfile -State $State
    }
    catch {
        Write-AgentLog "Post-step hook '$HookName' failed: $($_.Exception.Message)"
        Write-AgentConsoleLine -Level Warn -Message "Post-step hook '$HookName' failed: $($_.Exception.Message)"
    }
}

function Invoke-AgentProfileModule {
    param(
        [Parameter(Mandatory)][string]$StepName,
        [Parameter(Mandatory)][string]$FunctionName,
        [bool]$Enabled,
        [string]$PostStepHook = ''
    )

    $key = "module:$StepName"
    if (-not $Enabled) {
        $State.steps[$key] = @{ status = 'skipped'; updatedAt = (Get-Date -Format o) }
        Save-AgentState -State $State
        Write-AgentEvent -Type 'step' -Status 'skipped' -Step $key -Message "$StepName is not selected."
        return
    }
    if (-not $Force -and $State.steps.ContainsKey($key) -and $State.steps[$key].status -eq 'ok') {
        Write-AgentLog "SKIP $key already ok"
        Write-AgentEvent -Type 'step' -Status 'ok' -Step $key -Message "$StepName already completed."
        Write-AgentConsoleLine -Level OK -Message "$StepName already completed."
        Invoke-WinMintAgentPostStepHook -HookName $PostStepHook
        return
    }
    $cmd = Get-Command $FunctionName -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $State.steps[$key] = @{ status = 'failed'; updatedAt = (Get-Date -Format o); error = "$FunctionName not found" }
        Save-AgentState -State $State
        Write-AgentEvent -Type 'step' -Status 'failed' -Step $key -Message "$StepName could not start." -Data @{
            error = "$FunctionName not found"
        }
        Write-AgentLog "FAIL $key :: $FunctionName not found"
        Write-AgentConsoleLine -Level Error -Message "$StepName could not start."
        return
    }
    try {
        $attempts = Get-AgentStepAttempts -Step $State.steps[$key]
        $State.steps[$key] = @{
            status = 'running'
            startedAt = (Get-Date -Format o)
            updatedAt = (Get-Date -Format o)
            attempts = ($attempts + 1)
        }
        Save-AgentState -State $State
        Write-AgentEvent -Type 'step' -Status 'running' -Step $key -Message "Starting $StepName." -Data @{
            attempts = ($attempts + 1)
        }
        Write-AgentConsoleLine -Level Section -Message "Starting $StepName."
        $result = & $FunctionName -AgentProfile $agentProfile -State $State
        $status = if ($result -and $result.PSObject.Properties['Status']) { [string]$result.Status } else { 'ok' }
        $State.steps[$key] = @{
            status = $status
            updatedAt = (Get-Date -Format o)
            attempts = ($attempts + 1)
            result = $result
        }
        Write-AgentLog "MODULE $key :: $status"
        Write-AgentEvent -Type 'step' -Status $status -Step $key -Message "$StepName finished: $status." -Data @{
            attempts = ($attempts + 1)
        }
        $level = if ($status -eq 'ok') { 'OK' } elseif ($status -eq 'skipped') { 'Warn' } else { 'Warn' }
        Write-AgentConsoleLine -Level $level -Message "$StepName finished: $status."
    }
    catch {
        $State.steps[$key] = @{
            status = 'failed'
            updatedAt = (Get-Date -Format o)
            attempts = ($attempts + 1)
            error = $_.Exception.Message
        }
        Write-AgentLog "FAIL $key :: $($_.Exception.Message)"
        Write-AgentEvent -Type 'step' -Status 'failed' -Step $key -Message "$StepName failed." -Data @{
            attempts = ($attempts + 1)
            error = $_.Exception.Message
        }
        Write-AgentConsoleLine -Level Error -Message "$StepName failed: $($_.Exception.Message)"
    }
    Save-AgentState -State $State
    Invoke-WinMintAgentPostStepHook -HookName $PostStepHook
}

function Invoke-WinMintAgentStepRuntime {
    $runtimePlan = @(New-WinMintAgentRuntimeStepPlan)
    foreach ($step in @($runtimePlan | Where-Object { $_.Phase -eq 'main' } | Sort-Object Order)) {
        Invoke-AgentProfileModule -StepName $step.StepName -FunctionName $step.FunctionName -Enabled ([bool]$step.Enabled) -PostStepHook ([string]$step.PostStepHook)
    }
    Remove-AgentDesktopShortcuts

    foreach ($step in @($runtimePlan | Where-Object { $_.Phase -eq 'finalValidation' } | Sort-Object Order)) {
        Invoke-AgentProfileModule -StepName $step.StepName -FunctionName $step.FunctionName -Enabled ([bool]$step.Enabled) -PostStepHook ([string]$step.PostStepHook)
    }

    # Live-user modules are best-effort. A failed app/tool install must not keep
    # autologon credentials resident or block final desktop personalization; the
    # summary and state file carry the retry/manual-repair details.
    $blockingSteps = @($runtimePlan | Where-Object { $_.FailurePolicy -eq 'blocking' } | ForEach-Object { [string]$_.Id })
    $allFailed = @($state.steps.GetEnumerator() | Where-Object { $_.Value.status -eq 'failed' })
    $advisoryFailed = @($allFailed | Where-Object { [string]$_.Key -notin $blockingSteps })
    $failed = @($allFailed | Where-Object { [string]$_.Key -in $blockingSteps })
    foreach ($a in $advisoryFailed) {
        Write-AgentLog "Live step '$([string]$a.Key)' failed (non-blocking); continuing so setup can finish."
    }
    if ($failed.Count -gt 0) {
        $rebootPending = Test-AgentRebootPending
        Set-AgentStateValue -State $state -Name 'failedAt' -Value (Get-Date -Format o)
        Set-AgentStateValue -State $state -Name 'run' -Value @{
            status = 'failed'
            completedAt = (Get-Date -Format o)
            exitCode = 1
            failedSteps = @($failed | ForEach-Object { [string]$_.Key })
            rebootPending = $rebootPending
        }
        Save-AgentState -State $state
        Write-AgentEvent -Type 'run' -Status 'failed' -Message "FirstLogon failed: $($failed.Count) failed step(s)." -Data @{
            failedSteps = @($failed | ForEach-Object { [string]$_.Key })
            rebootPending = $rebootPending
        }
        if ($rebootPending) { Write-AgentLog 'Windows reports a pending reboot after the failed FirstLogon run.' }
        Write-AgentLog "WinMintAgent failed: $($failed.Count) failed step(s)."
        Show-AgentFinalSummary -State $state
        Wait-AgentConsoleBeforeClose -Failed $true
        return 1
    }

    $rebootPending = Test-AgentRebootPending
    Set-AgentStateValue -State $state -Name 'completedAt' -Value (Get-Date -Format o)
    $warningSteps = @($advisoryFailed | ForEach-Object { [string]$_.Key })
    Set-AgentStateValue -State $state -Name 'run' -Value @{
        status = 'ok'
        completedAt = (Get-Date -Format o)
        exitCode = 0
        rebootPending = $rebootPending
        warningSteps = $warningSteps
    }
    Save-AgentState -State $state
    $message = if ($warningSteps.Count -gt 0) { 'FirstLogon agent completed with warnings.' } else { 'FirstLogon agent completed.' }
    Write-AgentEvent -Type 'run' -Status 'ok' -Message $message -Data @{
        rebootPending = $rebootPending
        warningSteps = $warningSteps
    }
    if ($rebootPending) { Write-AgentLog 'Windows reports a pending reboot after the successful FirstLogon run.' }
    if ($warningSteps.Count -gt 0) { Write-AgentLog "WinMintAgent completed with warning step(s): $($warningSteps -join ', ')" }
    else { Write-AgentLog 'WinMintAgent end' }
    Show-AgentFinalSummary -State $state
    Wait-AgentConsoleBeforeClose -Failed $false -Warnings:($warningSteps.Count -gt 0)
    return 0
}

# NOTE: FirstLogon modules are registered through Get-WinMintAgentModuleCatalog and
# loaded by Import-WinMintAgentRegisteredModules. Keep this explicit catalog aligned
# with the runtime step plan; do not fall back to folder globbing or function-scoped
# loaders that lose the exported bootstrap functions.

