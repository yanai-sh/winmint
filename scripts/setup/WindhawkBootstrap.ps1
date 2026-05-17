#Requires -Version 5.1
<#
.SYNOPSIS
Applies the WinWS Windhawk desktop preset.

.DESCRIPTION
Installs a version-controlled Windhawk preset without bundling compiled mod DLLs.
The preset stores mod ids, pinned versions, target filters, and settings. This
script downloads official Windhawk mod sources and precompiled mod DLLs at
first logon, writes Windhawk registry configuration, stages the runtime helper
files for the current architecture, and restarts Windhawk.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PresetFile = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'assets\windhawk\preset.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$WindhawkRoot = "$env:PROGRAMDATA\Windhawk",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$WindhawkInstallRoot = "$env:ProgramFiles\Windhawk",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ModsBaseUrl = 'https://mods.windhawk.net/mods',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogPath = "$env:PUBLIC\Documents\WinWS\WindhawkBootstrap.log",

    [Parameter()]
    [switch]$NoRestartExplorer
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:ExitCode = 0

. (Join-Path $PSScriptRoot 'WindhawkBootstrap.Helpers.ps1')

$stageDir = $null
$runtimeNeedsRestart = $false
$runtimeRestarted = $false
try {
    if (-not (Test-WindowsHost)) { throw 'Windhawk bootstrap requires Windows.' }
    if (-not (Test-Administrator)) { throw 'Windhawk bootstrap must run elevated.' }

    $PresetFile = [System.IO.Path]::GetFullPath($PresetFile)
    $WindhawkRoot = [System.IO.Path]::GetFullPath($WindhawkRoot)
    if (-not (Test-Path -LiteralPath $PresetFile)) { throw "Windhawk preset not found: $PresetFile" }
    $WindhawkInstallRoot = Resolve-WindhawkInstallRoot
    Write-WindhawkLog "Windhawk install root: $WindhawkInstallRoot"

    $preset = Get-Content -LiteralPath $PresetFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $preset.mods -or @($preset.mods).Count -eq 0) { throw 'Windhawk preset contains no mods.' }

    Write-WindhawkLog "Applying Windhawk preset: $PresetFile"
    $hostArchitecture = Get-WindhawkHostArchitecture
    Write-WindhawkLog "Host architecture: $($hostArchitecture.Name)"

    $stageDir = Join-Path ([System.IO.Path]::GetTempPath()) ('WinWS-WindhawkPreset-{0}' -f ([guid]::NewGuid().ToString('N')))
    $null = New-Item -ItemType Directory -Path $stageDir -Force

    $prepared = [System.Collections.Generic.List[object]]::new()
    $allSubfolders = [System.Collections.Generic.List[string]]::new()
    foreach ($mod in @($preset.mods)) {
        if ([string]::IsNullOrWhiteSpace([string]$mod.id)) { throw 'Windhawk preset has a mod without an id.' }
        $version = Resolve-WindhawkModVersion -Mod $mod
        $targetDllName = '{0}_{1}_{2}.dll' -f $mod.id, $version, (Get-Random -Minimum 100000 -Maximum 999999)
        $subfolders = @(Get-WindhawkArchitectureSubfolder -Architecture @($mod.architecture) -HostArchitecture $hostArchitecture)
        foreach ($subfolder in $subfolders) {
            if (-not $allSubfolders.Contains($subfolder)) { $allSubfolders.Add($subfolder) }
        }

        $sourceUrl = if ($mod.PSObject.Properties['sourceUrl'] -and $mod.sourceUrl) { [string]$mod.sourceUrl } else { ('{0}/{1}.wh.cpp' -f $ModsBaseUrl.TrimEnd('/'), $mod.id) }
        $sourceStagePath = Join-Path $stageDir "ModsSource\$($mod.id).wh.cpp"
        Write-WindhawkLog "Downloading $($mod.id) source."
        Invoke-WindhawkDownload -Uri $sourceUrl -OutFile $sourceStagePath

        $dlls = [System.Collections.Generic.List[object]]::new()
        foreach ($subfolder in $subfolders) {
            $dllUrl = '{0}/{1}/{2}_{3}.dll' -f $ModsBaseUrl.TrimEnd('/'), $mod.id, $version, $subfolder
            $dllStagePath = Join-Path $stageDir "Engine\Mods\$subfolder\$targetDllName"
            Write-WindhawkLog "Downloading $($mod.id) $version for $subfolder."
            Invoke-WindhawkDownload -Uri $dllUrl -OutFile $dllStagePath
            $dlls.Add([pscustomobject]@{
                Subfolder = $subfolder
                StagePath = $dllStagePath
                FinalPath = Join-Path $WindhawkRoot "Engine\Mods\$subfolder\$targetDllName"
            })
        }

        $prepared.Add([pscustomobject]@{
            Mod = $mod
            Id = [string]$mod.id
            Version = $version
            LibraryFileName = $targetDllName
            Subfolders = $subfolders
            SourceStagePath = $sourceStagePath
            SourceFinalPath = Join-Path $WindhawkRoot "ModsSource\$($mod.id).wh.cpp"
            Dlls = $dlls.ToArray()
            Rating = if ($mod.PSObject.Properties['rating']) { $mod.rating } else { $null }
        })
    }

    Stop-WindhawkRuntime
    $runtimeNeedsRestart = $true
    $null = New-Item -ItemType Directory -Path $WindhawkRoot -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $WindhawkRoot 'ModsSource') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $WindhawkRoot 'Engine\Mods') -Force

    foreach ($subfolder in $allSubfolders) {
        Copy-WindhawkRuntimeHelper -Subfolder $subfolder
    }

    $applied = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $prepared) {
        $sourceParent = Split-Path -Parent $item.SourceFinalPath
        if (-not (Test-Path -LiteralPath $sourceParent)) {
            $null = New-Item -ItemType Directory -Path $sourceParent -Force
        }
        Copy-Item -LiteralPath $item.SourceStagePath -Destination $item.SourceFinalPath -Force

        foreach ($dll in @($item.Dlls)) {
            $dllParent = Split-Path -Parent $dll.FinalPath
            if (-not (Test-Path -LiteralPath $dllParent)) {
                $null = New-Item -ItemType Directory -Path $dllParent -Force
            }
            Copy-Item -LiteralPath $dll.StagePath -Destination $dll.FinalPath -Force
        }

        Set-WindhawkModRegistry -Mod $item.Mod -Version $item.Version -LibraryFileName $item.LibraryFileName
        Remove-WindhawkOldModFile -ModId $item.Id -Subfolders $item.Subfolders -CurrentLibraryFileName $item.LibraryFileName

        $applied.Add([pscustomobject]@{
            Id = $item.Id
            Version = $item.Version
            Rating = $item.Rating
        })
        Write-WindhawkLog "Enabled $($item.Id) $($item.Version)." -Level OK
    }

    Write-WindhawkUserProfile -AppliedMods $applied.ToArray() -Preset $preset
    Remove-WindhawkPresetDrift -PresetModIds @($applied | ForEach-Object { $_.Id })
    Start-WindhawkRuntime
    $runtimeRestarted = $true
    Restart-ExplorerForWindhawk
    foreach ($item in $prepared) {
        Remove-WindhawkOldModFile -ModId $item.Id -Subfolders $item.Subfolders -CurrentLibraryFileName $item.LibraryFileName
    }
    Remove-WindhawkPresetDrift -PresetModIds @($applied | ForEach-Object { $_.Id })
    Write-WindhawkLog "Windhawk preset applied ($($applied.Count) mods)." -Level OK
}
catch {
    Write-WindhawkLog $_.Exception.Message -Level ERROR
    $script:ExitCode = 1
}
finally {
    if ($runtimeNeedsRestart -and -not $runtimeRestarted) {
        Write-WindhawkLog 'Restarting Windhawk after bootstrap failure.' -Level WARN
        Start-WindhawkRuntime
    }
    if ($stageDir -and (Test-Path -LiteralPath $stageDir)) {
        Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit $script:ExitCode
