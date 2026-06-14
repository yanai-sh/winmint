#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Repository = 'yanai-sh/winmint',
    [string]$Version = 'latest',
    [string]$InstallRoot = '',
    [ValidateSet('Gui','Headless')]
    [string]$Mode = 'Gui',
    [switch]$Gui,
    [switch]$Headless,
    # Headless launch runs a profile-backed build (or -ValidateOnly). Profile
    # authoring lives in the GUI or `WinMint-CLI.ps1 new`, not on this launcher.
    [string]$ProfilePath = '',
    [string]$SourceIso = '',
    [switch]$DryRun,
    [switch]$ValidateOnly,
    [switch]$Json,
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

function Find-WinMintGuiExecutable {
    param([string]$Root)

    $candidate = Join-Path $Root 'apps\gui\bin\WinMint-GUI.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return $candidate
    }

    throw "WinMint-GUI.exe was not found under '$Root'. This release is missing the packaged GPUI binary."
}

function Resolve-WinMintLaunchMode {
    param(
        [string]$RequestedMode,
        [switch]$UseGui,
        [switch]$UseHeadless
    )

    $explicitModes = @($UseGui, $UseHeadless) | Where-Object { $_ }
    if ($explicitModes.Count -gt 1) {
        throw 'Use only one of -Gui or -Headless.'
    }
    if ($UseGui -and $RequestedMode -ne 'Gui') {
        throw 'Use either -Mode or -Gui, not both.'
    }
    if ($UseHeadless -and $RequestedMode -ne 'Gui') {
        throw 'Use either -Mode or -Headless, not both.'
    }
    if ($UseGui) { return 'Gui' }
    if ($UseHeadless) { return 'Headless' }
    return $RequestedMode
}

function ConvertTo-WinMintBootstrapQuotedArgument {
    param([Parameter(Mandatory)][string]$Value)

    '"' + ($Value -replace '"', '\"') + '"'
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

function New-WinMintGuiExecutableArguments {
    $arguments = [System.Collections.Generic.List[string]]::new()
    if ($DryRun) { $arguments.Add('--dry-run') }
    return $arguments.ToArray()
}

function Start-WinMintElevatedGui {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    $startArgs = @{
        FilePath = $FilePath
        Verb = 'RunAs'
        Wait = $true
        PassThru = $true
    }
    if ($ArgumentList.Count -gt 0) {
        $startArgs.ArgumentList = (($ArgumentList | ForEach-Object {
            ConvertTo-WinMintBootstrapQuotedArgument -Value ([string]$_)
        }) -join ' ')
    }

    $process = Start-Process @startArgs
    return $process.ExitCode
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
        # Profile is the source of truth: dispatch the build (or validate) verb
        # with only run-specific overrides.
        $verb = if ($ValidateOnly) { 'validate' } else { 'build' }
        $arguments.Add($verb)
        if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) {
            $arguments.Add($ProfilePath)
        }
        Add-WinMintArgumentValue -Arguments $arguments -Name 'SourceIso' -Value $SourceIso
        if ($DryRun -and -not $ValidateOnly) { $arguments.Add('-DryRun') }
        if ($Json) { $arguments.Add('-Json') }
        if ($Quiet) { $arguments.Add('-Quiet') }
        if ($AllowElevate) { $arguments.Add('-AllowElevate') }
        if ($Yes) { $arguments.Add('-Yes') }
    }

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
        'apps\gui\bin\WinMint-GUI.exe',
        'src\runtime\image\WinMint.ps1',
        'src\runtime\firstlogon\Start-WinMintAgent.ps1',
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

$launchMode = Resolve-WinMintLaunchMode -RequestedMode $Mode -UseGui:$Gui -UseHeadless:$Headless

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
$checksum = @($release.assets | Where-Object { $_.name -eq $checksumName } | Select-Object -First 1)
if (-not $checksum) {
    throw "Release '$tag' is missing required checksum asset '$checksumName'. Refusing to install without release integrity verification."
}
$archivePath = Join-Path $downloadRoot $archive.name
$checksumPath = Join-Path $downloadRoot $checksum.name

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
    Save-WinMintAsset -Asset $checksum -Destination $checksumPath
    Test-WinMintArchiveHash -ArchivePath $archivePath -ChecksumPath $checksumPath

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

Write-WinMintBootstrapLog "Starting WinMint $launchMode."
if ($launchMode -eq 'Gui') {
    $guiExe = Find-WinMintGuiExecutable -Root $versionRoot
    $guiArguments = New-WinMintGuiExecutableArguments
    $exitCode = Start-WinMintElevatedGui -FilePath $guiExe -ArgumentList $guiArguments
    if ($exitCode -ne 0) {
        exit $exitCode
    }
    return
}

$entryScript = Find-WinMintCliScript -Root $versionRoot
$arguments = New-WinMintLaunchArguments -ScriptPath $entryScript -LaunchMode $launchMode
& $pwshExe @arguments
