#Requires -Version 7.6
# Test helpers for WinMintSetupShell.exe integration tests (not shipped runtime).

function Get-WinMintTestRepoRoot {
    param([Parameter(Mandatory)][string]$ScriptRoot)
    Split-Path -Parent (Split-Path -Parent $ScriptRoot)
}

function Get-WinMintHostSetupShellBinArch {
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch -Regex ([string]$arch) {
        '^ARM64$' { return 'arm64' }
        default { return 'x64' }
    }
}

function Get-WinMintSetupShellNativeExePath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [ValidateSet('x64', 'arm64')]
        [string]$Arch = (Get-WinMintHostSetupShellBinArch)
    )

    $exePath = Join-Path $Root "assets\runtime\setup\setup-shell\bin\$Arch\WinMintSetupShell.Native.exe"
    if (-not (Test-Path -LiteralPath $exePath)) {
        throw @"
WinMintSetupShell.Native.exe not found.
Build once: pwsh -NoProfile -File tools\release\Build-WinMintSetupShell.ps1
"@
    }
    return $exePath
}

function Get-WinMintSetupShellExePath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [ValidateSet('x64', 'arm64')]
        [string]$Arch = (Get-WinMintHostSetupShellBinArch)
    )

    return Get-WinMintSetupShellNativeExePath -Root $Root -Arch $Arch
}

function New-WinMintSetupShellTestWorkspace {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$ParentDir = $env:TEMP,
        [string]$NamePrefix = 'winmint-setup-shell-test'
    )

    $workDir = Join-Path $ParentDir ("{0}-{1}" -f $NamePrefix, [guid]::NewGuid().ToString('n'))
    $null = New-Item -ItemType Directory -Path $workDir -Force
    $shellAssets = Join-Path $Root 'assets\runtime\setup\setup-shell'
    foreach ($name in @('tokens.json', 'winmint_hero_ui.png')) {
        $src = Join-Path $shellAssets $name
        if ($name -eq 'winmint_hero_ui.png' -and -not (Test-Path -LiteralPath $src)) {
            $src = Join-Path $Root 'assets\brand\winmint_hero_ui.png'
        }
        if (-not (Test-Path -LiteralPath $src)) {
            throw "Missing setup shell asset for tests: $src"
        }
        Copy-Item -LiteralPath $src -Destination (Join-Path $workDir $name) -Force
    }

    return [ordered]@{
        WorkDir     = $workDir
        StatusPath  = Join-Path $workDir 'setup-shell-status.json'
        ControlPath = Join-Path $workDir 'setup-shell-control.json'
    }
}

function Set-WinMintSetupShellTestControl {
    param(
        [Parameter(Mandatory)][string]$ControlPath,
        [Parameter(Mandatory)][string]$Phase,
        [string]$ProfileName = 'Preview'
    )

    @{
        phase       = $Phase
        startedAt   = (Get-Date -Format o)
        updatedAt   = (Get-Date -Format o)
        profileName = $ProfileName
        message     = ''
    } | ConvertTo-Json | Set-Content -LiteralPath $ControlPath -Encoding utf8
}

function Start-WinMintSetupShellTestHost {
    param(
        [Parameter(Mandatory)][string]$ExePath,
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string]$StatusPath,
        [Parameter(Mandatory)][string]$ControlPath,
        [int]$PollMs = 500,
        [int]$MinStartDwellMs = 0,
        [int]$MinCompleteDwellMs = 400,
        [switch]$EnableLog,
        [switch]$Preview
    )

    $argParts = @(
        "--shell-root `"$WorkDir`""
        "--status `"$StatusPath`""
        "--control `"$ControlPath`""
        '--poll-ms', $PollMs
        '--min-start-dwell-ms', $MinStartDwellMs
        '--min-complete-dwell-ms', $MinCompleteDwellMs
    )
    if ($EnableLog) { $argParts += '--log' }
    if ($Preview) { $argParts += '--preview' }
    Start-Process -FilePath $ExePath -ArgumentList ($argParts -join ' ') -PassThru
}

function Complete-WinMintSetupShellTestHost {
    param(
        [Parameter(Mandatory)]$Process,
        [Parameter(Mandatory)][string]$ControlPath,
        [string]$Phase = 'complete',
        [string]$ProfileName = 'Preview',
        [int]$TimeoutSeconds = 10,
        [switch]$FailIfTimeout
    )

    Set-WinMintSetupShellTestControl -ControlPath $ControlPath -Phase $Phase -ProfileName $ProfileName
    if ($Process.HasExited) { return }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and -not $Process.HasExited) {
        Start-Sleep -Milliseconds 100
    }
    if ($Process.HasExited) { return }

    $Process | Stop-Process -Force -ErrorAction SilentlyContinue
    if ($FailIfTimeout) {
        throw 'WinMintSetupShell.exe did not exit after complete control phase (requires an interactive desktop session).'
    }
}
