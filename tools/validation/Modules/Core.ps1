#Requires -Version 7.3

function Add-ValidationError {
    param([string]$Message)
    $errors.Add($Message) | Out-Null
    Write-Error $Message -ErrorAction Continue
}

function Invoke-ValidationStep {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )

    Write-Host "== $Name =="
    try {
        & $ScriptBlock
    }
    catch {
        Add-ValidationError "$Name failed: $($_.Exception.Message)"
    }
}

function Get-ValidationPowerShellFile {
    $roots = @(
        'WinMint-CLI.ps1',
        'WinMint-GUI.ps1',
        'WinMint-LegacyUI.ps1',
        'winmint.ps1',
        'src',
        'apps',
        'tools',
        'tests\contract'
    ) | ForEach-Object { Join-Path $root $_ }

    $files = foreach ($target in $roots) {
        if (-not (Test-Path -LiteralPath $target)) { continue }
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            Get-Item -LiteralPath $target
            continue
        }
        Get-ChildItem -LiteralPath $target -Recurse -File -Filter '*.ps1'
    }

    $files |
        Where-Object {
            $_.FullName -notmatch '\\.git\\' -and
            $_.FullName -notmatch '\\node_modules\\' -and
            $_.FullName -notmatch '\\dist\\' -and
            $_.FullName -notmatch '\\output\\' -and
            $_.FullName -notmatch '\\temp\\' -and
            $_.FullName -notmatch '\\target\\' -and
            $_.FullName -notmatch '\\\.venv\\'
        } |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($root.Length).TrimStart('\', '/')
            [pscustomobject]@{ FullName = $_.FullName; RelativePath = $relative }
        }
}

function Test-XmlFile {
    param([string]$Path, [string]$Kind)
    try {
        [xml]$doc = Get-Content -LiteralPath $Path -Raw
        if (-not $doc.DocumentElement) { throw 'No document element.' }
        Write-Host "OK $Kind $Path"
    } catch {
        Add-ValidationError "$Kind parse failed: $Path :: $($_.Exception.Message)"
    }
}

function Test-JsonFile {
    param([string]$Path)
    try {
        $null = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        Write-Host "OK JSON $Path"
    } catch {
        Add-ValidationError "JSON parse failed: $Path :: $($_.Exception.Message)"
    }
}

function Test-PowerShellParser {
    param([string[]]$RelativePaths)

    $files = if ($RelativePaths -and $RelativePaths.Count -gt 0) {
        @($RelativePaths | ForEach-Object {
            [pscustomobject]@{ FullName = (Join-Path $root $_); RelativePath = $_ }
        })
    } else {
        @(Get-ValidationPowerShellFile)
    }

    foreach ($file in $files) {
        $tokens = $null
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName,
            [ref]$tokens,
            [ref]$parseErrors
        )
        foreach ($err in $parseErrors) {
            Add-ValidationError "PowerShell parse failed: $($file.RelativePath) line $($err.Extent.StartLineNumber): $($err.Message)"
        }
        if (-not $parseErrors -or $parseErrors.Count -eq 0) {
            Write-Host "OK PowerShell parser $($file.RelativePath)"
        }
    }
}

function Invoke-AnalyzerIfAvailable {
    if ($SkipAnalyzer -or -not $RunAnalyzer) {
        Write-Host 'Skipping PSScriptAnalyzer pass. Use -RunAnalyzer to opt in.'
        return
    }
    $cmd = Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Warning 'PSScriptAnalyzer not installed; skipping analyzer pass.'
        return
    }
    $targets = @(
        'WinMint-CLI.ps1',
        'WinMint-GUI.ps1',
        'WinMint-LegacyUI.ps1',
        'tools\gui',
        'src\engine',
        'apps\legacy-wpf',
        'src\agent',
        'src\setup'
    ) | ForEach-Object { Join-Path $root $_ }
    $settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
    $findings = @()
    foreach ($target in $targets) {
        $analyzerArgs = @{ Path = $target; Recurse = $true; Severity = @('Error') }
        if (Test-Path -LiteralPath $settings) { $analyzerArgs.Settings = $settings }
        $findings += @(Invoke-ScriptAnalyzer @analyzerArgs)
    }
    foreach ($f in $findings) { Add-ValidationError "PSScriptAnalyzer $($f.RuleName): $($f.ScriptPath):$($f.Line) $($f.Message)" }
}

function Test-LauncherArchitecture {
    foreach ($required in @('WinMint-GUI.ps1', 'WinMint-LegacyUI.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf)) {
            Add-ValidationError "Required launcher missing: $required"
        }
    }

    $bootstrapPath = Join-Path $root 'winmint.ps1'
    $bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw
    if ($bootstrap -notmatch "\[ValidateSet\('Gui','Headless','LegacyUi'\)\]") {
        Add-ValidationError 'winmint.ps1 must expose Gui, Headless, and LegacyUi modes.'
    }
    if ($bootstrap -notmatch '\[string\]\$Mode = ''Gui''') {
        Add-ValidationError 'winmint.ps1 default mode must be Gui.'
    }
    $guiFunction = [regex]::Match($bootstrap, 'function Find-WinMintGuiScript[\s\S]*?function Resolve-WinMintLaunchMode')
    if (-not $guiFunction.Success -or $guiFunction.Value -match 'WinMint-LegacyUI\.ps1') {
        Add-ValidationError 'Find-WinMintGuiScript must resolve only the GUI launcher.'
    }
    Write-Host 'OK launcher architecture'
}

function Test-GuiIdentity {
    $cargoPath = Get-WinMintPath -Name GuiCargoToml
    $cargoText = Get-Content -LiteralPath $cargoPath -Raw
    if ($cargoText -notmatch '(?m)^name\s*=\s*"winmint-gui"\s*$') {
        Add-ValidationError 'GUI Cargo package name must be winmint-gui.'
    }

    $mainText = Get-Content -LiteralPath (Get-WinMintPath -Name GuiApp -ChildPath 'src\main.rs') -Raw
    if ($mainText -match 'GPUI Lab|WinWsGuiDev|build_gui_dev') {
        Add-ValidationError 'GUI source still contains lab identity.'
    }
    Write-Host 'OK GUI identity'
}

function Test-ReleaseManifestRuntimeSurface {
    $manifestPath = Get-WinMintPath -Name Config -ChildPath 'release-manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $include = @($manifest.include)
    $exclude = @($manifest.exclude)
    foreach ($required in @('WinMint-GUI.ps1', 'WinMint-LegacyUI.ps1', 'apps/gui/bin/WinMint-GUI.exe')) {
        if ($include -notcontains $required) {
            Add-ValidationError "Release manifest must include $required."
        }
    }
    if ($include -contains 'apps') {
        Add-ValidationError 'Release manifest must not include the entire apps tree.'
    }
    if ($include -contains 'tools') {
        Add-ValidationError 'Release manifest must not include tools as runtime surface.'
    }
    if ($exclude -notcontains 'tools') {
        Add-ValidationError 'Release manifest must continue excluding tools.'
    }
    Write-Host 'OK release manifest runtime surface'
}

function Test-NoWinWsCompatibilitySurface {
    $patterns = @(
        'src\\WinWS',
        'WinWS\.ps1',
        'winws\..*schema\.json',
        'Initialize-WinWSEngine'
    )
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch '\\.git\\|\\dist\\|\\output\\|\\temp\\|\\target\\|\\node_modules\\' -and
            $_.Extension -in @('.ps1', '.psm1', '.psd1', '.md', '.json', '.rs', '.toml')
        })
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($root.Length).TrimStart('\', '/')
        if ($relative -in @('AGENTS.md', 'tools\validation\Modules\Core.ps1')) { continue }
        $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        foreach ($pattern in $patterns) {
            if ($text -match $pattern) {
                Add-ValidationError "Legacy WinWS compatibility reference remains in ${relative}: $pattern"
                break
            }
        }
    }
    Write-Host 'OK no WinWS compatibility surface'
}

function Test-GuiBuild {
    param([switch]$IncludeBuild)

    $cargo = Get-Command cargo -ErrorAction SilentlyContinue
    if (-not $cargo) {
        Write-Warning 'Rust cargo not installed; skipping optional GUI cargo check.'
        return
    }

    $manifest = Get-WinMintPath -Name GuiCargoToml
    $arguments = if ($IncludeBuild) {
        @('build', '--release', '--manifest-path', $manifest)
    } else {
        @('check', '--manifest-path', $manifest)
    }
    & $cargo.Source @arguments
    if ($LASTEXITCODE -ne 0) {
        Add-ValidationError "cargo $($arguments[0]) failed for GUI with exit code $LASTEXITCODE."
    }
}

function Test-DismArgumentQuoting {
    $targets = @(
        'src\engine\Private\Image\Assets.ps1',
        'src\engine\Private\Image\Packages.ps1',
        'src\engine\Private\Image\Staging.ps1',
        'src\engine\Private\Image\Tweaks.ps1'
    )
    $patterns = @('/Image:`"', '/Driver:`"', '/PackagePath:`"')
    foreach ($relativePath in $targets) {
        $path = Join-Path $root $relativePath
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $lineNumber = 0
        foreach ($line in Get-Content -LiteralPath $path) {
            $lineNumber++
            foreach ($pattern in $patterns) {
                if ($line.Contains($pattern)) {
                    Add-ValidationError "Embedded quote in dism.exe argument at ${relativePath}:$lineNumber. Pass native arguments as /Image:`$MountDir, not /Image:`"`$MountDir`"."
                }
            }
        }
    }
    Write-Host 'OK DISM native argument quoting'
}

function Test-RegistryTweakStrictModeAccess {
    $relativePath = 'src\engine\Private\Image\Tweaks.ps1'
    $path = Join-Path $root $relativePath
    if (-not (Test-Path -LiteralPath $path)) { return }

    $patterns = @(
        '\$group\.conditional',
        '\$group\.remove'
    )
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $path) {
        $lineNumber++
        foreach ($pattern in $patterns) {
            if ($line -match $pattern) {
                Add-ValidationError "StrictMode-unsafe optional registry tweak access at ${relativePath}:$lineNumber. Use Get-RegistryTweakGroupValue for optional hashtable keys."
            }
        }
    }
    Write-Host 'OK registry tweak optional key access'
}
