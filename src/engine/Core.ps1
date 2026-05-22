#Requires -Version 7.3

function Get-WinMintRepositoryRoot {
    $rootVariable = Get-Variable -Name WinMintRepositoryRoot -Scope Script -ErrorAction SilentlyContinue
    if ($rootVariable -and $rootVariable.Value) { return $rootVariable.Value }
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Get-WinMintPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            'RepoRoot',
            'Root',
            'Apps',
            'LegacyUiApp',
            'LegacyUiEntry',
            'GuiApp',
            'GuiCargoToml',
            'GuiBinary',
            'Engine',
            'EngineRoot',
            'EngineEntry',
            'Agent',
            'AgentRoot',
            'Setup',
            'SetupRoot',
            'Assets',
            'AssetsRoot',
            'DocsRoot',
            'Config',
            'ConfigRoot',
            'Schemas',
            'SchemasRoot',
            'BuildProfileSchema',
            'BuildManifestSchema',
            'AgentStateSchema',
            'Tools',
            'ToolsRoot',
            'ValidationTool',
            'ValidationToolsRoot',
            'ReleaseTool',
            'ReleaseToolsRoot',
            'AuditTool',
            'GuiTool',
            'GuiToolsRoot',
            'UiBridgeTool',
            'UiBridgeToolsRoot',
            'Tests',
            'TestsRoot',
            'ContractTests',
            'Vendor',
            'Output',
            'OutputRoot',
            'Dist',
            'DistRoot'
        )]
        [string]$Name,

        [string]$ChildPath = ''
    )

    $root = Get-WinMintRepositoryRoot
    $relative = switch ($Name) {
        'RepoRoot'       { '' }
        'Root'           { '' }
        'Apps'           { 'apps' }
        'LegacyUiApp'    { 'apps\legacy-wpf' }
        'LegacyUiEntry'  { 'apps\legacy-wpf\App\Start-WinMintUI.ps1' }
        'GuiApp'        { 'apps\gui' }
        'GuiCargoToml'  { 'apps\gui\Cargo.toml' }
        'GuiBinary'     { 'apps\gui\bin\WinMint-GUI.exe' }
        'Engine'         { 'src\engine' }
        'EngineRoot'     { 'src\engine' }
        'EngineEntry'    { 'src\engine\WinMint.ps1' }
        'Agent'          { 'src\agent' }
        'AgentRoot'      { 'src\agent' }
        'Setup'          { 'src\setup' }
        'SetupRoot'      { 'src\setup' }
        'Assets'         { 'assets' }
        'AssetsRoot'     { 'assets' }
        'DocsRoot'       { 'docs' }
        'Config'         { 'config' }
        'ConfigRoot'     { 'config' }
        'Schemas'        { 'schemas' }
        'SchemasRoot'    { 'schemas' }
        'BuildProfileSchema'  { 'schemas\winmint.buildprofile.schema.json' }
        'BuildManifestSchema' { 'schemas\winmint.buildmanifest.schema.json' }
        'AgentStateSchema'    { 'schemas\winmint.agentstate.schema.json' }
        'Tools'          { 'tools' }
        'ToolsRoot'      { 'tools' }
        'ValidationTool' { 'tools\validation' }
        'ValidationToolsRoot' { 'tools\validation' }
        'ReleaseTool'    { 'tools\release' }
        'ReleaseToolsRoot' { 'tools\release' }
        'AuditTool'      { 'tools\audit' }
        'GuiTool'       { 'tools\gui' }
        'GuiToolsRoot'  { 'tools\gui' }
        'UiBridgeTool'   { 'tools\ui-bridge' }
        'UiBridgeToolsRoot' { 'tools\ui-bridge' }
        'Tests'          { 'tests' }
        'TestsRoot'      { 'tests' }
        'ContractTests'  { 'tests\contract' }
        'Vendor'         { 'vendor' }
        'Output'         { 'output' }
        'OutputRoot'     { 'output' }
        'Dist'           { 'dist' }
        'DistRoot'       { 'dist' }
    }

    $path = if ([string]::IsNullOrWhiteSpace($relative)) {
        $root
    } else {
        Join-Path $root $relative
    }
    if (-not [string]::IsNullOrWhiteSpace($ChildPath)) {
        $path = Join-Path $path $ChildPath
    }
    return $path
}

function Get-WinMintOutputDirectory {
    $out = Get-WinMintPath -Name Output
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
