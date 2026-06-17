#Requires -Version 7.6

function Get-WinMintAgentRaycastConfig {
    param([Parameter(Mandatory)][object]$AgentProfile)

    if (-not $AgentProfile.modules) { return $null }
    $prop = $AgentProfile.modules.PSObject.Properties['raycast']
    if ($prop) { return $prop.Value }
    return $null
}

function Get-WinMintAgentEverythingExePath {
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

    foreach ($name in @('Everything64.exe', 'Everything.exe')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }

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

function Set-WinMintAgentIniValue {
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

function Set-WinMintAgentEverythingConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][string]$PackageId
    )

    $key = 'config:everything-search-backend'
    if (-not $Force -and $State.steps.ContainsKey($key) -and [string]$State.steps[$key].status -eq 'ok') {
        Write-AgentConsoleLine -Level OK -Message 'Everything search backend already configured.'
        return
    }

    foreach ($name in @('Everything', 'Everything64')) {
        Get-Process -Name $name -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }

    $exe = Get-WinMintAgentEverythingExePath
    if ([string]::IsNullOrWhiteSpace($exe)) {
        throw 'Everything executable was not found after installation.'
    }

    $exeDir = Split-Path -Parent $exe
    $appDataDir = Join-Path $env:APPDATA 'Everything'
    $iniPaths = @(
        (Join-Path $exeDir 'Everything.ini'),
        (Join-Path $exeDir 'Everything-1.5a.ini'),
        (Join-Path $appDataDir 'Everything.ini'),
        (Join-Path $appDataDir 'Everything-1.5a.ini')
    ) | Select-Object -Unique
    $excludeList = @(
        'C:\$Recycle.Bin\**',
        'C:\Windows\SoftwareDistribution\**',
        'C:\Windows\WinSxS\**',
        'C:\Windows\Installer\**',
        'C:\ProgramData\Microsoft\Windows\WER\**',
        'C:\Users\*\AppData\Local\Temp\**'
    )

    foreach ($ini in $iniPaths) {
        try {
            foreach ($setting in @(
                    @{ Name = 'app_data'; Value = '1' },
                    @{ Name = 'alpha_instance'; Value = '0' },
                    @{ Name = 'service_name'; Value = 'Everything' },
                    @{ Name = 'service_pipe_name'; Value = '\\.\PIPE\Everything Service' },
                    @{ Name = 'allow_multiple_windows'; Value = '0' },
                    @{ Name = 'run_in_background'; Value = '1' },
                    @{ Name = 'show_tray_icon'; Value = '0' },
                    @{ Name = 'http_server_enabled'; Value = '0' },
                    @{ Name = 'etp_server_enabled'; Value = '0' },
                    @{ Name = 'ftp_server_enabled'; Value = '0' },
                    @{ Name = 'content_index_enabled'; Value = '0' },
                    @{ Name = 'exclude_hidden_files_and_folders'; Value = '1' },
                    @{ Name = 'exclude_system_files_and_folders'; Value = '1' },
                    @{ Name = 'exclude_list_enabled'; Value = '1' },
                    @{ Name = 'exclude_list'; Value = ($excludeList -join ';') }
                )) {
                Set-WinMintAgentIniValue -Path $ini -Name $setting.Name -Value $setting.Value
            }
        }
        catch {
            Write-AgentLog "Everything config warning for ${ini}: $($_.Exception.Message)"
        }
    }

    try {
        $marker = Join-Path $exeDir 'NO_ALPHA_INSTANCE'
        if (-not (Test-Path -LiteralPath $marker)) {
            [System.IO.File]::WriteAllText($marker, '', [System.Text.UTF8Encoding]::new($false))
        }
    }
    catch {
        Write-AgentLog "Everything NO_ALPHA_INSTANCE warning: $($_.Exception.Message)"
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

    $State.steps[$key] = @{
        status = 'ok'
        updatedAt = (Get-Date -Format o)
        exe = $exe
        package = $PackageId
        iniPaths = @($iniPaths)
        localFilesystemOnly = $true
        trayIcon = 'hidden'
        serverSearch = 'disabled'
        sdkSearch = 'disabled'
        excludeHiddenFilesAndFolders = $true
        excludeSystemFilesAndFolders = $true
        excludeList = @($excludeList)
    }
    Save-AgentState -State $State
}

function Install-WinMintRaycastEverythingBackend {
    param(
        [Parameter(Mandatory)][object]$RaycastConfig,
        [Parameter(Mandatory)][hashtable]$State
    )

    $backend = if ($RaycastConfig.PSObject.Properties['everythingBackend']) { $RaycastConfig.everythingBackend } else { $null }
    if (-not $backend -or -not [bool]$backend.enabled) { return $false }

    $packageId = if ($backend.PSObject.Properties['package']) { [string]$backend.package } else { 'everything' }
    if ([string]::IsNullOrWhiteSpace($packageId)) { $packageId = 'everything' }

    Install-AgentManifestTool -ToolId $packageId -State $State
    Set-WinMintAgentEverythingConfiguration -State $State -PackageId $packageId
    return $true
}

function Request-WinMintRaycastExtensionInstall {
    param(
        [Parameter(Mandatory)][object]$Extension,
        [Parameter(Mandatory)][hashtable]$State
    )

    $id = [string]$Extension.id
    $owner = [string]$Extension.owner
    if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($owner)) { return $false }

    $key = "raycast-extension:$id"
    if (-not $Force -and $State.steps.ContainsKey($key) -and [string]$State.steps[$key].status -eq 'ok') {
        return $true
    }

    $uri = "raycast://extensions/$owner/$id?source=winmint"
    try {
        Start-Process -FilePath $uri -ErrorAction Stop
        $State.steps[$key] = @{
            status = 'ok'
            updatedAt = (Get-Date -Format o)
            owner = $owner
            extension = $id
            uri = $uri
            installRequest = 'requested'
        }
        Save-AgentState -State $State
        return $true
    }
    catch {
        $State.steps[$key] = @{
            status = 'failed'
            updatedAt = (Get-Date -Format o)
            owner = $owner
            extension = $id
            uri = $uri
            error = $_.Exception.Message
        }
        Save-AgentState -State $State
        Write-AgentLog "Raycast extension request failed for ${owner}/${id}: $($_.Exception.Message)"
        return $false
    }
}

function Start-WinMintRaycastApp {
    param([Parameter(Mandatory)][hashtable]$State)

    $key = 'config:raycast-start'
    if (-not (Get-Command Resolve-WinMintAgentStartAppAumid -ErrorAction SilentlyContinue)) {
        return
    }

    $aumid = Resolve-WinMintAgentStartAppAumid -Name 'Raycast'
    if ([string]::IsNullOrWhiteSpace($aumid)) { return }

    try {
        $explorer = Join-Path $env:SystemRoot 'explorer.exe'
        Start-Process -FilePath $explorer -ArgumentList "shell:AppsFolder\$aumid" -WindowStyle Hidden -ErrorAction Stop
        $State.steps[$key] = @{
            status = 'ok'
            updatedAt = (Get-Date -Format o)
            aumid = $aumid
        }
        Save-AgentState -State $State
    }
    catch {
        Write-AgentLog "Raycast start warning: $($_.Exception.Message)"
    }
}

function Invoke-WinMintAgentRaycastBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    $cfg = Get-WinMintAgentRaycastConfig -AgentProfile $AgentProfile
    if (-not $cfg -or -not [bool]$cfg.enabled) {
        return [pscustomobject]@{
            Id      = 'raycast'
            Status  = 'skipped'
            Message = 'Raycast was not selected.'
        }
    }

    Install-AgentManifestTool -ToolId 'raycast' -State $State
    $requiredStateSteps = [System.Collections.Generic.List[string]]::new()
    $requiredStateSteps.Add((Get-AgentManifestToolStateKey -ToolId 'raycast')) | Out-Null
    Start-WinMintRaycastApp -State $State
    $everythingConfigured = Install-WinMintRaycastEverythingBackend -RaycastConfig $cfg -State $State
    if ($everythingConfigured) {
        $requiredStateSteps.Add('config:everything-search-backend') | Out-Null
    }

    $requested = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()
    foreach ($extension in @($cfg.extensions)) {
        if (Request-WinMintRaycastExtensionInstall -Extension $extension -State $State) {
            $requested.Add([string]$extension.id) | Out-Null
        }
        else {
            $failed.Add([string]$extension.id) | Out-Null
        }
    }

    [pscustomobject]@{
        Id      = 'raycast'
        Status  = if ($failed.Count -gt 0) { 'retryable' } else { 'ok' }
        Message = "Raycast installed. Extensions requested: $($requested.Count). Everything backend: $everythingConfigured."
        ExtensionsRequested = @($requested)
        ExtensionsFailed = @($failed)
        RequiredStateSteps = @($requiredStateSteps)
    }
}

