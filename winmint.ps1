#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Repository = 'yanai-sh/winmint',
    [string]$Version = 'latest',
    [string]$InstallRoot = '',
    [ValidateSet('Ui','Gui','Headless')]
    [string]$Mode = 'Ui',
    [switch]$Gui,
    [switch]$Headless,
    [string]$ProfilePath = '',
    [string]$SourceIso = '',
    [string]$UupDumpZip = '',
    [string]$SourceIsoOverride = '',
    [ValidateSet('amd64','arm64','x86')]
    [string]$Architecture = '',
    [switch]$DryRun,
    [switch]$ExportHostDrivers,
    [switch]$Developer,
    [switch]$Copilot,
    [switch]$DesktopUI,
    [switch]$Gaming,
    [switch]$NonInteractive,
    [switch]$ValidateOnly,
    [switch]$Json,
    [switch]$NoProgress,
    [switch]$Quiet,
    [switch]$AllowElevate,
    [switch]$Yes,
    [switch]$NoLaunch,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Write-WinWSBootstrapLog {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','OK')]
        [string]$Level = 'INFO'
    )

    $stamp = Get-Date -Format 'HH:mm:ss.fff'
    Write-Host "[$stamp] [$Level] $Message"
}

function Enable-WinWSBootstrapTls {
    try {
        $tls12 = [Net.SecurityProtocolType]::Tls12
        if (-not ([Net.ServicePointManager]::SecurityProtocol -band $tls12)) {
            [Net.ServicePointManager]::SecurityProtocol =
                [Net.ServicePointManager]::SecurityProtocol -bor $tls12
        }
    } catch {
        Write-WinWSBootstrapLog "TLS setup warning: $($_.Exception.Message)" 'WARN'
    }
}

function Get-WinWSRelease {
    param([string]$Repo, [string]$RequestedVersion)

    $encodedVersion = [uri]::EscapeDataString($RequestedVersion)
    $releasePath = if ($RequestedVersion -eq 'latest') {
        "https://api.github.com/repos/$Repo/releases/latest"
    } else {
        "https://api.github.com/repos/$Repo/releases/tags/$encodedVersion"
    }

    Write-WinWSBootstrapLog "Querying GitHub release '$RequestedVersion' from $Repo."
    Invoke-RestMethod -Uri $releasePath -Headers @{
        'Accept' = 'application/vnd.github+json'
        'User-Agent' = 'WinMint-Bootstrap'
    } -UseBasicParsing
}

function Select-WinWSAsset {
    param(
        [Parameter(Mandatory)]$Release,
        [string]$Extension,
        [string]$PreferredName
    )

    $assets = @($Release.assets)
    if ($assets.Count -eq 0) {
        throw "Release '$($Release.tag_name)' has no downloadable assets."
    }

    $preferred = $assets | Where-Object { $_.name -eq $PreferredName } | Select-Object -First 1
    if ($preferred) { return $preferred }

    $matching = $assets |
        Where-Object { $_.name -like "*$Extension" -and $_.name -match '(?i)winmint|winws|windows' } |
        Select-Object -First 1
    if ($matching) { return $matching }

    return $assets | Where-Object { $_.name -like "*$Extension" } | Select-Object -First 1
}

function Save-WinWSAsset {
    param(
        [Parameter(Mandatory)]$Asset,
        [string]$Destination
    )

    Write-WinWSBootstrapLog "Downloading $($Asset.name)."
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $Destination -Headers @{
        'User-Agent' = 'WinMint-Bootstrap'
    } -UseBasicParsing
}

function Get-WinWSFileSha256 {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = $sha.ComputeHash($stream)
            return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '').ToUpperInvariant()
        }
        finally {
            $sha.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Test-WinWSArchiveHash {
    param([string]$ArchivePath, [string]$ChecksumPath)

    $text = Get-Content -LiteralPath $ChecksumPath -Raw
    $match = [regex]::Match($text, '(?i)\b[a-f0-9]{64}\b')
    if (-not $match.Success) {
        throw "Checksum file '$ChecksumPath' does not contain a SHA256 hash."
    }

    $expected = $match.Value.ToUpperInvariant()
    $actual = Get-WinWSFileSha256 -Path $ArchivePath
    if ($actual -ne $expected) {
        throw "Archive SHA256 mismatch. Expected $expected, got $actual."
    }

    Write-WinWSBootstrapLog "Verified SHA256 $actual." 'OK'
}

function Expand-WinWSRelease {
    param([string]$ArchivePath, [string]$Destination, [switch]$Overwrite)

    if ((Test-Path -LiteralPath $Destination) -and $Overwrite) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $Destination -Force
}

function Find-WinWSUiScript {
    param([string]$Root)

    $script = Get-ChildItem -LiteralPath $Root -Filter 'WinMint-UI.ps1' -Recurse -File |
        Select-Object -First 1
    if (-not $script) {
        throw "WinMint-UI.ps1 was not found under '$Root'."
    }

    return $script.FullName
}

function Find-WinWSCliScript {
    param([string]$Root)

    $script = Get-ChildItem -LiteralPath $Root -Filter 'WinMint-CLI.ps1' -Recurse -File |
        Select-Object -First 1
    if (-not $script) {
        throw "WinMint-CLI.ps1 was not found under '$Root'."
    }

    return $script.FullName
}

function Find-WinWSGuiScript {
    param([string]$Root)

    foreach ($relativePath in @(
            'WinMint-GUI.ps1',
            'scripts\gpui\Start-GpuiLab.ps1'
        )) {
        $candidate = Join-Path $Root $relativePath
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    throw "The WIP GUI is not packaged in this WinMint release yet. Use the default UI, or pass -Headless."
}

function Resolve-WinWSLaunchMode {
    param(
        [string]$RequestedMode,
        [switch]$UseGui,
        [switch]$UseHeadless
    )

    if ($UseGui -and $UseHeadless) {
        throw 'Use either -Gui or -Headless, not both.'
    }
    if ($UseGui -and $RequestedMode -ne 'Ui') {
        throw 'Use either -Mode or -Gui, not both.'
    }
    if ($UseHeadless -and $RequestedMode -ne 'Ui') {
        throw 'Use either -Mode or -Headless, not both.'
    }
    if ($UseGui) { return 'Gui' }
    if ($UseHeadless) { return 'Headless' }
    return $RequestedMode
}

function Add-WinWSArgumentValue {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[string]]$Arguments,
        [string]$Name,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    $Arguments.Add("-$Name")
    $Arguments.Add($Value)
}

function New-WinWSLaunchArguments {
    param(
        [string]$ScriptPath,
        [string]$LaunchMode
    )

    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($value in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)) {
        $arguments.Add($value)
    }

    if ($LaunchMode -eq 'Headless') {
        Add-WinWSArgumentValue -Arguments $arguments -Name 'ProfilePath' -Value $ProfilePath
        Add-WinWSArgumentValue -Arguments $arguments -Name 'SourceIso' -Value $SourceIso
        Add-WinWSArgumentValue -Arguments $arguments -Name 'UupDumpZip' -Value $UupDumpZip
        Add-WinWSArgumentValue -Arguments $arguments -Name 'SourceIsoOverride' -Value $SourceIsoOverride
        Add-WinWSArgumentValue -Arguments $arguments -Name 'Architecture' -Value $Architecture
        if ($Developer) { $arguments.Add('-Developer') }
        if ($Copilot) { $arguments.Add('-Copilot') }
        if ($DesktopUI) { $arguments.Add('-DesktopUI') }
        if ($Gaming) { $arguments.Add('-Gaming') }
        if ($NonInteractive) { $arguments.Add('-NonInteractive') }
        if ($ValidateOnly) { $arguments.Add('-ValidateOnly') }
        if ($Json) { $arguments.Add('-Json') }
        if ($NoProgress) { $arguments.Add('-NoProgress') }
        if ($Quiet) { $arguments.Add('-Quiet') }
        if ($AllowElevate) { $arguments.Add('-AllowElevate') }
        if ($Yes) { $arguments.Add('-Yes') }
    }

    if ($DryRun) { $arguments.Add('-DryRun') }
    if ($ExportHostDrivers -and $LaunchMode -ne 'Gui') { $arguments.Add('-ExportHostDrivers') }
    return $arguments.ToArray()
}

function Get-WinWSObjectProperty {
    param([object]$InputObject, [string]$Name)

    if (-not $InputObject) {
        return ''
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) {
        return [string]$property.Value
    }

    return ''
}

function Test-WinWSInstalledVersion {
    param(
        [string]$Root,
        [string]$MarkerPath,
        [string]$Tag,
        [string]$ArchiveName
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $MarkerPath -PathType Leaf)) {
        Write-WinWSBootstrapLog "Existing version directory '$Root' has no completion marker; reinstalling." 'WARN'
        return $false
    }

    try {
        $marker = Get-Content -LiteralPath $MarkerPath -Raw | ConvertFrom-Json
    } catch {
        Write-WinWSBootstrapLog "Existing version marker '$MarkerPath' is unreadable; reinstalling." 'WARN'
        return $false
    }

    if ((Get-WinWSObjectProperty -InputObject $marker -Name 'tag') -ne $Tag) {
        Write-WinWSBootstrapLog "Existing version marker does not match release '$Tag'; reinstalling." 'WARN'
        return $false
    }

    if ((Get-WinWSObjectProperty -InputObject $marker -Name 'archive') -ne $ArchiveName) {
        Write-WinWSBootstrapLog "Existing version marker does not match asset '$ArchiveName'; reinstalling." 'WARN'
        return $false
    }

    $uiScript = Get-WinWSObjectProperty -InputObject $marker -Name 'uiScript'
    if ([string]::IsNullOrWhiteSpace($uiScript) -or -not (Test-Path -LiteralPath $uiScript -PathType Leaf)) {
        Write-WinWSBootstrapLog "Existing version marker points to a missing UI script; reinstalling." 'WARN'
        return $false
    }

    foreach ($relativePath in @(
        'WinMint-CLI.ps1',
        'src\WinWS\WinWS.ps1',
        'src\WinWS.Agent\Start-WinWSAgent.ps1',
        'config\packages.json'
    )) {
        $requiredPath = Join-Path $Root $relativePath
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            Write-WinWSBootstrapLog "Existing version is missing '$relativePath'; reinstalling." 'WARN'
            return $false
        }
    }

    return $true
}

function Write-WinWSInstallMarker {
    param(
        [string]$MarkerPath,
        [string]$Tag,
        [string]$ArchiveName,
        [string]$UiScript
    )

    $marker = [pscustomobject][ordered]@{
        tag = $Tag
        archive = $ArchiveName
        uiScript = $UiScript
        completedAt = [DateTimeOffset]::Now.ToString('o')
    }

    $marker | ConvertTo-Json | Set-Content -LiteralPath $MarkerPath -Encoding UTF8
}

function Get-WinWSPowerShell {
    $pwsh = Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue
    if (-not $pwsh) {
        throw 'PowerShell 7.3+ is required. Install PowerShell 7, then run this launcher again.'
    }

    $versionText = & $pwsh.Source -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null |
        Select-Object -First 1
    try {
        $version = [version]([string]$versionText).Trim()
    }
    catch {
        throw "Could not determine PowerShell version from '$($pwsh.Source)'. Install PowerShell 7.3+, then run this launcher again."
    }
    if ($version -lt [version]'7.3') {
        throw "PowerShell 7.3+ is required. Found $version at '$($pwsh.Source)'. Update PowerShell, then run this launcher again."
    }

    return $pwsh.Source
}

Enable-WinWSBootstrapTls

if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    throw 'LOCALAPPDATA is not set. This launcher must run on Windows.'
}
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Join-Path $env:LOCALAPPDATA 'WinMint'
}

$launchMode = Resolve-WinWSLaunchMode -RequestedMode $Mode -UseGui:$Gui -UseHeadless:$Headless

$release = Get-WinWSRelease -Repo $Repository -RequestedVersion $Version
$tag = [string]$release.tag_name
$safeTag = $tag -replace '[^A-Za-z0-9._-]', '_'
$downloadRoot = Join-Path $InstallRoot 'downloads'
$versionRoot = Join-Path (Join-Path $InstallRoot 'versions') $safeTag
$installMarkerPath = Join-Path $versionRoot '.winmint-install-complete.json'
$archiveName = "WinMint-$tag.zip"
$archive = Select-WinWSAsset -Release $release -Extension '.zip' -PreferredName $archiveName
if (-not $archive) {
    throw "Release '$tag' does not include a WinMint zip asset."
}

$checksumName = "$($archive.name).sha256"
$checksum = Select-WinWSAsset -Release $release -Extension '.sha256' -PreferredName $checksumName
$archivePath = Join-Path $downloadRoot $archive.name
$checksumPath = if ($checksum) { Join-Path $downloadRoot $checksum.name } else { $null }

New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null

$uiScript = $null
$useInstalledVersion = (-not $Force) -and (Test-WinWSInstalledVersion `
    -Root $versionRoot `
    -MarkerPath $installMarkerPath `
    -Tag $tag `
    -ArchiveName $archive.name)

if ($useInstalledVersion) {
    Write-WinWSBootstrapLog "Using installed version '$tag' at '$versionRoot'."
} else {
    Save-WinWSAsset -Asset $archive -Destination $archivePath
    if ($checksum) {
        Save-WinWSAsset -Asset $checksum -Destination $checksumPath
        Test-WinWSArchiveHash -ArchivePath $archivePath -ChecksumPath $checksumPath
    } else {
        Write-WinWSBootstrapLog "No .sha256 asset found for '$($archive.name)'; hash verification skipped." 'WARN'
    }

    Write-WinWSBootstrapLog "Extracting to '$versionRoot'."
    Expand-WinWSRelease -ArchivePath $archivePath -Destination $versionRoot -Overwrite
    $uiScript = Find-WinWSUiScript -Root $versionRoot
    Write-WinWSInstallMarker -MarkerPath $installMarkerPath -Tag $tag -ArchiveName $archive.name -UiScript $uiScript
}

if (-not $uiScript) {
    $uiScript = Find-WinWSUiScript -Root $versionRoot
}
Write-WinWSBootstrapLog "Ready: $uiScript" 'OK'

if ($NoLaunch) {
    Write-WinWSBootstrapLog 'NoLaunch requested; not starting WinMint.'
    return
}

$pwshExe = Get-WinWSPowerShell
$entryScript = switch ($launchMode) {
    'Ui' { $uiScript }
    'Headless' { Find-WinWSCliScript -Root $versionRoot }
    'Gui' { Find-WinWSGuiScript -Root $versionRoot }
}
$arguments = New-WinWSLaunchArguments -ScriptPath $entryScript -LaunchMode $launchMode

Write-WinWSBootstrapLog "Starting WinMint $launchMode."
& $pwshExe @arguments
