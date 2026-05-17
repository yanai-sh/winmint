#Requires -Version 7.3

function Get-WinWSRepositoryRoot {
    $rootVariable = Get-Variable -Name WinWSRepositoryRoot -Scope Script -ErrorAction SilentlyContinue
    if ($rootVariable -and $rootVariable.Value) { return $rootVariable.Value }
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Get-WinWSOutputDirectory {
    $root = Get-WinWSRepositoryRoot
    $out = Join-Path $root 'output'
    $null = New-Item -ItemType Directory -Path $out -Force
    return $out
}

function Write-WinWSProgress {
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

function Get-WinWSIsoArchitectureHint {
    param([string]$Path)
    $name = [IO.Path]::GetFileName($Path)
    if ($name -match '(?i)(arm64|aarch64)') { return 'arm64' }
    if ($name -match '(?i)(x64|amd64)') { return 'amd64' }
    if ($name -match '(?i)(x86)') { return 'x86' }
    return $null
}
