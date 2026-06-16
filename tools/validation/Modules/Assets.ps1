#Requires -Version 7.3

function Test-RequiredAssets {
    $required = @(
        'WinMint-GUI.ps1',
        'config\autounattend.xml',
        'LICENSE',
        'winmint.ps1',
        'assets\brand\window_logo.svg',
        'assets\brand\winmint_full.png',
        'assets\brand\winmint_hero.png',
        'assets\brand\icons\winmint_simple_squircle_256.ico',
        'assets\runtime\wallpaper\winmint-bloom.png',
        'assets\runtime\accountpicture\user.png',
        'assets\runtime\accountpicture\user-192.png',
        'assets\runtime\accountpicture\user-48.png',
        'assets\runtime\accountpicture\user-40.png',
        'assets\runtime\accountpicture\user-32.png',
        'assets\runtime\defaultapps\WinMint-DefaultAppAssociations.xml',
        'assets\ui\editors\cursor.png',
        'assets\ui\editors\zed.png',
        'assets\ui\editors\neovim.png',
        'assets\ui\wsl\ubuntu.png',
        'assets\ui\wsl\archlinux.png',
        'assets\ui\wsl\fedora.png',
        'assets\ui\wsl\pengwin.png',
        'assets\ui\wsl\nixos.png',
        'assets\ui\desktop\windhawk\windhawk.svg',
        'assets\ui\desktop\windhawk\windhawk.png',
        'assets\runtime\desktop\windhawk\preset.json',
        'assets\runtime\desktop\windhawk\README.md',
        'assets\ui\desktop\yasb.svg',
        'assets\ui\desktop\yasb.png',
        'assets\runtime\desktop\yasb\config.yaml',
        'assets\runtime\desktop\yasb\styles.css',
        'assets\ui\desktop\komorebi.svg',
        'assets\ui\desktop\komorebi.png',
        'assets\runtime\desktop\komorebi\komorebi.json',
        'assets\runtime\desktop\komorebi\applications.json',
        'assets\runtime\desktop\komorebi\whkdrc',
        'assets\runtime\fonts\CascadiaCodeNF-Regular.ttf',
        'assets\runtime\cursors\Windows11ModernLight\Alternate.cur',
        'assets\runtime\cursors\Windows11ModernLight\Arrow.cur',
        'assets\runtime\cursors\Windows11ModernLight\Busy.ani',
        'assets\runtime\cursors\Windows11ModernLight\Cross.cur',
        'assets\runtime\cursors\Windows11ModernLight\Handwriting.cur',
        'assets\runtime\cursors\Windows11ModernLight\Help.cur',
        'assets\runtime\cursors\Windows11ModernLight\IBeam.cur',
        'assets\runtime\cursors\Windows11ModernLight\Link.cur',
        'assets\runtime\cursors\Windows11ModernLight\Move.cur',
        'assets\runtime\cursors\Windows11ModernLight\Person.cur',
        'assets\runtime\cursors\Windows11ModernLight\Pin.cur',
        'assets\runtime\cursors\Windows11ModernLight\Precision.cur',
        'assets\runtime\cursors\Windows11ModernLight\SizeNESW.cur',
        'assets\runtime\cursors\Windows11ModernLight\SizeNS.cur',
        'assets\runtime\cursors\Windows11ModernLight\SizeNWSE.cur',
        'assets\runtime\cursors\Windows11ModernLight\SizeWE.cur',
        'assets\runtime\cursors\Windows11ModernLight\Unavailable.cur',
        'assets\runtime\cursors\Windows11ModernLight\Work.ani',
        'assets\runtime\cursors\BreezeXLight\Alternate.cur',
        'assets\runtime\cursors\BreezeXLight\Arrow.cur',
        'assets\runtime\cursors\BreezeXLight\Busy.ani',
        'assets\runtime\cursors\BreezeXLight\Cross.cur',
        'assets\runtime\cursors\BreezeXLight\Grabbing.cur',
        'assets\runtime\cursors\BreezeXLight\Handwriting.cur',
        'assets\runtime\cursors\BreezeXLight\Help.cur',
        'assets\runtime\cursors\BreezeXLight\IBeam.cur',
        'assets\runtime\cursors\BreezeXLight\Link.cur',
        'assets\runtime\cursors\BreezeXLight\Move.cur',
        'assets\runtime\cursors\BreezeXLight\Pan.cur',
        'assets\runtime\cursors\BreezeXLight\Person.cur',
        'assets\runtime\cursors\BreezeXLight\Pin.cur',
        'assets\runtime\cursors\BreezeXLight\SizeNESW.cur',
        'assets\runtime\cursors\BreezeXLight\SizeNS.cur',
        'assets\runtime\cursors\BreezeXLight\SizeNWSE.cur',
        'assets\runtime\cursors\BreezeXLight\SizeWE.cur',
        'assets\runtime\cursors\BreezeXLight\Unavailable.cur',
        'assets\runtime\cursors\BreezeXLight\Work.ani',
        'assets\runtime\cursors\BreezeXLight\ZoomIn.cur',
        'assets\runtime\cursors\BreezeXLight\ZoomOut.cur',
        'assets\runtime\cursors\BreezeXLight\install.inf',
        'config\packages.json',
        'config\release-manifest.json',
        'config\tweaks.json',
        'cloudflare\winmint\README.md',
        'cloudflare\winmint\src\index.js',
        'cloudflare\winmint\wrangler.jsonc',
        'tools\release\New-WinMintReleaseBundle.ps1',
        'tools\release\Build-WinMintGui.ps1',
        'tools\audit\Audit-LiveInstall.ps1',
        'src\runtime\setup\WindhawkBootstrap.ps1',
        'src\runtime\setup\WindhawkBootstrap.Helpers.ps1',
        'src\runtime\image\Private\Pipeline.Console.ps1',
        'src\runtime\firstlogon\Agent.Console.ps1',
        'src\runtime\firstlogon\Agent.Runtime.ps1',
        'src\runtime\firstlogon\Start-WinMintAgent.ps1',
        'src\runtime\firstlogon\BuildProfile.json',
        'src\runtime\firstlogon\Modules\PackageManagers.ps1',
        'src\runtime\firstlogon\Modules\Editors.ps1',
        'src\runtime\firstlogon\Modules\Git.ps1',
        'src\runtime\firstlogon\Modules\Dotfiles.ps1',
        'src\runtime\firstlogon\Modules\Wsl.ps1',
        'src\runtime\firstlogon\Modules\Raycast.ps1',
        'src\runtime\firstlogon\Modules\LauncherKey.ps1',
        'src\runtime\firstlogon\Modules\LiveInstallAudit.ps1',
        'src\runtime\firstlogon\Modules\TilingDesktop.ps1',
        'src\runtime\firstlogon\Modules\Windhawk.ps1',
        'src\runtime\firstlogon\Modules\Profiles.ps1'
    )
    foreach ($rel in $required) {
        $path = Join-Path $root $rel
        if (-not (Test-Path -LiteralPath $path)) {
            Add-ValidationError "Required asset missing: $rel"
        }
    }
}

function Test-DuplicateLargeAssets {
    $assetRoot = Join-Path $root 'assets'
    if (-not (Test-Path -LiteralPath $assetRoot)) { return }

    $files = @(Get-ChildItem -LiteralPath $assetRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Length -ge 1MB -and
            $_.FullName.Substring($root.Length).TrimStart('\', '/') -notlike 'assets\runtime\cursors\_extract\Assets\*' -and
            $_.FullName.Substring($root.Length).TrimStart('\', '/') -notlike 'assets\runtime\cursors\Windows11ModernLight\*'
        })
    $candidates = @($files | Group-Object Length | Where-Object { $_.Count -gt 1 })
    foreach ($sizeGroup in $candidates) {
        $hashed = @($sizeGroup.Group | ForEach-Object {
            [pscustomobject]@{
                Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                RelativePath = $_.FullName.Substring($root.Length).TrimStart('\', '/')
            }
        })
        foreach ($hashGroup in @($hashed | Group-Object Hash | Where-Object { $_.Count -gt 1 })) {
            $paths = @($hashGroup.Group | Select-Object -ExpandProperty RelativePath | Sort-Object)
            Add-ValidationError "Duplicate large asset content: $($paths -join ', ')"
        }
    }
    Write-Host 'OK no duplicate large assets'
}

function Test-WslTerminalIconQuality {
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    }
    catch {
        Add-ValidationError "Unable to load System.Drawing for WSL icon validation: $($_.Exception.Message)"
        return
    }

    foreach ($iconName in @('ubuntu.png', 'archlinux.png', 'fedora.png', 'nixos.png')) {
        $iconPath = Join-Path $root "assets\ui\wsl\$iconName"
        if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) { continue }

        $image = $null
        try {
            $image = [System.Drawing.Image]::FromFile($iconPath)
            if ($image.Width -lt 512 -or $image.Height -lt 512) {
                Add-ValidationError "WSL Terminal icon must be at least 512x512: assets\ui\wsl\$iconName is $($image.Width)x$($image.Height)."
            }
        }
        catch {
            Add-ValidationError "WSL Terminal icon is not a readable PNG: assets\ui\wsl\$iconName. $($_.Exception.Message)"
        }
        finally {
            if ($image) { $image.Dispose() }
        }
    }
    Write-Host 'OK WSL Terminal PNG icon quality'
}

function Test-WindhawkPresetPayload {
    function Test-WindhawkPresetUrl {
        param([Parameter(Mandatory)][string]$Uri)

        try {
            $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -Method Head -TimeoutSec 20
            return [int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 400
        }
        catch {
            try {
                $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -Method Get -Headers @{ Range = 'bytes=0-0' } -TimeoutSec 20
                return [int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 400
            }
            catch {
                return $false
            }
        }
    }

    function Get-WindhawkPresetDllSubfolder {
        param([string[]]$Architecture)

        $subfolders = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $archs = @($Architecture | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($archs.Count -eq 0) { $archs = @('x86', 'x86-64') }
        foreach ($arch in $archs) {
            switch ($arch) {
                'x86' { [void]$subfolders.Add('32') }
                'x86-64' {
                    [void]$subfolders.Add('64')
                    [void]$subfolders.Add('arm64')
                }
                'amd64' { [void]$subfolders.Add('64') }
                'arm64' { [void]$subfolders.Add('arm64') }
            }
        }
        return @($subfolders.GetEnumerator())
    }

    $legacyPayload = Join-Path $root 'assets\runtime\desktop\windhawk\current.zip'
    if (Test-Path -LiteralPath $legacyPayload) {
        Add-ValidationError 'Windhawk preset must not include compiled ProgramData zip payloads. Remove assets\runtime\desktop\windhawk\current.zip.'
    }

    $presetPath = Join-Path $root 'assets\runtime\desktop\windhawk\preset.json'
    if (-not (Test-Path -LiteralPath $presetPath)) { return }

    try {
        $preset = Get-Content -LiteralPath $presetPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($preset.schema -ne 'winmint.windhawkPreset.v1') {
            Add-ValidationError "Windhawk preset schema is unexpected: $($preset.schema)"
        }
        $mods = @($preset.mods)
        if ($mods.Count -eq 0) {
            Add-ValidationError 'Windhawk preset contains no mods.'
        }
        $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($mod in $mods) {
            if ([string]::IsNullOrWhiteSpace([string]$mod.id)) {
                Add-ValidationError 'Windhawk preset contains a mod without id.'
                continue
            }
            if (-not $seen.Add([string]$mod.id)) {
                Add-ValidationError "Windhawk preset contains duplicate mod id: $($mod.id)"
            }
            if ([string]::IsNullOrWhiteSpace([string]$mod.version)) {
                Add-ValidationError "Windhawk preset mod missing version: $($mod.id)"
            }
            foreach ($arch in @($mod.architecture)) {
                if (@('x86', 'x86-64', 'amd64', 'arm64') -notcontains [string]$arch) {
                    Add-ValidationError "Windhawk preset mod $($mod.id) has unsupported architecture metadata: $arch"
                }
            }
            foreach ($include in @($mod.include)) {
                if ([string]::IsNullOrWhiteSpace([string]$include)) {
                    Add-ValidationError "Windhawk preset mod $($mod.id) contains an empty include target."
                }
            }
            $sourceUrl = if ($mod.PSObject.Properties['sourceUrl'] -and $mod.sourceUrl) {
                [string]$mod.sourceUrl
            } else {
                "https://mods.windhawk.net/mods/$($mod.id).wh.cpp"
            }
            if (-not (Test-WindhawkPresetUrl -Uri $sourceUrl)) {
                Add-ValidationError "Windhawk preset source URL is unavailable for $($mod.id): $sourceUrl"
            }
            $versionsUrl = "https://mods.windhawk.net/mods/$($mod.id)/versions.json"
            try {
                $versionResponse = Invoke-WebRequest -Uri $versionsUrl -UseBasicParsing -TimeoutSec 20
                $versions = @($versionResponse.Content | ConvertFrom-Json)
                if (@($versions | Where-Object { [string]$_.version -eq [string]$mod.version }).Count -eq 0) {
                    Add-ValidationError "Windhawk preset pinned version $($mod.version) was not found for $($mod.id)."
                }
            }
            catch {
                Add-ValidationError "Windhawk preset versions URL is unavailable for $($mod.id): $versionsUrl"
            }
            foreach ($subfolder in @(Get-WindhawkPresetDllSubfolder -Architecture @($mod.architecture))) {
                $dllUrl = "https://mods.windhawk.net/mods/$($mod.id)/$($mod.version)_$subfolder.dll"
                if (-not (Test-WindhawkPresetUrl -Uri $dllUrl)) {
                    Add-ValidationError "Windhawk preset DLL URL is unavailable for $($mod.id) ${subfolder}: $dllUrl"
                }
            }
        }
        Write-Host 'OK Windhawk preset assets\runtime\desktop\windhawk\preset.json'
    }
    catch {
        Add-ValidationError "Windhawk preset validation failed: $($_.Exception.Message)"
    }
}

function Test-YasbPresetPayload {
    $configPath = Join-Path $root 'assets\runtime\desktop\yasb\config.yaml'
    $stylesPath = Join-Path $root 'assets\runtime\desktop\yasb\styles.css'
    if (-not (Test-Path -LiteralPath $configPath) -or -not (Test-Path -LiteralPath $stylesPath)) { return }

    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    $styles = Get-Content -LiteralPath $stylesPath -Raw -Encoding UTF8
    if ($config -match '(?im)^\s*api_key\s*:') {
        Add-ValidationError 'YASB preset must not include API keys. Use a post-install private config path instead.'
    }
    if ($config -match '(?i)weatherapi|\.env|token|secret') {
        Add-ValidationError 'YASB preset contains secret-oriented weather/env/token references.'
    }
    if ($config -match [regex]::Escape([string]$env:USERPROFILE) -or $styles -match [regex]::Escape([string]$env:USERPROFILE)) {
        Add-ValidationError 'YASB preset must not include development-machine user profile paths.'
    }
    if ($config -notmatch 'yasb\.clock\.ClockWidget' -or $config -notmatch 'yasb\.taskbar\.TaskbarWidget') {
        Add-ValidationError 'YASB preset should include the expected clock and taskbar widgets.'
    }
    Write-Host 'OK YASB preset assets\runtime\desktop\yasb'
}

function Test-PackageManifestArchitecture {
    $manifestPath = Join-Path $root 'config\packages.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { return }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $manifest.tools) {
            Add-ValidationError 'config\packages.json must contain a tools object.'
            return
        }
        foreach ($toolProperty in $manifest.tools.PSObject.Properties) {
            $tool = $toolProperty.Value
            $id = [string]$toolProperty.Name
            if (-not $tool.PSObject.Properties['source']) {
                Add-ValidationError "Tool '$id' must declare a source."
                continue
            }
            if ([string]$tool.source -notin @('winget', 'store', 'scoop', 'direct')) {
                Add-ValidationError "Tool '$id' must use winget, store, scoop, or approved direct as its source; got '$($tool.source)'."
            }
            if (-not $tool.PSObject.Properties['architectures']) {
                Add-ValidationError "Tool '$id' must declare architectures."
                continue
            }
            $architectures = @($tool.architectures | ForEach-Object { ([string]$_).ToLowerInvariant() })
            $unsupportedArchitectures = @()
            if ($tool.PSObject.Properties['unsupportedArchitectures']) {
                if ($tool.unsupportedArchitectures -is [array]) {
                    $unsupportedArchitectures = @($tool.unsupportedArchitectures | ForEach-Object { ([string]$_).ToLowerInvariant() })
                }
                else {
                    $unsupportedArchitectures = @($tool.unsupportedArchitectures.PSObject.Properties.Name | ForEach-Object { ([string]$_).ToLowerInvariant() })
                }
            }
            foreach ($requiredArch in @('amd64', 'arm64')) {
                if ($architectures -notcontains $requiredArch -and $unsupportedArchitectures -notcontains $requiredArch) {
                    Add-ValidationError "Tool '$id' must declare $requiredArch support or an explicit unsupported policy."
                }
            }
            foreach ($arch in $architectures) {
                if (@('amd64', 'arm64', 'x86') -notcontains $arch) {
                    Add-ValidationError "Tool '$id' declares unsupported architecture token: $arch"
                }
            }
            foreach ($arch in $unsupportedArchitectures) {
                if (@('amd64', 'arm64', 'x86') -notcontains $arch) {
                    Add-ValidationError "Tool '$id' declares unsupported architecture token in unsupportedArchitectures: $arch"
                }
                if ($architectures -contains $arch) {
                    Add-ValidationError "Tool '$id' declares $arch as both supported and unsupported."
                }
            }
            if ($tool.PSObject.Properties['wingetArchitectureByHost']) {
                foreach ($override in $tool.wingetArchitectureByHost.PSObject.Properties) {
                    if ($architectures -notcontains ([string]$override.Name).ToLowerInvariant()) {
                        Add-ValidationError "Tool '$id' has a Winget architecture override for undeclared host architecture: $($override.Name)"
                    }
                    if (@('x86', 'x64', 'arm64') -notcontains ([string]$override.Value).ToLowerInvariant()) {
                        Add-ValidationError "Tool '$id' has unsupported Winget architecture override: $($override.Value)"
                    }
                    if (([string]$override.Name).ToLowerInvariant() -eq 'arm64' -and ([string]$override.Value).ToLowerInvariant() -eq 'x86') {
                        Add-ValidationError "Tool '$id' must not downgrade native ARM64 support to x86 in wingetArchitectureByHost."
                    }
                }
            }
            if ([string]$tool.source -eq 'direct') {
                foreach ($requiredField in @('url', 'sha256', 'version')) {
                    $fieldProperty = $tool.PSObject.Properties[$requiredField]
                    if (-not $fieldProperty -or [string]::IsNullOrWhiteSpace([string]$fieldProperty.Value)) {
                        Add-ValidationError "Direct tool '$id' must declare $requiredField."
                    }
                }
                if ([string]$id -ne 'everything-arm64-beta' -or
                    [string]$tool.id -ne 'Everything-1.5.0.1415b.ARM64' -or
                    [string]$tool.version -ne '1.5.0.1415b' -or
                    [string]$tool.url -ne 'https://www.voidtools.com/Everything-1.5.0.1415b.ARM64.en-US-Setup.exe' -or
                    [string]$tool.sha256 -ne '2D511A33A3494147F921DCB488772125E6CC654E677196AACB0235967A27D2DA' -or
                    $architectures.Count -ne 1 -or
                    $architectures[0] -ne 'arm64') {
                    Add-ValidationError "Direct tool '$id' must be the approved pinned Everything 1.5.0.1415b ARM64 payload."
                }
                if (-not $tool.PSObject.Properties['silentArgs'] -or @($tool.silentArgs).Count -eq 0) {
                    Add-ValidationError "Direct tool '$id' must declare silentArgs."
                }
            }
        }
        Write-Host 'OK package manifest architecture declarations'
    }
    catch {
        Add-ValidationError "Package manifest architecture validation failed: $($_.Exception.Message)"
    }
}

function Test-KomorebiPresetPayload {
    $configPath = Join-Path $root 'assets\runtime\desktop\komorebi\komorebi.json'
    $appsPath = Join-Path $root 'assets\runtime\desktop\komorebi\applications.json'
    $whkdPath = Join-Path $root 'assets\runtime\desktop\komorebi\whkdrc'
    if (-not (Test-Path -LiteralPath $configPath) -or -not (Test-Path -LiteralPath $appsPath)) { return }

    try {
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $apps = Get-Content -LiteralPath $appsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        [void]$apps
        if ([string]$config.app_specific_configuration_path -notmatch 'KOMOREBI_CONFIG_HOME') {
            Add-ValidationError 'Komorebi preset should use KOMOREBI_CONFIG_HOME for applications.json.'
        }
        if (-not $config.monitors -or @($config.monitors[0].workspaces).Count -lt 3) {
            Add-ValidationError 'Komorebi preset must define at least three workspaces.'
        }
        $whkd = if (Test-Path -LiteralPath $whkdPath) {
            Get-Content -LiteralPath $whkdPath -Raw -Encoding UTF8
        } else {
            ''
        }
        foreach ($binding in @('alt + h', 'alt + j', 'alt + k', 'alt + l', 'alt + return')) {
            if ($whkd -notmatch [regex]::Escape($binding)) {
                Add-ValidationError "Komorebi whkdrc missing expected binding: $binding"
            }
        }
        Write-Host 'OK Komorebi preset assets\runtime\desktop\komorebi'
    }
    catch {
        Add-ValidationError "Komorebi preset validation failed: $($_.Exception.Message)"
    }
}
