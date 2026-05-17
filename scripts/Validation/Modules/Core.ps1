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
    Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1' |
        Where-Object {
            $_.FullName -notmatch '\\.git\\' -and
            $_.FullName -notmatch '\\dist\\' -and
            $_.FullName -notmatch '\\output\\'
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
    $targets = @('WinMint-CLI.ps1', 'WinMint-UI.ps1', 'src\WinWS', 'src\WinWS.UI', 'src\WinWS.Agent') |
        ForEach-Object { Join-Path $root $_ }
    $settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
    $findings = @()
    foreach ($target in $targets) {
        $analyzerArgs = @{ Path = $target; Recurse = $true; Severity = @('Error') }
        if (Test-Path -LiteralPath $settings) { $analyzerArgs.Settings = $settings }
        $findings += @(Invoke-ScriptAnalyzer @analyzerArgs)
    }
    foreach ($f in $findings) { Add-ValidationError "PSScriptAnalyzer $($f.RuleName): $($f.ScriptPath):$($f.Line) $($f.Message)" }
}

function Test-DismArgumentQuoting {
    $targets = @(
        'src\WinWS\Private\Image\Assets.ps1',
        'src\WinWS\Private\Image\Packages.ps1',
        'src\WinWS\Private\Image\Staging.ps1',
        'src\WinWS\Private\Image\Tweaks.ps1'
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
    $relativePath = 'src\WinWS\Private\Image\Tweaks.ps1'
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
