#Requires -Version 7.3

function Get-WinWSShellLayerConfig {
    param([Parameter(Mandatory)][object]$AgentProfile)

    if (-not $AgentProfile.modules) { return $null }
    $prop = $AgentProfile.modules.PSObject.Properties['shell']
    if ($prop) { return $prop.Value }
    return $null
}

function Resolve-WinWSYasbCli {
    $cmd = Get-Command -Name @('yasbc.exe', 'yasbc') -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'YASB\yasbc.exe'),
        (Join-Path $env:ProgramFiles 'yasb\yasbc.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\YASB\yasbc.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\yasb\yasbc.exe')
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }

    return $null
}

function Resolve-WinWSKomorebiCli {
    $cmd = Get-Command -Name 'komorebic.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'komorebi\bin\komorebic.exe'),
        (Join-Path $env:ProgramFiles 'komorebi\komorebic.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\komorebic.exe')
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }

    return $null
}

function Invoke-WinWSYasbCli {
    param(
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [switch]$AllowFailure
    )

    $yasbc = Resolve-WinWSYasbCli
    if (-not $yasbc) { throw 'yasbc.exe was not found after installing YASB.' }

    try {
        Invoke-AgentNative -FilePath $yasbc -ArgumentList $ArgumentList
    }
    catch {
        if (-not $AllowFailure) { throw }
        Write-AgentLog "YASB command ignored failure: yasbc $($ArgumentList -join ' ') :: $($_.Exception.Message)"
    }
}

function Invoke-WinWSKomorebiCli {
    param(
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [switch]$AllowFailure
    )

    $komorebic = Resolve-WinWSKomorebiCli
    if (-not $komorebic) { throw 'komorebic.exe was not found after installing Komorebi.' }

    try {
        Invoke-AgentNative -FilePath $komorebic -ArgumentList $ArgumentList
    }
    catch {
        if (-not $AllowFailure) { throw }
        Write-AgentLog "Komorebi command ignored failure: komorebic $($ArgumentList -join ' ') :: $($_.Exception.Message)"
    }
}

function Backup-WinWSYasbConfig {
    param([Parameter(Mandatory)][string]$ConfigDir)

    if (-not (Test-Path -LiteralPath $ConfigDir)) { return $null }
    $existingFiles = @(
        Get-ChildItem -LiteralPath $ConfigDir -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch '\.log$' }
    )
    if ($existingFiles.Count -eq 0) { return $null }

    $backupRoot = Join-Path $env:LOCALAPPDATA 'WinWS\Backups\Yasb'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupDir = Join-Path $backupRoot $stamp
    $null = New-Item -ItemType Directory -Path $backupDir -Force
    foreach ($item in $existingFiles) {
        Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $backupDir $item.Name) -Recurse -Force
    }
    Write-AgentLog "YASB config backup created at $backupDir"
    return $backupDir
}

function Backup-WinWSKomorebiConfig {
    param(
        [Parameter(Mandatory)][string]$ConfigDir,
        [Parameter(Mandatory)][string]$WhkdDir
    )

    $sources = @(
        [pscustomobject]@{ Name = 'komorebi'; Path = $ConfigDir },
        [pscustomobject]@{ Name = 'whkdrc'; Path = $WhkdDir }
    )
    $existing = @($sources | Where-Object { Test-Path -LiteralPath $_.Path })
    if ($existing.Count -eq 0) { return $null }

    $backupRoot = Join-Path $env:LOCALAPPDATA 'WinWS\Backups\Komorebi'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupDir = Join-Path $backupRoot $stamp
    $null = New-Item -ItemType Directory -Path $backupDir -Force
    foreach ($source in $existing) {
        Copy-Item -LiteralPath $source.Path -Destination (Join-Path $backupDir $source.Name) -Recurse -Force
    }
    Write-AgentLog "Komorebi config backup created at $backupDir"
    return $backupDir
}

function Copy-WinWSYasbPreset {
    $assetDir = Join-Path $agentRoot 'Assets\Yasb'
    if (-not (Test-Path -LiteralPath $assetDir)) {
        throw "YASB preset assets were not staged: $assetDir"
    }

    $configDir = Join-Path $env:USERPROFILE '.config\yasb'
    $backupDir = Backup-WinWSYasbConfig -ConfigDir $configDir
    $null = New-Item -ItemType Directory -Path $configDir -Force
    foreach ($name in @('config.yaml', 'styles.css')) {
        $source = Join-Path $assetDir $name
        if (-not (Test-Path -LiteralPath $source)) {
            throw "YASB preset file is missing: $source"
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path $configDir $name) -Force
    }

    Write-AgentLog "YASB preset copied to $configDir"
    if ($backupDir) { Write-AgentConsoleLine -Level Info -Message "Existing YASB config backed up." }
}

function Copy-WinWSKomorebiPreset {
    $assetDir = Join-Path $agentRoot 'Assets\Komorebi'
    if (-not (Test-Path -LiteralPath $assetDir)) {
        throw "Komorebi preset assets were not staged: $assetDir"
    }

    $configDir = Join-Path $env:USERPROFILE '.config\komorebi'
    $whkdDir = Join-Path $env:USERPROFILE '.config\whkdrc'
    $backupDir = Backup-WinWSKomorebiConfig -ConfigDir $configDir -WhkdDir $whkdDir
    $null = New-Item -ItemType Directory -Path $configDir -Force
    $null = New-Item -ItemType Directory -Path $whkdDir -Force
    foreach ($name in @('komorebi.json', 'applications.json')) {
        $source = Join-Path $assetDir $name
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Komorebi preset file is missing: $source"
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path $configDir $name) -Force
    }

    $whkdSource = Join-Path $assetDir 'whkdrc'
    if (-not (Test-Path -LiteralPath $whkdSource)) {
        throw "Komorebi preset file is missing: $whkdSource"
    }
    Copy-Item -LiteralPath $whkdSource -Destination (Join-Path $whkdDir 'whkdrc') -Force
    [Environment]::SetEnvironmentVariable('KOMOREBI_CONFIG_HOME', $configDir, 'User')
    [Environment]::SetEnvironmentVariable('WHKD_CONFIG_HOME', $whkdDir, 'User')
    $env:KOMOREBI_CONFIG_HOME = $configDir
    $env:WHKD_CONFIG_HOME = $whkdDir

    Write-AgentLog "Komorebi preset copied to $configDir and $whkdDir"
    if ($backupDir) { Write-AgentConsoleLine -Level Info -Message "Existing Komorebi config backed up." }
}

function Enable-WinWSYasbAutostart {
    try {
        Invoke-WinWSYasbCli -ArgumentList @('enable-autostart')
        return
    }
    catch {
        Write-AgentLog "YASB user autostart failed: $($_.Exception.Message)"
    }

    if (Test-AgentProcessElevated) {
        Invoke-WinWSYasbCli -ArgumentList @('enable-autostart', '--task')
        return
    }

    throw 'YASB autostart could not be enabled.'
}

function Enable-WinWSKomorebiAutostart {
    $configPath = Join-Path $env:KOMOREBI_CONFIG_HOME 'komorebi.json'
    Invoke-WinWSKomorebiCli -ArgumentList @('enable-autostart', '--whkd', '--config', $configPath)
}

function Install-WinWSYasbLayer {
    param([Parameter(Mandatory)][hashtable]$State)

    Install-AgentManifestTool -ToolId 'yasb' -State $State
    Copy-WinWSYasbPreset
    Invoke-WinWSYasbCli -ArgumentList @('stop') -AllowFailure
    Enable-WinWSYasbAutostart
    Invoke-WinWSYasbCli -ArgumentList @('start')
}

function Install-WinWSKomorebiLayer {
    param([Parameter(Mandatory)][hashtable]$State)

    Install-AgentManifestTool -ToolId 'komorebi' -State $State
    Install-AgentManifestTool -ToolId 'whkd' -State $State
    Copy-WinWSKomorebiPreset
    Invoke-WinWSKomorebiCli -ArgumentList @('stop') -AllowFailure
    Get-Process -Name 'whkd' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Invoke-WinWSKomorebiCli -ArgumentList @('fetch-app-specific-configuration') -AllowFailure
    Enable-WinWSKomorebiAutostart
    $configPath = Join-Path $env:KOMOREBI_CONFIG_HOME 'komorebi.json'
    Invoke-WinWSKomorebiCli -ArgumentList @('start', '--whkd', '--config', $configPath, '--clean-state')
}

function Invoke-WinWSAgentTilingDesktopBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    $shell = Get-WinWSShellLayerConfig -AgentProfile $AgentProfile
    if (-not $shell) {
        return [pscustomobject]@{
            Id      = 'tiling-desktop'
            Status  = 'skipped'
            Message = 'No desktop shell layers selected.'
        }
    }

    $completed = [System.Collections.Generic.List[string]]::new()

    if ([bool]$shell.yasb) {
        Install-WinWSYasbLayer -State $State
        $completed.Add('YASB') | Out-Null
    }
    if ([bool]$shell.komorebi) {
        Install-WinWSKomorebiLayer -State $State
        $completed.Add('Komorebi') | Out-Null
        if ([bool]$shell.whkd) { $completed.Add('whkd') | Out-Null }
    }

    if ($completed.Count -eq 0) {
        return [pscustomobject]@{
            Id      = 'tiling-desktop'
            Status  = 'skipped'
            Message = 'Standard Windows desktop selected.'
        }
    }

    [pscustomobject]@{
        Id      = 'tiling-desktop'
        Status  = 'ok'
        Message = "Configured: $($completed -join ', ')."
    }
}
