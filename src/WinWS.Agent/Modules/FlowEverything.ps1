#Requires -Version 7.3

function Get-WinWSAgentEverythingExePath {
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        foreach ($relative in @(
                'Everything 1.5a\Everything64.exe',
                'Everything 1.5a\Everything.exe',
                'Everything\Everything64.exe',
                'Everything\Everything.exe',
                'Programs\Everything 1.5a\Everything64.exe',
                'Programs\Everything 1.5a\Everything.exe',
                'Programs\Everything\Everything64.exe',
                'Programs\Everything\Everything.exe'
            )) {
            $candidates.Add((Join-Path $root $relative)) | Out-Null
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }

    $cmd = Get-Command Everything64.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command Everything.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }

    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) { continue }
        $match = Get-ChildItem -LiteralPath $root -Directory -Filter 'Everything*' -ErrorAction SilentlyContinue |
            ForEach-Object {
                Get-ChildItem -LiteralPath $_.FullName -File -Include 'Everything64.exe', 'Everything.exe' -Recurse -ErrorAction SilentlyContinue
            } |
            Select-Object -First 1
        if ($match) { return $match.FullName }
    }

    return ''
}

function Set-WinWSAgentIniValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force -ErrorAction SilentlyContinue
    }
    $lines = if (Test-Path -LiteralPath $Path) {
        [System.Collections.Generic.List[string]]::new([string[]](Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue))
    } else {
        [System.Collections.Generic.List[string]]::new()
    }
    if ($lines.Count -eq 0) { $lines.Add('[Everything]') | Out-Null }
    if ($lines[0] -notmatch '^\[Everything\]') { $lines.Insert(0, '[Everything]') }

    $pattern = '^\s*' + [regex]::Escape($Name) + '\s*='
    $updated = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $pattern) {
            $lines[$i] = "$Name=$Value"
            $updated = $true
            break
        }
    }
    if (-not $updated) { $lines.Add("$Name=$Value") | Out-Null }
    [System.IO.File]::WriteAllLines($Path, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
}

function Set-WinWSAgentEverythingAlphaConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    [void]$State

    foreach ($name in @('Everything', 'Everything64')) {
        Get-Process -Name $name -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }

    $exe = Get-WinWSAgentEverythingExePath
    if ([string]::IsNullOrWhiteSpace($exe)) {
        throw 'Everything Alpha executable was not found after installation.'
    }

    $exeDir = Split-Path -Parent $exe
    $appDataDir = Join-Path $env:APPDATA 'Everything'
    $iniPaths = @(
        (Join-Path $exeDir 'Everything.ini'),
        (Join-Path $exeDir 'Everything-1.5a.ini'),
        (Join-Path $appDataDir 'Everything.ini'),
        (Join-Path $appDataDir 'Everything-1.5a.ini')
    ) | Select-Object -Unique

    foreach ($ini in $iniPaths) {
        try {
            Set-WinWSAgentIniValue -Path $ini -Name 'app_data' -Value '1'
            Set-WinWSAgentIniValue -Path $ini -Name 'alpha_instance' -Value '0'
            Set-WinWSAgentIniValue -Path $ini -Name 'service_name' -Value 'Everything'
            Set-WinWSAgentIniValue -Path $ini -Name 'service_pipe_name' -Value '\\.\PIPE\Everything Service'
            Set-WinWSAgentIniValue -Path $ini -Name 'allow_multiple_windows' -Value '0'
            Set-WinWSAgentIniValue -Path $ini -Name 'run_in_background' -Value '1'
            Set-WinWSAgentIniValue -Path $ini -Name 'show_tray_icon' -Value '0'
        }
        catch {
            Write-AgentLog "Everything Alpha config warning for ${ini}: $($_.Exception.Message)"
        }
    }

    try {
        $marker = Join-Path $exeDir 'NO_ALPHA_INSTANCE'
        if (-not (Test-Path -LiteralPath $marker)) {
            [System.IO.File]::WriteAllText($marker, '', [System.Text.UTF8Encoding]::new($false))
        }
    }
    catch {
        Write-AgentLog "Everything Alpha NO_ALPHA_INSTANCE warning: $($_.Exception.Message)"
    }

    try {
        Invoke-AgentNative -FilePath $exe -ArgumentList @('-uninstall-service')
    }
    catch {
        Write-AgentLog "Everything service uninstall warning: $($_.Exception.Message)"
    }

    Invoke-AgentNative -FilePath $exe -ArgumentList @(
        '-install-service',
        '-install-service-pipe-name',
        '\\.\PIPE\Everything Service'
    )

    try {
        Start-Service -Name 'Everything' -ErrorAction SilentlyContinue
    }
    catch {
        Write-AgentLog "Everything service start warning: $($_.Exception.Message)"
    }

    $State.steps['config:everything-alpha'] = @{
        status = 'ok'
        updatedAt = (Get-Date -Format o)
        exe = $exe
        iniPaths = @($iniPaths)
        trayIcon = 'hidden'
    }
    Save-AgentState -State $State
}

function Set-WinWSAgentFlowLauncherEverythingIntegration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    $flowData = Join-Path $env:APPDATA 'FlowLauncher'
    $pluginsDir = Join-Path $flowData 'Plugins'
    $settingsDir = Join-Path $flowData 'Settings'
    $null = New-Item -ItemType Directory -Path $pluginsDir -Force -ErrorAction SilentlyContinue
    $null = New-Item -ItemType Directory -Path $settingsDir -Force -ErrorAction SilentlyContinue

    $State.steps['config:flow-everything'] = @{
        status = 'ok'
        updatedAt = (Get-Date -Format o)
        note = 'Flow Launcher Everything support is provided by the official Explorer plugin in current Flow builds; standalone Everything plugin is archived upstream.'
    }
    Save-AgentState -State $State
}

function Invoke-WinWSAgentFlowEverythingBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    [void]$AgentProfile

    Install-AgentManifestTool -ToolId 'everything' -State $State
    Set-WinWSAgentEverythingAlphaConfiguration -State $State
    Install-AgentManifestTool -ToolId 'flow-launcher' -State $State
    Set-WinWSAgentFlowLauncherEverythingIntegration -State $State

    [pscustomobject]@{
        Id      = 'flow-everything'
        Status  = 'ok'
        Message = 'Everything Alpha and Flow Launcher installed.'
    }
}
