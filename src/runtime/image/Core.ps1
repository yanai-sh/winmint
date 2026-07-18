#Requires -Version 7.6

function Get-WinMintRepositoryRoot {
    $rootVariable = Get-Variable -Name WinMintRepositoryRoot -Scope Script -ErrorAction SilentlyContinue
    if ($rootVariable -and $rootVariable.Value) { return $rootVariable.Value }
    $current = $PSScriptRoot
    while ($current) {
        $hasSourceRootMarker = (Test-Path -LiteralPath (Join-Path $current 'AGENTS.md')) -or
            (Test-Path -LiteralPath (Join-Path $current '.git'))
        $hasReleaseRootMarker = (Test-Path -LiteralPath (Join-Path $current 'WinMint-CLI.ps1') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $current 'src\runtime\modules') -PathType Container)
        if ($hasSourceRootMarker -or $hasReleaseRootMarker) {
            return (Resolve-Path -LiteralPath $current).Path
        }
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }
    throw 'Unable to determine WinMint repository root.'
}

function Get-WinMintHostSetupShellBinArch {
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch -Regex ([string]$arch) {
        '^ARM64$' { return 'arm64' }
        default { return 'x64' }
    }
}

function Get-WinMintSetupShellBinFolder {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    Join-Path $RepositoryRoot "assets\runtime\setup\setup-shell\bin\$(Get-WinMintHostSetupShellBinArch)"
}

function Get-WinMintSetupShellWizardHostPath {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $candidate = Join-Path (Get-WinMintSetupShellBinFolder -RepositoryRoot $RepositoryRoot) 'WinMintSetupShell.exe'
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "WinMintSetupShell.exe (WebView2 wizard) was not found at '$candidate'. Run: pwsh -NoProfile -File tools\release\Build-WinMintSetupShell.ps1"
    }
    return $candidate
}

function Get-WinMintSetupShellNativeHostPath {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $binFolder = Get-WinMintSetupShellBinFolder -RepositoryRoot $RepositoryRoot
    $candidate = Join-Path $binFolder 'WinMintSetupShell.Native.exe'
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "WinMintSetupShell.Native.exe was not found at '$candidate'. Run: pwsh -NoProfile -File tools\release\Build-WinMintSetupShell.ps1"
    }
    return $candidate
}

function Get-WinMintSetupShellHostPath {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    return Get-WinMintSetupShellWizardHostPath -RepositoryRoot $RepositoryRoot
}

function Get-WinMintPathTable {
    $root = Get-WinMintRepositoryRoot
    return [pscustomobject]@{
        RepoRoot = $root
        AppsRoot = (Join-Path $root 'apps')
        SetupShellAssetsRoot = (Join-Path $root 'assets\runtime\setup\setup-shell')

        RuntimeRoot = (Join-Path $root 'src\runtime')
        RuntimeImageRoot = (Join-Path $root 'src\runtime\image')
        RuntimeImageEntry = (Join-Path $root 'src\runtime\image\WinMint.ps1')
        RuntimeSetupRoot = (Join-Path $root 'src\runtime\setup')
        RuntimeFirstLogonRoot = (Join-Path $root 'src\runtime\firstlogon')

        AssetsRoot = (Join-Path $root 'assets')
        DocsRoot = (Join-Path $root 'docs')
        ConfigRoot = (Join-Path $root 'config')
        SchemasRoot = (Join-Path $root 'schemas')
        BuildProfileSchema = (Join-Path $root 'schemas\winmint.buildprofile.schema.json')
        BuildManifestSchema = (Join-Path $root 'schemas\winmint.buildmanifest.schema.json')
        AgentStateSchema = (Join-Path $root 'schemas\winmint.agentstate.schema.json')
        BuildDeltaSchema = (Join-Path $root 'schemas\winmint.builddelta.schema.json')
        RuntimeModulesRoot = (Join-Path $root 'src\runtime\modules')

        ToolsRoot = (Join-Path $root 'tools')
        ValidationToolsRoot = (Join-Path $root 'tools\validation')
        ReleaseToolsRoot = (Join-Path $root 'tools\release')
        AuditToolsRoot = (Join-Path $root 'tools\audit')
        UiBridgeToolsRoot = (Join-Path $root 'tools\ui-bridge')
        VmToolsRoot = (Join-Path $root 'tools\vm')
        MediaToolsRoot = (Join-Path $root 'tools\media')
        AssetsToolsRoot = (Join-Path $root 'tools\assets')

        TestsRoot = (Join-Path $root 'tests')
        ContractTestsRoot = (Join-Path $root 'tests\contract')
        FixturesRoot = (Join-Path $root 'tests\fixtures')
        OutputRoot = (Join-Path $root 'output')
        DistRoot = (Join-Path $root 'dist')
    }
}

function Get-WinMintPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            'RepoRoot',
            'SetupShell',
            'SetupShellWizardBinary',
            'AppsRoot',
            'RuntimeRoot',
            'RuntimeImageRoot',
            'RuntimeImageEntry',
            'RuntimeSetupRoot',
            'RuntimeFirstLogonRoot',
            'AssetsRoot',
            'DocsRoot',
            'ConfigRoot',
            'SchemasRoot',
            'BuildProfileSchema',
            'BuildManifestSchema',
            'AgentStateSchema',
            'BuildDeltaSchema',
            'RuntimeModulesRoot',
            'ToolsRoot',
            'ValidationToolsRoot',
            'ReleaseToolsRoot',
            'AuditToolsRoot',
            'UiBridgeToolsRoot',
            'VmToolsRoot',
            'MediaToolsRoot',
            'AssetsToolsRoot',
            'TestsRoot',
            'ContractTestsRoot',
            'FixturesRoot',
            'OutputRoot',
            'DistRoot'
        )]
        [string]$Name,

        [string]$ChildPath = ''
    )

    $paths = Get-WinMintPathTable
    $path = switch ($Name) {
        'RepoRoot'       { $paths.RepoRoot }
        'SetupShell'              { $paths.SetupShellAssetsRoot }
        'SetupShellWizardBinary'  { Join-Path $paths.SetupShellAssetsRoot "bin\$(Get-WinMintHostSetupShellBinArch)\WinMintSetupShell.exe" }
        'AppsRoot'       { $paths.AppsRoot }
        'RuntimeRoot'    { $paths.RuntimeRoot }
        'RuntimeImageRoot' { $paths.RuntimeImageRoot }
        'RuntimeImageEntry' { $paths.RuntimeImageEntry }
        'RuntimeSetupRoot' { $paths.RuntimeSetupRoot }
        'RuntimeFirstLogonRoot' { $paths.RuntimeFirstLogonRoot }
        'AssetsRoot'     { $paths.AssetsRoot }
        'DocsRoot'       { $paths.DocsRoot }
        'ConfigRoot'     { $paths.ConfigRoot }
        'SchemasRoot'    { $paths.SchemasRoot }
        'BuildProfileSchema'  { $paths.BuildProfileSchema }
        'BuildManifestSchema' { $paths.BuildManifestSchema }
        'AgentStateSchema'    { $paths.AgentStateSchema }
        'BuildDeltaSchema'    { $paths.BuildDeltaSchema }
        'RuntimeModulesRoot'  { $paths.RuntimeModulesRoot }
        'ToolsRoot'      { $paths.ToolsRoot }
        'ValidationToolsRoot' { $paths.ValidationToolsRoot }
        'ReleaseToolsRoot' { $paths.ReleaseToolsRoot }
        'AuditToolsRoot' { $paths.AuditToolsRoot }
        'UiBridgeToolsRoot' { $paths.UiBridgeToolsRoot }
        'VmToolsRoot'    { $paths.VmToolsRoot }
        'MediaToolsRoot' { $paths.MediaToolsRoot }
        'AssetsToolsRoot' { $paths.AssetsToolsRoot }
        'TestsRoot'      { $paths.TestsRoot }
        'ContractTestsRoot' { $paths.ContractTestsRoot }
        'FixturesRoot'   { $paths.FixturesRoot }
        'OutputRoot'     { $paths.OutputRoot }
        'DistRoot'       { $paths.DistRoot }
    }
    if (-not [string]::IsNullOrWhiteSpace($ChildPath)) {
        $path = Join-Path $path $ChildPath
    }
    return $path
}

function Get-WinMintOutputDirectory {
    $out = Get-WinMintPath -Name OutputRoot
    $null = New-Item -ItemType Directory -Path $out -Force
    return $out
}

function Write-WinMintProgress {
    param(
        [string]$Stage,
        [string]$Message,
        [ValidateSet('Info','OK','Warn','Error','Section')]
        [string]$Level = 'Info',
        [scriptblock]$ProgressHandler
    )

    $progressEvent = [pscustomobject]@{
        Time    = [DateTimeOffset]::Now.ToString('o')
        Stage   = $Stage
        Level   = $Level
        Message = $Message
    }
    $scriptHandler = Get-Variable -Name WinMintProgressHandler -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    # Route through Log* for verbose file + human Spectre. Log* also emits to
    # script:WinMintProgressHandler when installed; invoke an explicit
    # -ProgressHandler only when the script handler is not yet set (early engine).
    if (Get-Command Log -ErrorAction SilentlyContinue) {
        switch ($Level) {
            'OK'      { LogOK $Message }
            'Warn'    { LogWarn $Message }
            'Error'   { LogErr $Message }
            'Section' {
                if (Get-Command LogSection -ErrorAction SilentlyContinue) { LogSection $Message }
                else { Log $Message }
            }
            default   { Log $Message }
        }
        if ($ProgressHandler -and $null -eq $scriptHandler) {
            & $ProgressHandler $progressEvent
        }
        return
    }
    if ($ProgressHandler) { & $ProgressHandler $progressEvent }
    else { Write-Information "[$Level] $Stage $Message" -InformationAction Continue }
}

function Get-WinMintIsoArchitectureHint {
    param([string]$Path)
    $name = [IO.Path]::GetFileName($Path)
    if ($name -match '(?i)(arm64|aarch64)') { return 'arm64' }
    if ($name -match '(?i)(x64|amd64)') { return 'amd64' }
    if ($name -match '(?i)(x86)') { return 'x86' }
    return $null
}

