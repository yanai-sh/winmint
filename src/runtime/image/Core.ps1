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

function Get-WinMintPathTable {
    $root = Get-WinMintRepositoryRoot
    return [pscustomobject]@{
        RepoRoot = $root
        AppsRoot = (Join-Path $root 'apps')
        GuiRoot = (Join-Path $root 'apps\gui')
        GuiCargoToml = (Join-Path $root 'apps\gui\Cargo.toml')
        GuiBinary = (Join-Path $root 'apps\gui\bin\WinMint-GUI.exe')

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
        GuiToolsRoot = (Join-Path $root 'tools\gui')
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
            'GuiApp',
            'GuiCargoToml',
            'GuiBinary',
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
            'GuiToolsRoot',
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
        'GuiApp'         { $paths.GuiRoot }
        'GuiCargoToml'   { $paths.GuiCargoToml }
        'GuiBinary'      { $paths.GuiBinary }
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
        'GuiToolsRoot'   { $paths.GuiToolsRoot }
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

