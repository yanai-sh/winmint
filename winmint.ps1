#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Repository = 'yanai-sh/winmint',
    [string]$Version = 'latest',
    [string]$InstallRoot = '',
    [ValidateSet('Gui','Headless','LegacyUi')]
    [string]$Mode = 'Gui',
    [switch]$Gui,
    [switch]$Headless,
    [switch]$LegacyUi,
    [string]$ProfilePath = '',
    [string]$SourceIso = '',
    [string]$UupDumpSource = '',
    [string]$UupDumpZip = '',
    [string]$SourceIsoOverride = '',
    [ValidateSet('amd64','arm64','x86')]
    [string]$Architecture = '',
    [switch]$DryRun,
    [switch]$ExportHostDrivers,
    [switch]$NoServicedWimCache,
    [switch]$Developer,
    [switch]$Copilot,
    [switch]$DesktopUI,
    [switch]$Gaming,
    [ValidateSet('None','FlowEverything','Raycast')]
    [string]$Launcher = 'None',
    [switch]$LiveInstallAudit,
    [switch]$PhoneLink,
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

function Write-WinMintBootstrapLog {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','OK')]
        [string]$Level = 'INFO'
    )

    $stamp = Get-Date -Format 'HH:mm:ss.fff'
    Write-Host "[$stamp] [$Level] $Message"
}

function Enable-WinMintBootstrapTls {
    try {
        $tls12 = [Net.SecurityProtocolType]::Tls12
        if (-not ([Net.ServicePointManager]::SecurityProtocol -band $tls12)) {
            [Net.ServicePointManager]::SecurityProtocol =
                [Net.ServicePointManager]::SecurityProtocol -bor $tls12
        }
    } catch {
        Write-WinMintBootstrapLog "TLS setup warning: $($_.Exception.Message)" 'WARN'
    }
}

function Get-WinMintRelease {
    param([string]$Repo, [string]$RequestedVersion)

    $encodedVersion = [uri]::EscapeDataString($RequestedVersion)
    $releasePath = if ($RequestedVersion -eq 'latest') {
        "https://api.github.com/repos/$Repo/releases/latest"
    } else {
        "https://api.github.com/repos/$Repo/releases/tags/$encodedVersion"
    }

    Write-WinMintBootstrapLog "Querying GitHub release '$RequestedVersion' from $Repo."
    Invoke-RestMethod -Uri $releasePath -Headers @{
        'Accept' = 'application/vnd.github+json'
        'User-Agent' = 'WinMint-Bootstrap'
    } -UseBasicParsing
}

function Select-WinMintAsset {
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
        Where-Object { $_.name -like "*$Extension" -and $_.name -match '(?i)winmint|winmint|windows' } |
        Select-Object -First 1
    if ($matching) { return $matching }

    return $assets | Where-Object { $_.name -like "*$Extension" } | Select-Object -First 1
}

function Save-WinMintAsset {
    param(
        [Parameter(Mandatory)]$Asset,
        [string]$Destination
    )

    Write-WinMintBootstrapLog "Downloading $($Asset.name)."
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $Destination -Headers @{
        'User-Agent' = 'WinMint-Bootstrap'
    } -UseBasicParsing
}

function Get-WinMintFileSha256 {
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

function Test-WinMintArchiveHash {
    param([string]$ArchivePath, [string]$ChecksumPath)

    $text = Get-Content -LiteralPath $ChecksumPath -Raw
    $match = [regex]::Match($text, '(?i)\b[a-f0-9]{64}\b')
    if (-not $match.Success) {
        throw "Checksum file '$ChecksumPath' does not contain a SHA256 hash."
    }

    $expected = $match.Value.ToUpperInvariant()
    $actual = Get-WinMintFileSha256 -Path $ArchivePath
    if ($actual -ne $expected) {
        throw "Archive SHA256 mismatch. Expected $expected, got $actual."
    }

    Write-WinMintBootstrapLog "Verified SHA256 $actual." 'OK'
}

function Expand-WinMintRelease {
    param([string]$ArchivePath, [string]$Destination, [switch]$Overwrite)

    if ((Test-Path -LiteralPath $Destination) -and $Overwrite) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $Destination -Force
}

function Find-WinMintLegacyUiScript {
    param([string]$Root)

    $candidate = Join-Path $Root 'WinMint-LegacyUI.ps1'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return $candidate
    }

    throw "WinMint-LegacyUI.ps1 was not found under '$Root'."
}

function Find-WinMintCliScript {
    param([string]$Root)

    $script = Get-ChildItem -LiteralPath $Root -Filter 'WinMint-CLI.ps1' -Recurse -File |
        Select-Object -First 1
    if (-not $script) {
        throw "WinMint-CLI.ps1 was not found under '$Root'."
    }

    return $script.FullName
}

function Find-WinMintGuiScript {
    param([string]$Root)

    $candidate = Join-Path $Root 'WinMint-GUI.ps1'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return $candidate
    }

    throw "WinMint-GUI.ps1 was not found under '$Root'. This release is missing the packaged GPUI launcher."
}

function Resolve-WinMintLaunchMode {
    param(
        [string]$RequestedMode,
        [switch]$UseGui,
        [switch]$UseHeadless,
        [switch]$UseLegacyUi
    )

    $explicitModes = @($UseGui, $UseHeadless, $UseLegacyUi) | Where-Object { $_ }
    if ($explicitModes.Count -gt 1) {
        throw 'Use only one of -Gui, -Headless, or -LegacyUi.'
    }
    if ($UseGui -and $RequestedMode -ne 'Gui') {
        throw 'Use either -Mode or -Gui, not both.'
    }
    if ($UseHeadless -and $RequestedMode -ne 'Gui') {
        throw 'Use either -Mode or -Headless, not both.'
    }
    if ($UseLegacyUi -and $RequestedMode -ne 'Gui') {
        throw 'Use either -Mode or -LegacyUi, not both.'
    }
    if ($UseGui) { return 'Gui' }
    if ($UseHeadless) { return 'Headless' }
    if ($UseLegacyUi) { return 'LegacyUi' }
    return $RequestedMode
}

function Add-WinMintArgumentValue {
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

function New-WinMintLaunchArguments {
    param(
        [string]$ScriptPath,
        [string]$LaunchMode
    )

    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($value in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)) {
        $arguments.Add($value)
    }

    if ($LaunchMode -eq 'Headless') {
        Add-WinMintArgumentValue -Arguments $arguments -Name 'ProfilePath' -Value $ProfilePath
        Add-WinMintArgumentValue -Arguments $arguments -Name 'SourceIso' -Value $SourceIso
        Add-WinMintArgumentValue -Arguments $arguments -Name 'UupDumpSource' -Value $UupDumpSource
        Add-WinMintArgumentValue -Arguments $arguments -Name 'UupDumpZip' -Value $UupDumpZip
        Add-WinMintArgumentValue -Arguments $arguments -Name 'SourceIsoOverride' -Value $SourceIsoOverride
        Add-WinMintArgumentValue -Arguments $arguments -Name 'Architecture' -Value $Architecture
        if ($Developer) { $arguments.Add('-Developer') }
        if ($Copilot) { $arguments.Add('-Copilot') }
        if ($DesktopUI) { $arguments.Add('-DesktopUI') }
        if ($Gaming) { $arguments.Add('-Gaming') }
        if ($Launcher -ne 'None') {
            $arguments.Add('-Launcher')
            $arguments.Add($Launcher)
        }
        if ($LiveInstallAudit) { $arguments.Add('-LiveInstallAudit') }
        if ($PhoneLink) { $arguments.Add('-PhoneLink') }
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
    if ($NoServicedWimCache -and $LaunchMode -ne 'Gui') { $arguments.Add('-NoServicedWimCache') }
    return $arguments.ToArray()
}

function Get-WinMintObjectProperty {
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

function Test-WinMintInstalledVersion {
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
        Write-WinMintBootstrapLog "Existing version directory '$Root' has no completion marker; reinstalling." 'WARN'
        return $false
    }

    try {
        $marker = Get-Content -LiteralPath $MarkerPath -Raw | ConvertFrom-Json
    } catch {
        Write-WinMintBootstrapLog "Existing version marker '$MarkerPath' is unreadable; reinstalling." 'WARN'
        return $false
    }

    if ((Get-WinMintObjectProperty -InputObject $marker -Name 'tag') -ne $Tag) {
        Write-WinMintBootstrapLog "Existing version marker does not match release '$Tag'; reinstalling." 'WARN'
        return $false
    }

    if ((Get-WinMintObjectProperty -InputObject $marker -Name 'archive') -ne $ArchiveName) {
        Write-WinMintBootstrapLog "Existing version marker does not match asset '$ArchiveName'; reinstalling." 'WARN'
        return $false
    }

    $guiScript = Get-WinMintObjectProperty -InputObject $marker -Name 'guiScript'
    if ([string]::IsNullOrWhiteSpace($guiScript) -or -not (Test-Path -LiteralPath $guiScript -PathType Leaf)) {
        Write-WinMintBootstrapLog "Existing version marker points to a missing GPUI script; reinstalling." 'WARN'
        return $false
    }

    foreach ($relativePath in @(
        'WinMint-CLI.ps1',
        'WinMint-GUI.ps1',
        'WinMint-LegacyUI.ps1',
        'apps\gui\bin\WinMint-GUI.exe',
        'apps\legacy-wpf\Views\MainWindow.xaml',
        'src\engine\WinMint.ps1',
        'src\agent\Start-WinMintAgent.ps1',
        'config\packages.json'
    )) {
        $requiredPath = Join-Path $Root $relativePath
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            Write-WinMintBootstrapLog "Existing version is missing '$relativePath'; reinstalling." 'WARN'
            return $false
        }
    }

    return $true
}

function Write-WinMintInstallMarker {
    param(
        [string]$MarkerPath,
        [string]$Tag,
        [string]$ArchiveName,
        [string]$GuiScript
    )

    $marker = [pscustomobject][ordered]@{
        tag = $Tag
        archive = $ArchiveName
        guiScript = $GuiScript
        completedAt = [DateTimeOffset]::Now.ToString('o')
    }

    $marker | ConvertTo-Json | Set-Content -LiteralPath $MarkerPath -Encoding UTF8
}

function Get-WinMintPowerShell {
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

Enable-WinMintBootstrapTls

if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    throw 'LOCALAPPDATA is not set. This launcher must run on Windows.'
}
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Join-Path $env:LOCALAPPDATA 'WinMint'
}

$launchMode = Resolve-WinMintLaunchMode -RequestedMode $Mode -UseGui:$Gui -UseHeadless:$Headless -UseLegacyUi:$LegacyUi

$release = Get-WinMintRelease -Repo $Repository -RequestedVersion $Version
$tag = [string]$release.tag_name
$safeTag = $tag -replace '[^A-Za-z0-9._-]', '_'
$downloadRoot = Join-Path $InstallRoot 'downloads'
$versionRoot = Join-Path (Join-Path $InstallRoot 'versions') $safeTag
$installMarkerPath = Join-Path $versionRoot '.winmint-install-complete.json'
$archiveName = "WinMint-$tag.zip"
$archive = Select-WinMintAsset -Release $release -Extension '.zip' -PreferredName $archiveName
if (-not $archive) {
    throw "Release '$tag' does not include a WinMint zip asset."
}

$checksumName = "$($archive.name).sha256"
$checksum = Select-WinMintAsset -Release $release -Extension '.sha256' -PreferredName $checksumName
$archivePath = Join-Path $downloadRoot $archive.name
$checksumPath = if ($checksum) { Join-Path $downloadRoot $checksum.name } else { $null }

New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null

$guiScript = $null
$useInstalledVersion = (-not $Force) -and (Test-WinMintInstalledVersion `
    -Root $versionRoot `
    -MarkerPath $installMarkerPath `
    -Tag $tag `
    -ArchiveName $archive.name)

if ($useInstalledVersion) {
    Write-WinMintBootstrapLog "Using installed version '$tag' at '$versionRoot'."
} else {
    Save-WinMintAsset -Asset $archive -Destination $archivePath
    if ($checksum) {
        Save-WinMintAsset -Asset $checksum -Destination $checksumPath
        Test-WinMintArchiveHash -ArchivePath $archivePath -ChecksumPath $checksumPath
    } else {
        Write-WinMintBootstrapLog "No .sha256 asset found for '$($archive.name)'; hash verification skipped." 'WARN'
    }

    Write-WinMintBootstrapLog "Extracting to '$versionRoot'."
    Expand-WinMintRelease -ArchivePath $archivePath -Destination $versionRoot -Overwrite
    $guiScript = Find-WinMintGuiScript -Root $versionRoot
    Write-WinMintInstallMarker -MarkerPath $installMarkerPath -Tag $tag -ArchiveName $archive.name -GuiScript $guiScript
}

if (-not $guiScript) {
    $guiScript = Find-WinMintGuiScript -Root $versionRoot
}
Write-WinMintBootstrapLog "Ready: $guiScript" 'OK'

if ($NoLaunch) {
    Write-WinMintBootstrapLog 'NoLaunch requested; not starting WinMint.'
    return
}

$pwshExe = Get-WinMintPowerShell
$entryScript = switch ($launchMode) {
    'Gui' { $guiScript }
    'Headless' { Find-WinMintCliScript -Root $versionRoot }
    'LegacyUi' { Find-WinMintLegacyUiScript -Root $versionRoot }
}
$arguments = New-WinMintLaunchArguments -ScriptPath $entryScript -LaunchMode $launchMode

Write-WinMintBootstrapLog "Starting WinMint $launchMode."
& $pwshExe @arguments
