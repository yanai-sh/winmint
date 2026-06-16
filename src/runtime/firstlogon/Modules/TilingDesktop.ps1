#Requires -Version 7.3

function Get-WinMintShellLayerConfig {
    param([Parameter(Mandatory)][object]$AgentProfile)

    if (-not $AgentProfile.modules) { return $null }
    $prop = $AgentProfile.modules.PSObject.Properties['shell']
    if ($prop) { return $prop.Value }
    return $null
}

function Resolve-WinMintYasbCli {
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

function Resolve-WinMintKomorebiCli {
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

function Resolve-WinMintThideCli {
    $cmd = Get-Command -Name @('thide.exe', 'thide') -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($cmd) { return $cmd.Source }

    foreach ($candidate in @(
            (Join-Path $env:ProgramFiles 'thide\bin\thide.exe'),
            (Join-Path $env:ProgramFiles 'thide\thide.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\thide\thide.exe')
        )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }

    return $null
}

function Invoke-WinMintYasbCli {
    param(
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [switch]$AllowFailure
    )

    $yasbc = Resolve-WinMintYasbCli
    if (-not $yasbc) { throw 'yasbc.exe was not found after installing YASB.' }

    try {
        Invoke-AgentNative -FilePath $yasbc -ArgumentList $ArgumentList
    }
    catch {
        if (-not $AllowFailure) { throw }
        Write-AgentLog "YASB command ignored failure: yasbc $($ArgumentList -join ' ') :: $($_.Exception.Message)"
    }
}

function Invoke-WinMintKomorebiCli {
    param(
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [switch]$AllowFailure
    )

    $komorebic = Resolve-WinMintKomorebiCli
    if (-not $komorebic) { throw 'komorebic.exe was not found after installing Komorebi.' }

    try {
        Invoke-AgentNative -FilePath $komorebic -ArgumentList $ArgumentList
    }
    catch {
        if (-not $AllowFailure) { throw }
        Write-AgentLog "Komorebi command ignored failure: komorebic $($ArgumentList -join ' ') :: $($_.Exception.Message)"
    }
}

function Invoke-WinMintThideCli {
    param(
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [switch]$AllowFailure
    )

    $thide = Resolve-WinMintThideCli
    if (-not $thide) { throw 'thide.exe was not found after installation.' }

    try {
        Invoke-AgentNative -FilePath $thide -ArgumentList $ArgumentList
    }
    catch {
        if (-not $AllowFailure) { throw }
        Write-AgentLog "thide command ignored failure: thide $($ArgumentList -join ' ') :: $($_.Exception.Message)"
    }
}

function Get-WinMintThideReleaseAssetUrl {
    $arch = Get-AgentTargetArchitecture
    $assetPattern = switch ($arch) {
        'arm64' { 'arm64.msi$' }
        'amd64' { 'x64.msi$' }
        default { throw "thide does not publish a WinMint-supported installer for target architecture '$arch'." }
    }

    $release = Invoke-RestMethod -UseBasicParsing -Uri 'https://api.github.com/repos/amnweb/thide/releases/latest' -Headers @{
        'User-Agent' = 'WinMint'
        'Accept' = 'application/vnd.github+json'
    } -ErrorAction Stop

    foreach ($asset in @($release.assets)) {
        $name = [string]$asset.name
        if ($name -match $assetPattern -and -not ($name -match 'portable')) {
            return [pscustomobject]@{
                Name = $name
                Url = [string]$asset.browser_download_url
                Version = [string]$release.tag_name
            }
        }
    }

    throw "No thide MSI asset matched target architecture '$arch'."
}

function Backup-WinMintYasbConfig {
    param([Parameter(Mandatory)][string]$ConfigDir)

    if (-not (Test-Path -LiteralPath $ConfigDir)) { return $null }
    $existingFiles = @(
        Get-ChildItem -LiteralPath $ConfigDir -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch '\.log$' }
    )
    if ($existingFiles.Count -eq 0) { return $null }

    $backupRoot = Join-Path $env:LOCALAPPDATA 'WinMint\Backups\Yasb'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupDir = Join-Path $backupRoot $stamp
    $null = New-Item -ItemType Directory -Path $backupDir -Force
    foreach ($item in $existingFiles) {
        Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $backupDir $item.Name) -Recurse -Force
    }
    Write-AgentLog "YASB config backup created at $backupDir"
    return $backupDir
}

function Backup-WinMintKomorebiConfig {
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

    $backupRoot = Join-Path $env:LOCALAPPDATA 'WinMint\Backups\Komorebi'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupDir = Join-Path $backupRoot $stamp
    $null = New-Item -ItemType Directory -Path $backupDir -Force
    foreach ($source in $existing) {
        Copy-Item -LiteralPath $source.Path -Destination (Join-Path $backupDir $source.Name) -Recurse -Force
    }
    Write-AgentLog "Komorebi config backup created at $backupDir"
    return $backupDir
}

function Copy-WinMintYasbPreset {
    $assetDir = Join-Path $agentRoot 'Assets\Yasb'
    if (-not (Test-Path -LiteralPath $assetDir)) {
        throw "YASB preset assets were not staged: $assetDir"
    }

    $configDir = Join-Path $env:USERPROFILE '.config\yasb'
    $backupDir = Backup-WinMintYasbConfig -ConfigDir $configDir
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

function Copy-WinMintKomorebiPreset {
    $assetDir = Join-Path $agentRoot 'Assets\Komorebi'
    if (-not (Test-Path -LiteralPath $assetDir)) {
        throw "Komorebi preset assets were not staged: $assetDir"
    }

    $configDir = Join-Path $env:USERPROFILE '.config\komorebi'
    $whkdDir = Join-Path $env:USERPROFILE '.config\whkdrc'
    $backupDir = Backup-WinMintKomorebiConfig -ConfigDir $configDir -WhkdDir $whkdDir
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

function Enable-WinMintYasbAutostart {
    try {
        Invoke-WinMintYasbCli -ArgumentList @('enable-autostart')
        return
    }
    catch {
        Write-AgentLog "YASB user autostart failed: $($_.Exception.Message)"
    }

    if (Test-AgentProcessElevated) {
        Invoke-WinMintYasbCli -ArgumentList @('enable-autostart', '--task')
        return
    }

    throw 'YASB autostart could not be enabled.'
}

function Enable-WinMintKomorebiAutostart {
    $configPath = Join-Path $env:KOMOREBI_CONFIG_HOME 'komorebi.json'
    Invoke-WinMintKomorebiCli -ArgumentList @('enable-autostart', '--whkd', '--config', $configPath)
}

function Install-WinMintYasbLayer {
    param([Parameter(Mandatory)][hashtable]$State)

    Install-AgentManifestTool -ToolId 'yasb' -State $State
    Copy-WinMintYasbPreset
    Invoke-WinMintYasbCli -ArgumentList @('stop') -AllowFailure
    Enable-WinMintYasbAutostart
    Invoke-WinMintYasbCli -ArgumentList @('start')
}

function Install-WinMintKomorebiLayer {
    param([Parameter(Mandatory)][hashtable]$State)

    Install-AgentManifestTool -ToolId 'komorebi' -State $State
    Install-AgentManifestTool -ToolId 'whkd' -State $State
    Copy-WinMintKomorebiPreset
    Invoke-WinMintKomorebiCli -ArgumentList @('stop') -AllowFailure
    Get-Process -Name 'whkd' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Invoke-WinMintKomorebiCli -ArgumentList @('fetch-app-specific-configuration') -AllowFailure
    Enable-WinMintKomorebiAutostart
    $configPath = Join-Path $env:KOMOREBI_CONFIG_HOME 'komorebi.json'
    Invoke-WinMintKomorebiCli -ArgumentList @('start', '--whkd', '--config', $configPath, '--clean-state')
}

function Install-WinMintNilesoftLayer {
    param([Parameter(Mandatory)][hashtable]$State)

    Install-AgentManifestTool -ToolId 'nilesoft' -State $State
}

function Install-WinMintThideLayer {
    param([Parameter(Mandatory)][hashtable]$State)

    $key = 'shell:thide'
    if (-not $Force -and $State.steps.ContainsKey($key) -and [string]$State.steps[$key].status -eq 'ok') {
        Write-AgentConsoleLine -Level OK -Message 'thide already configured.'
        return
    }

    $State.steps[$key] = @{
        status = 'running'
        startedAt = (Get-Date -Format o)
        updatedAt = (Get-Date -Format o)
    }
    Save-AgentState -State $State

    try {
        $thide = Resolve-WinMintThideCli
        $releaseAsset = $null
        if (-not $thide) {
            $releaseAsset = Get-WinMintThideReleaseAssetUrl
            $downloadDir = Join-Path $env:TEMP 'WinMint-thide'
            $null = New-Item -ItemType Directory -Path $downloadDir -Force
            $msiPath = Join-Path $downloadDir ([string]$releaseAsset.Name)
            Invoke-WebRequest -UseBasicParsing -Uri ([string]$releaseAsset.Url) -OutFile $msiPath -ErrorAction Stop
            $msiexec = Join-Path $env:SystemRoot 'System32\msiexec.exe'
            Invoke-AgentNative -FilePath $msiexec -ArgumentList @('/i', $msiPath, '/qn', '/norestart')
            Update-AgentProcessPath
            $thide = Resolve-WinMintThideCli
        }

        if (-not $thide) { throw 'thide installer completed, but thide.exe was not found.' }
        Invoke-WinMintThideCli -ArgumentList @('enable-autostart') -AllowFailure
        Invoke-WinMintThideCli -ArgumentList @('start') -AllowFailure

        $State.steps[$key] = @{
            status = 'ok'
            updatedAt = (Get-Date -Format o)
            command = $thide
            release = if ($releaseAsset) { [string]$releaseAsset.Version } else { 'existing' }
        }
        Save-AgentState -State $State
    }
    catch {
        $State.steps[$key] = @{
            status = 'failed'
            updatedAt = (Get-Date -Format o)
            error = $_.Exception.Message
        }
        Save-AgentState -State $State
        throw
    }
}

function Invoke-WinMintAgentTilingDesktopBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    $shell = Get-WinMintShellLayerConfig -AgentProfile $AgentProfile
    if (-not $shell) {
        return [pscustomobject]@{
            Id      = 'tiling-desktop'
            Status  = 'skipped'
            Message = 'No desktop shell layers selected.'
        }
    }

    $completed = [System.Collections.Generic.List[string]]::new()

    if ([bool]$shell.yasb) {
        Install-WinMintYasbLayer -State $State
        $completed.Add('YASB') | Out-Null
    }
    if ([bool]$shell.thide) {
        Install-WinMintThideLayer -State $State
        $completed.Add('thide') | Out-Null
    }
    if ([bool]$shell.nilesoft) {
        Install-WinMintNilesoftLayer -State $State
        $completed.Add('Nilesoft Shell') | Out-Null
    }
    if ([bool]$shell.komorebi) {
        Install-WinMintKomorebiLayer -State $State
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
