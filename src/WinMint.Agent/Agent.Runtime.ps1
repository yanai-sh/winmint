#Requires -Version 7.3

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
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'),
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
    $sysnative = Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $sysnative) { return $sysnative }
    $system32 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $system32) { return $system32 }
    return 'powershell.exe'
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
    $p = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -ErrorAction Stop
    if ($p.ExitCode -ne 0) {
        Write-AgentEvent -Type 'command' -Status 'failed' -Message "$([IO.Path]::GetFileName($FilePath)) exited $($p.ExitCode)." -Data @{
            filePath = $FilePath
            exitCode = [int]$p.ExitCode
            stdout = $stdoutPath
            stderr = $stderrPath
        }
        throw "$FilePath exited $($p.ExitCode). Logs: $stdoutPath $stderrPath"
    }
    Write-AgentEvent -Type 'command' -Status 'ok' -Message "$([IO.Path]::GetFileName($FilePath)) completed." -Data @{
        filePath = $FilePath
        exitCode = [int]$p.ExitCode
        stdout = $stdoutPath
        stderr = $stderrPath
    }
}

function Get-WingetPath {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $pkg = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg -and $pkg.InstallLocation) {
        $p = Join-Path $pkg.InstallLocation 'winget.exe'
        if (Test-Path -LiteralPath $p) { return $p }
    }
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

function Test-AgentProcessElevated {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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
        [Parameter(Mandatory)][string]$HostArchitecture
    )

    if ($Tool.PSObject.Properties['wingetArchitectureByHost']) {
        $override = $Tool.wingetArchitectureByHost.PSObject.Properties[$HostArchitecture]
        if ($override -and -not [string]::IsNullOrWhiteSpace([string]$override.Value)) {
            return [string]$override.Value
        }
    }

    return ConvertTo-AgentWingetArchitecture -Architecture $HostArchitecture
}

function Install-AgentTool {
    param($Tool, [hashtable]$State)
    $key = "tool:$($Tool.id)"
    $hostArch = Get-AgentProcessorArchitecture
    if (-not $Force -and $State.steps.ContainsKey($key) -and $State.steps[$key].status -eq 'ok') {
        Write-AgentLog "SKIP $key already ok"
        Write-AgentConsoleLine -Level OK -Message "$($Tool.id) already installed."
        return
    }
    try {
        Write-AgentConsoleLine -Level Section -Message "Installing $($Tool.id) for $hostArch."
        if ($Tool.PSObject.Properties['architectures']) {
            $supported = @($Tool.architectures | ForEach-Object { ([string]$_).ToLowerInvariant() })
            if ($supported.Count -gt 0 -and $supported -notcontains $hostArch) {
                $State.steps[$key] = @{
                    status = 'skipped'
                    updatedAt = (Get-Date -Format o)
                    architecture = $hostArch
                    reason = "Unsupported architecture: $hostArch"
                }
                Save-AgentState -State $State
                Write-AgentEvent -Type 'step' -Status 'skipped' -Step $key -Message "$($Tool.id) is not available for $hostArch."
                Write-AgentLog "SKIP $key unsupported architecture $hostArch"
                Write-AgentConsoleLine -Level Warn -Message "$($Tool.id) is not available for $hostArch."
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
                    'install', '--exact', '--id', $Tool.id, '--silent',
                    '--accept-source-agreements', '--accept-package-agreements'
                )
                $wingetArchitecture = Get-AgentToolWingetArchitecture -Tool $Tool -HostArchitecture $hostArch
                if ($wingetArchitecture) {
                    $installArgs += @('--architecture', $wingetArchitecture)
                }
                if ($versionPolicy -ne 'latest' -and -not [string]::IsNullOrWhiteSpace($requestedVersion)) {
                    $installArgs += @('--version', $requestedVersion)
                }
                Invoke-AgentNative -FilePath $winget -ArgumentList $installArgs
                Update-AgentProcessPath
            }
            default {
                throw "Source not implemented in this wave: $($Tool.source)"
            }
        }
        $State.steps[$key] = @{ status = 'ok'; updatedAt = (Get-Date -Format o); architecture = $hostArch }
        Save-AgentState -State $State
        Write-AgentEvent -Type 'step' -Status 'ok' -Step $key -Message "$($Tool.id) installed." -Data @{
            architecture = $hostArch
        }
        Write-AgentConsoleLine -Level OK -Message "$($Tool.id) installed."
    } catch {
        $State.steps[$key] = @{
            status = 'failed'
            updatedAt = (Get-Date -Format o)
            architecture = $hostArch
            error = $_.Exception.Message
        }
        Save-AgentState -State $State
        Write-AgentEvent -Type 'step' -Status 'failed' -Step $key -Message "$($Tool.id) failed." -Data @{
            architecture = $hostArch
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

function Invoke-AgentProfileModule {
    param(
        [Parameter(Mandatory)][string]$StepName,
        [Parameter(Mandatory)][string]$FunctionName,
        [bool]$Enabled
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
}

function Import-AgentModule {
    if (-not (Test-Path -LiteralPath $script:AgentModuleRoot)) { return }
    Get-ChildItem -LiteralPath $script:AgentModuleRoot -Filter '*.ps1' -File |
        Sort-Object -Property Name |
        ForEach-Object { . $_.FullName }
}
