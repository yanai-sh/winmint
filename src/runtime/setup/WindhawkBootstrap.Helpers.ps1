#Requires -Version 5.1

function Write-WindhawkLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $line = "[{0}] {1}" -f $Level, $Message
    $color = switch ($Level) {
        'OK' { 'Green' }
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
        default { 'Cyan' }
    }
    Write-Host $line -ForegroundColor $color
    try {
        $logParent = Split-Path -Parent $LogPath
        if (-not (Test-Path -LiteralPath $logParent)) {
            $null = New-Item -ItemType Directory -Path $logParent -Force
        }
        "$(Get-Date -Format o) $line" | Out-File -LiteralPath $LogPath -Append -Encoding utf8
    }
    catch { }
}

function Test-WindowsHost {
    return [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

function Test-Administrator {
    try {
        $probeKey = 'HKLM\SOFTWARE\WinMint\ElevationProbe'
        & reg.exe add $probeKey /v Probe /t REG_SZ /d 1 /f *> $null
        if ($LASTEXITCODE -eq 0) {
            & reg.exe delete $probeKey /f *> $null | Out-Null
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

function Get-WindhawkHostArchitecture {
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch -Regex ([string]$arch) {
        'ARM64' {
            return [pscustomobject]@{
                Name = 'arm64'
                CompilerTarget = 'aarch64-w64-mingw32'
                NativeSubfolder = 'arm64'
            }
        }
        'AMD64' {
            return [pscustomobject]@{
                Name = 'amd64'
                CompilerTarget = 'x86_64-w64-mingw32'
                NativeSubfolder = '64'
            }
        }
        'x86' {
            return [pscustomobject]@{
                Name = 'x86'
                CompilerTarget = 'i686-w64-mingw32'
                NativeSubfolder = '32'
            }
        }
        default {
            throw "Unsupported Windows architecture: $arch"
        }
    }
}

function Get-WindhawkArchitectureSubfolder {
    param(
        [string[]]$Architecture,
        [Parameter(Mandatory)][object]$HostArchitecture
    )

    $subfolders = [System.Collections.Generic.List[string]]::new()
    $archs = @($Architecture | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($archs.Count -eq 0) { $archs = @('x86', 'x86-64') }

    foreach ($arch in $archs) {
        switch ($arch) {
            'x86' {
                if (-not $subfolders.Contains('32')) { $subfolders.Add('32') }
            }
            'x86-64' {
                if ($HostArchitecture.Name -eq 'arm64') {
                    if (-not $subfolders.Contains('64')) { $subfolders.Add('64') }
                    if (-not $subfolders.Contains('arm64')) { $subfolders.Add('arm64') }
                }
                elseif ($HostArchitecture.Name -eq 'amd64') {
                    if (-not $subfolders.Contains('64')) { $subfolders.Add('64') }
                }
            }
            'amd64' {
                if ($HostArchitecture.Name -eq 'amd64' -and -not $subfolders.Contains('64')) { $subfolders.Add('64') }
            }
            'arm64' {
                if ($HostArchitecture.Name -eq 'arm64' -and -not $subfolders.Contains('arm64')) { $subfolders.Add('arm64') }
            }
            default {
                throw "Unsupported Windhawk mod architecture metadata: $arch"
            }
        }
    }

    if ($subfolders.Count -eq 0) {
        throw "No compatible Windhawk mod DLL target for host architecture $($HostArchitecture.Name)."
    }
    return $subfolders.ToArray()
}

function Get-WindhawkCompilerTargetForSubfolder {
    param([Parameter(Mandatory)][string]$Subfolder)
    switch ($Subfolder) {
        '32' { 'i686-w64-mingw32' }
        '64' { 'x86_64-w64-mingw32' }
        'arm64' { 'aarch64-w64-mingw32' }
        default { throw "Unknown Windhawk architecture subfolder: $Subfolder" }
    }
}

function Get-WindhawkInstallRootCandidate {
    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($WindhawkInstallRoot) { $candidates.Add($WindhawkInstallRoot) }
    if ($env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles 'Windhawk')) }
    if (${env:ProgramFiles(x86)}) { $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'Windhawk')) }

    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='Windhawk'" -ErrorAction SilentlyContinue
    if ($svc -and $svc.PathName) {
        $pathName = [string]$svc.PathName
        $exePath = if ($pathName -match '^\s*"([^"]+)"') { $matches[1] } else { ($pathName -split '\s+', 2)[0] }
        if ($exePath -and (Split-Path -Parent $exePath)) {
            $candidates.Add((Split-Path -Parent $exePath))
        }
    }

    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($root in $uninstallRoots) {
        Get-ItemProperty -Path $root -ErrorAction SilentlyContinue |
            Where-Object {
                $_.PSObject.Properties['DisplayName'] -and
                $_.PSObject.Properties['InstallLocation'] -and
                $_.DisplayName -eq 'Windhawk' -and
                $_.InstallLocation
            } |
            ForEach-Object { $candidates.Add([string]$_.InstallLocation) }
    }

    return $candidates.ToArray() | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
}

function Resolve-WindhawkInstallRoot {
    foreach ($candidate in Get-WindhawkInstallRootCandidate) {
        $exe = Join-Path $candidate 'windhawk.exe'
        $compiler = Join-Path $candidate 'Compiler'
        if ((Test-Path -LiteralPath $exe) -and (Test-Path -LiteralPath $compiler)) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }
    throw 'Windhawk install root was not found.'
}

function Get-WindhawkInstalledExe {
    foreach ($candidate in Get-WindhawkInstallRootCandidate) {
        $exe = Join-Path $candidate 'windhawk.exe'
        if ($exe -and (Test-Path -LiteralPath $exe)) { return $exe }
    }
    return $null
}

function Stop-WindhawkRuntime {
    $svc = Get-Service -Name 'Windhawk' -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Stopped') {
        Write-WindhawkLog 'Stopping Windhawk service.'
        Stop-Service -Name 'Windhawk' -Force -ErrorAction SilentlyContinue
        try { $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15)) } catch { }
    }

    Get-Process -Name 'windhawk' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Write-WindhawkLog "Stopping Windhawk process $($_.Id)."
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
        catch { }
    }
}

function Start-WindhawkRuntime {
    $svc = Get-Service -Name 'Windhawk' -ErrorAction SilentlyContinue
    if ($svc) {
        try {
            if ($svc.Status -ne 'Running') {
                Write-WindhawkLog 'Starting Windhawk service.'
                Start-Service -Name 'Windhawk'
            }
        }
        catch {
            Write-WindhawkLog "Windhawk service start warning: $($_.Exception.Message)" -Level WARN
        }
    }

    $exe = Get-WindhawkInstalledExe
    if ($exe) {
        Write-WindhawkLog 'Restarting Windhawk tray process.'
        Start-Process -FilePath $exe -ArgumentList @('-restart', '-tray-only') -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
    }
}

function Copy-WindhawkRuntimeHelper {
    param([Parameter(Mandatory)][string]$Subfolder)

    $target = Get-WindhawkCompilerTargetForSubfolder -Subfolder $Subfolder
    $compilerBin = Join-Path $WindhawkInstallRoot "Compiler\$target\bin"
    if (-not (Test-Path -LiteralPath $compilerBin)) {
        throw "Windhawk compiler runtime not found: $compilerBin"
    }

    $destination = Join-Path $WindhawkRoot "Engine\Mods\$Subfolder"
    $null = New-Item -ItemType Directory -Path $destination -Force

    $copies = @(
        @{ From = 'libc++.dll'; To = 'libc++.whl' },
        @{ From = 'libunwind.dll'; To = 'libunwind.whl' },
        @{ From = 'windhawk-mod-shim.dll'; To = 'windhawk-mod-shim.dll' }
    )
    foreach ($copy in $copies) {
        $src = Join-Path $compilerBin $copy.From
        $dst = Join-Path $destination $copy.To
        if (-not (Test-Path -LiteralPath $src)) { throw "Windhawk runtime helper missing: $src" }
        try {
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
        catch {
            if (Test-Path -LiteralPath $dst) {
                Write-WindhawkLog "Keeping existing loaded helper $($copy.To)." -Level WARN
            }
            else {
                throw
            }
        }
    }
    Write-WindhawkLog "Staged Windhawk runtime helpers for $Subfolder." -Level OK
}

function Invoke-WindhawkDownload {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile
    )

    $parent = Split-Path -Parent $OutFile
    if (-not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
}

function Resolve-WindhawkModVersion {
    param([Parameter(Mandatory)][object]$Mod)

    $version = [string]$Mod.version
    if ($version -and $version -ne 'latest') { return $version }

    $versionsUri = ('{0}/{1}/versions.json' -f $ModsBaseUrl.TrimEnd('/'), $Mod.id)
    $versions = @(Invoke-RestMethod -Uri $versionsUri -UseBasicParsing)
    if ($versions.Count -eq 0) { throw "No versions reported for Windhawk mod: $($Mod.id)" }
    $latest = $versions | Sort-Object { [int64]$_.timestamp } | Select-Object -Last 1
    return [string]$latest.version
}

function Set-WindhawkDwordValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value
    )
    $raw = if ($Value -is [bool]) { if ($Value) { 1 } else { 0 } } else { [int64]$Value }
    if ($raw -lt 0) { $raw = 4294967296 + $raw }
    $dword = [uint32]$raw
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $dword -Force | Out-Null
}

function Set-WindhawkStringValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()]$Value
    )
    New-ItemProperty -Path $Path -Name $Name -PropertyType String -Value ([string]$Value) -Force | Out-Null
}

function Set-WindhawkModRegistry {
    param(
        [Parameter(Mandatory)][object]$Mod,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$LibraryFileName
    )

    $modPath = "HKLM:\SOFTWARE\Windhawk\Engine\Mods\$($Mod.id)"
    $null = New-Item -Path $modPath -Force

    Set-WindhawkStringValue -Path $modPath -Name 'LibraryFileName' -Value $LibraryFileName
    $disabled = if ($Mod.PSObject.Properties['disabled']) { [bool]$Mod.disabled } else { $false }
    Set-WindhawkDwordValue -Path $modPath -Name 'Disabled' -Value $disabled
    Set-WindhawkStringValue -Path $modPath -Name 'Include' -Value (@($Mod.include) -join '|')
    Set-WindhawkStringValue -Path $modPath -Name 'Exclude' -Value (@($Mod.exclude) -join '|')
    Set-WindhawkStringValue -Path $modPath -Name 'Architecture' -Value (@($Mod.architecture) -join '|')
    Set-WindhawkStringValue -Path $modPath -Name 'Version' -Value $Version
    Set-WindhawkDwordValue -Path $modPath -Name 'SettingsChangeTime' -Value ([int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds())

    foreach ($optionalStringArray in @('includeCustom', 'excludeCustom')) {
        if ($Mod.PSObject.Properties[$optionalStringArray]) {
            $storageName = switch ($optionalStringArray) {
                'includeCustom' { 'IncludeCustom' }
                'excludeCustom' { 'ExcludeCustom' }
            }
            Set-WindhawkStringValue -Path $modPath -Name $storageName -Value (@($Mod.$optionalStringArray) -join '|')
        }
    }
    foreach ($optionalBoolean in @('loggingEnabled', 'debugLoggingEnabled', 'includeExcludeCustomOnly', 'patternsMatchCriticalSystemProcesses')) {
        if ($Mod.PSObject.Properties[$optionalBoolean]) {
            $storageName = switch ($optionalBoolean) {
                'loggingEnabled' { 'LoggingEnabled' }
                'debugLoggingEnabled' { 'DebugLoggingEnabled' }
                'includeExcludeCustomOnly' { 'IncludeExcludeCustomOnly' }
                'patternsMatchCriticalSystemProcesses' { 'PatternsMatchCriticalSystemProcesses' }
            }
            Set-WindhawkDwordValue -Path $modPath -Name $storageName -Value ([bool]$Mod.$optionalBoolean)
        }
    }

    $settingsPath = Join-Path $modPath 'Settings'
    if (Test-Path -LiteralPath $settingsPath) {
        Remove-Item -LiteralPath $settingsPath -Recurse -Force
    }
    $null = New-Item -Path $settingsPath -Force

    if ($Mod.PSObject.Properties['settings'] -and $Mod.settings) {
        foreach ($setting in $Mod.settings.PSObject.Properties) {
            $value = $setting.Value
            if ($value -is [byte] -or $value -is [int16] -or $value -is [int] -or $value -is [long] -or $value -is [bool]) {
                Set-WindhawkDwordValue -Path $settingsPath -Name $setting.Name -Value $value
            }
            else {
                Set-WindhawkStringValue -Path $settingsPath -Name $setting.Name -Value $value
            }
        }
    }
}

function Remove-WindhawkPresetDrift {
    param([Parameter(Mandatory)][string[]]$PresetModIds)

    $presetIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $PresetModIds) { [void]$presetIds.Add($id) }

    foreach ($root in @('HKLM:\SOFTWARE\Windhawk\Engine\Mods', 'HKLM:\SOFTWARE\Windhawk\Engine\ModsWritable')) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $presetIds.Contains($_.PSChildName)) {
                Write-WindhawkLog "Removing non-preset Windhawk registry entry $($_.PSChildName)." -Level WARN
                Remove-Item -LiteralPath $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $sourceRoot = Join-Path $WindhawkRoot 'ModsSource'
    if (Test-Path -LiteralPath $sourceRoot) {
        Get-ChildItem -LiteralPath $sourceRoot -File -Filter '*.wh.cpp' -ErrorAction SilentlyContinue | ForEach-Object {
            $id = $_.Name.Substring(0, $_.Name.Length - '.wh.cpp'.Length)
            if (-not $presetIds.Contains($id)) {
                Write-WindhawkLog "Removing non-preset Windhawk source $($_.Name)." -Level WARN
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $modsRoot = Join-Path $WindhawkRoot 'Engine\Mods'
    if (Test-Path -LiteralPath $modsRoot) {
        Get-ChildItem -LiteralPath $modsRoot -File -Recurse -Filter '*.dll' -ErrorAction SilentlyContinue | ForEach-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            if ($name -ne 'windhawk-mod-shim' -and $name -match '^(.+)_\d+(?:\.\d+)*_\d+$' -and -not $presetIds.Contains($matches[1])) {
                Write-WindhawkLog "Removing non-preset Windhawk DLL $($_.Name)." -Level WARN
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $writableRoot = Join-Path $WindhawkRoot 'Engine\ModsWritable'
    foreach ($relative in @('mod-storage', 'mod-task', 'mod-status')) {
        $dir = Join-Path $writableRoot $relative
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $keep = $false
            foreach ($id in $PresetModIds) {
                if ($_.Name -like "*_$id" -or $_.Name -eq $id) {
                    $keep = $true
                    break
                }
            }
            if (-not $keep) {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Remove-WindhawkOldModFile {
    param(
        [Parameter(Mandatory)][string]$ModId,
        [Parameter(Mandatory)][string[]]$Subfolders,
        [Parameter(Mandatory)][string]$CurrentLibraryFileName
    )

    foreach ($subfolder in $Subfolders) {
        $dir = Join-Path $WindhawkRoot "Engine\Mods\$subfolder"
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        Get-ChildItem -LiteralPath $dir -File -Filter "$ModId`_*.dll" -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -ne $CurrentLibraryFileName) {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Write-WindhawkUserProfile {
    param(
        [Parameter(Mandatory)][object[]]$AppliedMods,
        [Parameter(Mandatory)][object]$Preset
    )

    $mods = [ordered]@{}
    foreach ($item in $AppliedMods) {
        $entry = [ordered]@{
            version = $item.Version
            latestVersion = $item.Version
        }
        if ($item.Rating) { $entry.rating = [int]$item.Rating }
        $mods[$item.Id] = $entry
    }

    $windhawkVersion = $null
    $exe = Get-WindhawkInstalledExe
    if ($exe) {
        try { $windhawkVersion = [string](Get-Item -LiteralPath $exe).VersionInfo.ProductVersion } catch { }
    }

    $windhawkProfile = [ordered]@{
        app = [ordered]@{
            version = $windhawkVersion
            latestVersion = $windhawkVersion
        }
        id = if ($Preset.PSObject.Properties['profileId'] -and $Preset.profileId) { [string]$Preset.profileId } else { ([guid]::NewGuid()).ToString('B').ToUpperInvariant() }
        mods = $mods
        os = [System.Environment]::OSVersion.Version.ToString()
    }
    $profilePath = Join-Path $WindhawkRoot 'userprofile.json'
    $windhawkProfile | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $profilePath -Encoding UTF8
}

function Restart-ExplorerForWindhawk {
    if ($NoRestartExplorer) { return }
    $explorer = @(Get-Process -Name explorer -ErrorAction SilentlyContinue)
    if ($explorer.Count -eq 0) { return }
    Write-WindhawkLog 'Restarting Explorer so Windhawk can inject the preset.'
    $explorer | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}
