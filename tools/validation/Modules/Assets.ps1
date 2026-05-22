#Requires -Version 7.3

function Test-RequiredAssets {
    $required = @(
        'apps\WinMint.LegacyWpf\Views\MainWindow.xaml',
        'WinMint-GUI.ps1',
        'WinMint-LegacyUI.ps1',
        'config\autounattend.xml',
        'LICENSE',
        'winmint.ps1',
        'assets\brand\WinMint.svg',
        'assets\brand\WinMint.vector.svg',
        'assets\brand\winmint-mark-v2.svg',
        'assets\brand\winmint-brand-final.svg',
        'assets\brand\winmint-brand-final.png',
        'assets\Bloom-wallpaper-OLED-muted.png',
        'assets\drivers\README.md',
        'assets\editors\cursor.png',
        'assets\editors\vscodium.png',
        'assets\editors\zed.png',
        'assets\editors\neovim.png',
        'assets\wsl\ubuntu.png',
        'assets\wsl\debian.png',
        'assets\wsl\archlinux.png',
        'assets\wsl\fedora.png',
        'assets\shell\standard.svg',
        'assets\shell\standard.png',
        'assets\shell\windhawk.svg',
        'assets\shell\windhawk.png',
        'assets\shell\windhawk\preview.png',
        'assets\windhawk\preset.json',
        'assets\windhawk\README.md',
        'assets\shell\yasb.svg',
        'assets\shell\yasb.png',
        'assets\yasb\config.yaml',
        'assets\yasb\styles.css',
        'assets\shell\komorebi.svg',
        'assets\shell\komorebi.png',
        'assets\komorebi\komorebi.json',
        'assets\komorebi\applications.json',
        'assets\komorebi\whkdrc',
        'assets\fonts\CascadiaCodeNF-Regular.ttf',
        'assets\cursors\Windows11ModernLight\Alternate.cur',
        'assets\cursors\Windows11ModernLight\Arrow.cur',
        'assets\cursors\Windows11ModernLight\Busy.ani',
        'assets\cursors\Windows11ModernLight\Cross.cur',
        'assets\cursors\Windows11ModernLight\Handwriting.cur',
        'assets\cursors\Windows11ModernLight\Help.cur',
        'assets\cursors\Windows11ModernLight\IBeam.cur',
        'assets\cursors\Windows11ModernLight\Link.cur',
        'assets\cursors\Windows11ModernLight\Move.cur',
        'assets\cursors\Windows11ModernLight\Person.cur',
        'assets\cursors\Windows11ModernLight\Pin.cur',
        'assets\cursors\Windows11ModernLight\Precision.cur',
        'assets\cursors\Windows11ModernLight\SizeNESW.cur',
        'assets\cursors\Windows11ModernLight\SizeNS.cur',
        'assets\cursors\Windows11ModernLight\SizeNWSE.cur',
        'assets\cursors\Windows11ModernLight\SizeWE.cur',
        'assets\cursors\Windows11ModernLight\Unavailable.cur',
        'assets\cursors\Windows11ModernLight\Work.ani',
        'config\packages.json',
        'config\profiles.json',
        'config\release-manifest.json',
        'config\tweaks.json',
        'cloudflare\winmint\README.md',
        'cloudflare\winmint\src\index.js',
        'cloudflare\winmint\wrangler.jsonc',
        'tools\release\New-WinMintReleaseBundle.ps1',
        'tools\release\Build-WinMintGpui.ps1',
        'tools\audit\Audit-LiveInstall.ps1',
        'src\WinMint.Setup\WindhawkBootstrap.ps1',
        'src\WinMint.Setup\WindhawkBootstrap.Helpers.ps1',
        'src\WinMint\Private\Pipeline.Console.ps1',
        'apps\WinMint.LegacyWpf\Foundation\FileSystemLiterals.ps1',
        'apps\WinMint.LegacyWpf\Foundation\UiSession.ps1',
        'apps\WinMint.LegacyWpf\Services\Theme.ps1',
        'apps\WinMint.LegacyWpf\Services\UiFramework.ps1',
        'apps\WinMint.LegacyWpf\Services\UiInteraction.ps1',
        'vendor\wpf-ui\4.3.0\net8.0-windows7.0\Wpf.Ui.dll',
        'vendor\wpf-ui\4.3.0\net8.0-windows7.0\Wpf.Ui.Abstractions.dll',
        'vendor\wpf-ui\4.3.0\net8.0-windows7.0\WPF-UI-LICENSE.md',
        'vendor\wpf-ui\4.3.0\net8.0-windows7.0\WPF-UI.Abstractions-LICENSE.md',
        'src\WinMint.Agent\Agent.Console.ps1',
        'src\WinMint.Agent\Agent.Runtime.ps1',
        'src\WinMint.Agent\Start-WinMintAgent.ps1',
        'src\WinMint.Agent\Start-WinMintFirstLogonUI.ps1',
        'src\WinMint.Agent\Start-WinMintFirstLogonUI.xaml',
        'src\WinMint.Agent\BuildProfile.json',
        'src\WinMint.Agent\Modules\PackageManagers.ps1',
        'src\WinMint.Agent\Modules\Editors.ps1',
        'src\WinMint.Agent\Modules\Git.ps1',
        'src\WinMint.Agent\Modules\Dotfiles.ps1',
        'src\WinMint.Agent\Modules\Wsl.ps1',
        'src\WinMint.Agent\Modules\FlowEverything.ps1',
        'src\WinMint.Agent\Modules\Raycast.ps1',
        'src\WinMint.Agent\Modules\LiveInstallAudit.ps1',
        'src\WinMint.Agent\Modules\TilingDesktop.ps1',
        'src\WinMint.Agent\Modules\Windhawk.ps1',
        'src\WinMint.Agent\Modules\Profiles.ps1',
        'apps\WinMint.LegacyWpf\Views\MainWindow.xaml'
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
            $_.FullName.Substring($root.Length).TrimStart('\', '/') -notlike 'assets\cursors\_extract\Assets\*' -and
            $_.FullName.Substring($root.Length).TrimStart('\', '/') -notlike 'assets\cursors\Windows11ModernLight\*'
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

    $legacyPayload = Join-Path $root 'assets\windhawk\current.zip'
    if (Test-Path -LiteralPath $legacyPayload) {
        Add-ValidationError 'Windhawk preset must not include compiled ProgramData zip payloads. Remove assets\windhawk\current.zip.'
    }

    $presetPath = Join-Path $root 'assets\windhawk\preset.json'
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
        Write-Host 'OK Windhawk preset assets\windhawk\preset.json'
    }
    catch {
        Add-ValidationError "Windhawk preset validation failed: $($_.Exception.Message)"
    }
}

function Test-YasbPresetPayload {
    $configPath = Join-Path $root 'assets\yasb\config.yaml'
    $stylesPath = Join-Path $root 'assets\yasb\styles.css'
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
    Write-Host 'OK YASB preset assets\yasb'
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
            if (-not $tool.PSObject.Properties['architectures']) {
                Add-ValidationError "Tool '$id' must declare architectures."
                continue
            }
            $architectures = @($tool.architectures | ForEach-Object { ([string]$_).ToLowerInvariant() })
            foreach ($requiredArch in @('amd64', 'arm64')) {
                if ($architectures -notcontains $requiredArch) {
                    Add-ValidationError "Tool '$id' must declare $requiredArch support or an explicit unsupported policy."
                }
            }
            foreach ($arch in $architectures) {
                if (@('amd64', 'arm64', 'x86') -notcontains $arch) {
                    Add-ValidationError "Tool '$id' declares unsupported architecture token: $arch"
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
    $configPath = Join-Path $root 'assets\komorebi\komorebi.json'
    $appsPath = Join-Path $root 'assets\komorebi\applications.json'
    $whkdPath = Join-Path $root 'assets\komorebi\whkdrc'
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
        Write-Host 'OK Komorebi preset assets\komorebi'
    }
    catch {
        Add-ValidationError "Komorebi preset validation failed: $($_.Exception.Message)"
    }
}
