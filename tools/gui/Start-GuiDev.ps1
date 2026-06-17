#Requires -Version 7.6
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Release,
    [switch]$BuildOnly,
    [switch]$Elevate,
    [switch]$CustomTitlebar,
    [switch]$SystemTitlebar,
    [string]$RustTarget = '',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AppArgs = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:WinMintRepositoryRoot = $root
. (Join-Path $root 'src\runtime\image\Core.ps1')

function Add-GuiDevToolPath {
    param([string]$ToolPath)

    if ([string]::IsNullOrWhiteSpace($ToolPath)) {
        return
    }
    if (-not (Test-Path -LiteralPath $ToolPath -PathType Container)) {
        return
    }

    $existing = @($env:Path -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($existing -notcontains $ToolPath) {
        $env:Path = (@($existing) + $ToolPath) -join ';'
    }
}

function Initialize-GuiDevToolPath {
    foreach ($scope in @('Machine', 'User')) {
        $pathValue = [Environment]::GetEnvironmentVariable('Path', $scope)
        foreach ($entry in @($pathValue -split ';')) {
            Add-GuiDevToolPath -ToolPath $entry
        }
    }

    Add-GuiDevToolPath -ToolPath (Join-Path $env:USERPROFILE '.cargo\bin')
    Add-GuiDevToolPath -ToolPath 'C:\Program Files\LLVM\bin'
}

function ConvertTo-CmdQuotedArgument {
    param([Parameter(Mandatory)][string]$Value)

    '"' + ($Value -replace '"', '\"') + '"'
}

function Get-VsDevCmdPath {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
        return ''
    }

    $installationPath = & $vswhere `
        -latest `
        -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($installationPath)) {
        return ''
    }

    $candidate = Join-Path ([string]$installationPath) 'Common7\Tools\VsDevCmd.bat'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return $candidate
    }

    ''
}

function Get-VsInstallPathFromDevCmd {
    param(
        [Parameter(Mandatory)][string]$DevCmdPath
    )

    $toolsPath = Split-Path -Parent $DevCmdPath
    $commonPath = Split-Path -Parent $toolsPath
    Split-Path -Parent $commonPath
}

function Get-VsInstallerSetupPath {
    $setup = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\setup.exe'
    if (Test-Path -LiteralPath $setup -PathType Leaf) {
        return $setup
    }

    ''
}

function Get-RustBuildTarget {
    param(
        [string]$TargetOverride
    )

    if (-not [string]::IsNullOrWhiteSpace($TargetOverride)) {
        return $TargetOverride
    }
    if (-not [string]::IsNullOrWhiteSpace($env:CARGO_BUILD_TARGET)) {
        return [string]$env:CARGO_BUILD_TARGET
    }

    $rustc = Get-Command rustc -ErrorAction SilentlyContinue
    if (-not $rustc) {
        return ''
    }

    $version = & $rustc.Source -vV
    if ($LASTEXITCODE -ne 0) {
        return ''
    }

    $hostLine = @($version | Where-Object { $_ -match '^host:\s*(.+)$' } | Select-Object -First 1)
    if ($hostLine.Count -gt 0 -and $hostLine[0] -match '^host:\s*(.+)$') {
        return $Matches[1]
    }

    ''
}

function ConvertTo-VsArchitecture {
    param(
        [Parameter(Mandatory)][string]$Architecture
    )

    switch -Regex ($Architecture.ToLowerInvariant()) {
        '^(aarch64|arm64)' { return 'arm64' }
        '^(x86_64|amd64)' { return 'amd64' }
        '^(i686|i586|x86)' { return 'x86' }
        default { return '' }
    }
}

function Get-NativeVsHostArchitecture {
    $processorArchitecture = if (-not [string]::IsNullOrWhiteSpace($env:PROCESSOR_ARCHITEW6432)) {
        [string]$env:PROCESSOR_ARCHITEW6432
    } else {
        [string]$env:PROCESSOR_ARCHITECTURE
    }

    $vsArchitecture = ConvertTo-VsArchitecture -Architecture $processorArchitecture
    if ([string]::IsNullOrWhiteSpace($vsArchitecture)) {
        return 'amd64'
    }

    $vsArchitecture
}

function Assert-VsDeveloperEnvironment {
    param(
        [Parameter(Mandatory)][string]$DevCmdPath,
        [Parameter(Mandatory)][string]$TargetArchitecture,
        [Parameter(Mandatory)][string]$HostArchitecture
    )

    $preflight = 'call {0} -arch={1} -host_arch={2} >nul && where link.exe >nul' -f `
        (ConvertTo-CmdQuotedArgument -Value $DevCmdPath),
        $TargetArchitecture,
        $HostArchitecture

    & cmd.exe /d /s /c $preflight
    if ($LASTEXITCODE -eq 0) {
        return
    }

    $installPath = Get-VsInstallPathFromDevCmd -DevCmdPath $DevCmdPath
    $setupPath = Get-VsInstallerSetupPath
    $modifyCommand = if ([string]::IsNullOrWhiteSpace($setupPath)) {
        'Open Visual Studio Installer, modify Build Tools, and add "MSVC C++ ARM64/ARM64EC build tools".'
    } else {
        @"
`$setup = '$setupPath'
`$arguments = @(
    'modify',
    '--installPath', '$installPath',
    '--add', 'Microsoft.VisualStudio.Component.VC.Tools.ARM64',
    '--includeRecommended',
    '--passive',
    '--norestart'
)
Start-Process -FilePath `$setup -ArgumentList `$arguments -Verb RunAs -Wait
"@
    }

    if ($TargetArchitecture -eq 'arm64') {
        throw @"
Visual Studio Build Tools is installed, but the ARM64 MSVC linker was not found.

Install the ARM64 C++ build tools component, then rerun this script:

$modifyCommand
"@
    }

    throw @"
Visual Studio Build Tools is installed, but link.exe was not found for target '$TargetArchitecture'.

Modify Build Tools and make sure the matching MSVC C++ build tools component is installed.
"@
}

Initialize-GuiDevToolPath

$cargo = Get-Command cargo -ErrorAction SilentlyContinue
if (-not $cargo) {
    throw 'Rust cargo was not found. Install Rust with rustup before running GPUI.'
}

$manifest = Get-WinMintPath -Name GuiCargoToml
# -Elevate builds (non-elevated) then launches the binary under UAC, so the
# subcommand is 'build' — cargo never runs the app itself in that mode.
$subcommand = if ($BuildOnly -or $Elevate) { 'build' } else { 'run' }
$arguments = @($subcommand, '--manifest-path', $manifest)
if ($Release) {
    $arguments = @($subcommand, '--release', '--manifest-path', $manifest)
}
if (-not [string]::IsNullOrWhiteSpace($RustTarget)) {
    $arguments += @('--target', $RustTarget)
}
if ($CustomTitlebar -and $SystemTitlebar) {
    throw 'Use either -CustomTitlebar or -SystemTitlebar, not both.'
}

# Runtime args forwarded to the app (whether via `cargo run` or the elevated launch).
$runtimeArgs = @()
if (-not $BuildOnly) {
    if ($SystemTitlebar) {
        $runtimeArgs += '--system-titlebar'
    }
    $runtimeArgs += @($AppArgs | Where-Object { $_ -ne '--' })
}
if ($subcommand -eq 'run' -and $runtimeArgs.Count -gt 0) {
    $arguments += @('--') + $runtimeArgs
}

$buildTarget = Get-RustBuildTarget -TargetOverride $RustTarget
$targetVsArchitecture = ConvertTo-VsArchitecture -Architecture $buildTarget
if ([string]::IsNullOrWhiteSpace($targetVsArchitecture)) {
    $targetVsArchitecture = Get-NativeVsHostArchitecture
}
$hostVsArchitecture = Get-NativeVsHostArchitecture

$guiApp = Get-WinMintPath -Name GuiApp
Push-Location $guiApp
try {
    $vsDevCmd = Get-VsDevCmdPath
    if ([string]::IsNullOrWhiteSpace($vsDevCmd)) {
        if (Get-Command link.exe -ErrorAction SilentlyContinue) {
            & $cargo.Source @arguments
        }
        else {
            throw @'
MSVC link.exe was not found. Install Visual Studio Build Tools with the C++ workload:

winget install --id Microsoft.VisualStudio.BuildTools --source winget --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"

If Build Tools is already installed, modify it in Visual Studio Installer and add "Desktop development with C++".
'@
        }
    }
    else {
        Assert-VsDeveloperEnvironment `
            -DevCmdPath $vsDevCmd `
            -TargetArchitecture $targetVsArchitecture `
            -HostArchitecture $hostVsArchitecture

        Write-Host "Using Visual Studio tools: target=$targetVsArchitecture host=$hostVsArchitecture rust=$buildTarget"
        $cargoLine = @($cargo.Source) + $arguments |
            ForEach-Object { ConvertTo-CmdQuotedArgument -Value ([string]$_) }
        $command = 'call {0} -arch={1} -host_arch={2} >nul && {3}' -f `
            (ConvertTo-CmdQuotedArgument -Value $vsDevCmd),
            $targetVsArchitecture,
            $hostVsArchitecture,
            ($cargoLine -join ' ')

        & cmd.exe /d /s /c $command
    }

    if ($LASTEXITCODE -ne 0) {
        throw "cargo $subcommand failed with exit code $LASTEXITCODE."
    }

    if ($Elevate -and -not $BuildOnly) {
        $targetRoot = Join-Path $root 'target'
        $targetDir = if (-not [string]::IsNullOrWhiteSpace($RustTarget)) {
            Join-Path $targetRoot $RustTarget
        } else {
            $targetRoot
        }
        $config = if ($Release) { 'release' } else { 'debug' }
        $exe = Join-Path (Join-Path $targetDir $config) 'winmint-gui.exe'
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
            throw "Built WinMint GUI binary was not found at '$exe'."
        }

        Write-Host "Launching elevated (UAC prompt): $exe"
        $startArgs = @{
            FilePath         = $exe
            Verb             = 'RunAs'
            WorkingDirectory = $root
            Wait             = $true
            PassThru         = $true
        }
        if ($runtimeArgs.Count -gt 0) {
            $startArgs.ArgumentList = $runtimeArgs
        }
        $proc = Start-Process @startArgs
        if ($null -ne $proc -and $proc.ExitCode -ne 0) {
            throw "Elevated WinMint GUI exited with code $($proc.ExitCode)."
        }
    }
}
finally {
    Pop-Location
}

