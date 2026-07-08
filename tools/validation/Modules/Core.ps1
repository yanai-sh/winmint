#Requires -Version 7.6

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
        'tools\ui-bridge',
        'src\runtime\image',
        'src\runtime\firstlogon',
        'src\runtime\setup'
    ) | ForEach-Object { Join-Path $root $_ }
    $settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
    $findings = @()
    foreach ($target in $targets) {
        $analyzerArgs = @{ Path = $target; Recurse = $true }
        if (Test-Path -LiteralPath $settings) {
            $analyzerArgs.Settings = $settings
        }
        else {
            $analyzerArgs.Severity = @('Error', 'Warning')
        }
        $findings += @(Invoke-ScriptAnalyzer @analyzerArgs)
    }
    foreach ($f in $findings) { Add-ValidationError "PSScriptAnalyzer $($f.RuleName): $($f.ScriptPath):$($f.Line) $($f.Message)" }
}

function Test-LauncherArchitecture {
    foreach ($required in @('WinMint-GUI.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf)) {
            Add-ValidationError "Required launcher missing: $required"
        }
    }

    $bootstrapPath = Join-Path $root 'winmint.ps1'
    $bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw
    if ($bootstrap -notmatch "\[ValidateSet\('Gui','Headless'\)\]") {
        Add-ValidationError 'winmint.ps1 must expose only Gui and Headless modes.'
    }
    if ($bootstrap -notmatch '\[string\]\$Mode = ''Gui''') {
        Add-ValidationError 'winmint.ps1 default mode must be Gui.'
    }
    $guiFunction = [regex]::Match($bootstrap, 'function Find-WinMintWizardLauncherScript[\s\S]*?function Resolve-WinMintLaunchMode')
    $removedLauncherPattern = 'WinMint-Legacy' + 'UI\.ps1'
    if (-not $guiFunction.Success -or $guiFunction.Value -match $removedLauncherPattern) {
        Add-ValidationError 'Find-WinMintWizardLauncherScript must resolve only the GUI launcher.'
    }
    Write-Host 'OK launcher architecture'
}

function Test-WizardIdentity {
    foreach ($relative in @(
            'assets\runtime\setup\setup-shell\wizard.html',
            'assets\runtime\setup\setup-shell\wizard.js',
            'assets\runtime\setup\setup-shell\wizard.css'
        )) {
        $path = Join-Path $root $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Add-ValidationError "Wizard asset missing: $relative"
        }
    }

    $appOptions = Get-Content -LiteralPath (Join-Path $root 'apps\setup-shell\AppOptions.cs') -Raw
    if ($appOptions -notmatch '--wizard') {
        Add-ValidationError 'Setup shell AppOptions must parse --wizard.'
    }
    if ($appOptions -notmatch '--repo-root') {
        Add-ValidationError 'Setup shell AppOptions must parse --repo-root.'
    }

    $guiLauncher = Get-Content -LiteralPath (Join-Path $root 'WinMint-GUI.ps1') -Raw
    if ($guiLauncher -notmatch '--wizard') {
        Add-ValidationError 'WinMint-GUI.ps1 must launch the setup shell with --wizard.'
    }
    Write-Host 'OK wizard identity'
}

function Test-ReleaseManifestRuntimeSurface {
    $manifestPath = Get-WinMintPath -Name ConfigRoot -ChildPath 'release-manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $include = @($manifest.include)
    $exclude = @($manifest.exclude)
    foreach ($required in @('WinMint-GUI.ps1', 'tools/ui-bridge')) {
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
    $removedLauncher = 'WinMint-Legacy' + 'UI.ps1'
    $removedUiTree = 'apps/legacy' + '-wpf'
    foreach ($removed in @($removedLauncher, $removedUiTree, 'vendor')) {
        if ($include -contains $removed) {
            Add-ValidationError "Release manifest must not include removed compatibility path: $removed"
        }
    }
    foreach ($requiredExclude in @('tools/vm', 'tools/dev', 'tools/release', 'output', 'dist')) {
        if ($exclude -notcontains $requiredExclude) {
            Add-ValidationError "Release manifest must exclude $requiredExclude."
        }
    }
    Write-Host 'OK release manifest runtime surface'
}

function Test-DismArgumentQuoting {
    $targets = @(
        'src\runtime\image\Private\Image\Assets.ps1',
        'src\runtime\image\Private\Image\Packages.ps1',
        'src\runtime\image\Private\Image\Staging.ps1',
        'src\runtime\image\Private\Image\Tweaks.ps1'
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
    $relativePath = 'src\runtime\image\Private\Image\Tweaks.ps1'
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

