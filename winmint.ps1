#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Repository = 'yanai-sh/winmint',
    [string]$Version = 'latest',
    [string]$ReleaseApiRoot = 'https://api.github.com',
    [string]$InstallRoot = '',
    [switch]$CacheRelease,
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

$script:WinMintBootstrapOperation = 'Starting WinMint bootstrap.'
$script:WinMintBootstrapFailureKind = 'Unexpected'
$script:WinMintBootstrapRecovery = 'Retry the command. If it fails again, inspect the error text above and report the bootstrap log.'
$script:WinMintBootstrapRetrySafe = $true

function Set-WinMintBootstrapOperation {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [ValidateSet('Network','Integrity','Package','Runtime','Elevation','Relaunch','Usage','Unexpected')]
        [string]$FailureKind = 'Unexpected',
        [string]$Recovery = 'Retry the command. If it fails again, inspect the error text above and report the bootstrap log.',
        [bool]$RetrySafe = $true
    )

    $script:WinMintBootstrapOperation = $Operation
    $script:WinMintBootstrapFailureKind = $FailureKind
    $script:WinMintBootstrapRecovery = $Recovery
    $script:WinMintBootstrapRetrySafe = $RetrySafe
}

function Write-WinMintBootstrapFailure {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

    $message = [string]$ErrorRecord.Exception.Message
    $retryText = if ($script:WinMintBootstrapRetrySafe) {
        'Safe to retry: yes. A retry starts from a fresh temporary session unless -InstallRoot or -CacheRelease was used.'
    }
    else {
        'Safe to retry: no, not until the release asset or local input is corrected.'
    }

    Write-WinMintBootstrapLog "Bootstrap failed during: $script:WinMintBootstrapOperation" 'ERROR'
    Write-WinMintBootstrapLog "Failure kind: $script:WinMintBootstrapFailureKind" 'ERROR'
    Write-WinMintBootstrapLog "Reason: $message" 'ERROR'
    Write-WinMintBootstrapLog "Recovery: $script:WinMintBootstrapRecovery" 'ERROR'
    Write-WinMintBootstrapLog $retryText 'ERROR'
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
    param(
        [string]$Repo,
        [string]$RequestedVersion,
        [string]$ApiRoot
    )

    $encodedVersion = [uri]::EscapeDataString($RequestedVersion)
    $apiBase = $ApiRoot.TrimEnd('/')
    $releasePath = if ($RequestedVersion -eq 'latest') {
        "$apiBase/repos/$Repo/releases/latest"
    } else {
        "$apiBase/repos/$Repo/releases/tags/$encodedVersion"
    }

    Set-WinMintBootstrapOperation `
        -Operation "Querying release metadata for '$RequestedVersion' from $Repo." `
        -FailureKind 'Network' `
        -Recovery 'Check network access to GitHub or the configured release API root, then retry. If using the short URL, verify Cloudflare is not challenging command-line clients.'
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

    Set-WinMintBootstrapOperation `
        -Operation "Downloading release asset '$($Asset.name)'." `
        -FailureKind 'Network' `
        -Recovery 'Check network access, proxy/VPN/firewall policy, and GitHub release asset availability, then retry.'
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

    Set-WinMintBootstrapOperation `
        -Operation 'Verifying release archive SHA256.' `
        -FailureKind 'Integrity' `
        -Recovery 'Do not run this release asset. Wait for the release zip and .sha256 assets to be corrected, then retry.' `
        -RetrySafe $false

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

function Resolve-WinMintBootstrapReleasePayload {
    param(
        [Parameter(Mandatory)]$Release,
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$DownloadRoot
    )

    $archiveName = "WinMint-$tag.zip"
    Set-WinMintBootstrapOperation `
        -Operation "Resolving release assets for '$Tag'." `
        -FailureKind 'Package' `
        -Recovery 'The selected GitHub release is incomplete. Use another version or wait for the release assets to be republished.' `
        -RetrySafe $false
    $archive = Select-WinMintAsset -Release $Release -Extension '.zip' -PreferredName $archiveName
    if (-not $archive) {
        throw "Release '$Tag' does not include a WinMint zip asset."
    }

    $checksumName = "$($archive.name).sha256"
    $checksum = @($Release.assets | Where-Object { $_.name -eq $checksumName } | Select-Object -First 1)
    if (-not $checksum) {
        throw "Release '$Tag' is missing required checksum asset '$checksumName'. Refusing to install without release integrity verification."
    }

    [pscustomobject]@{
        Archive = $archive
        Checksum = $checksum
        ArchivePath = Join-Path $DownloadRoot $archive.name
        ChecksumPath = Join-Path $DownloadRoot $checksum.name
        SourceUrl = [string]$archive.browser_download_url
        Version = $Tag
    }
}

function Save-WinMintBootstrapReleasePayload {
    param([Parameter(Mandatory)]$Payload)

    $archivePath = [string]$Payload.ArchivePath
    $checksumPath = [string]$Payload.ChecksumPath
    Save-WinMintAsset -Asset $Payload.Archive -Destination $archivePath
    Save-WinMintAsset -Asset $Payload.Checksum -Destination $checksumPath
    Test-WinMintArchiveHash -ArchivePath $archivePath -ChecksumPath $checksumPath
}

function Expand-WinMintRelease {
    param([string]$ArchivePath, [string]$Destination, [switch]$Overwrite)

    Set-WinMintBootstrapOperation `
        -Operation "Extracting release archive to '$Destination'." `
        -FailureKind 'Package' `
        -Recovery 'The archive may be corrupt or locked by local security software. Retry after verifying the release hash and available disk space.'

    if ((Test-Path -LiteralPath $Destination) -and $Overwrite) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $Destination -Force
}

function New-WinMintBootstrapSessionRoot {
    param([string]$Tag)

    $safeTag = $Tag -replace '[^A-Za-z0-9._-]', '_'
    $name = "WinMintBootstrap-$safeTag-$([guid]::NewGuid().ToString('N'))"
    return Join-Path ([IO.Path]::GetTempPath()) $name
}

function Remove-WinMintBootstrapSessionRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        Write-WinMintBootstrapLog "Removed temporary session '$Path'." 'OK'
    }
    catch {
        Write-WinMintBootstrapLog "Could not remove temporary session '$Path': $($_.Exception.Message)" 'WARN'
    }
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

    $explicitModes = @(@($UseGui, $UseHeadless) | Where-Object { $_ })
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

    Set-WinMintBootstrapOperation `
        -Operation "Launching packaged GUI with elevation: '$FilePath'." `
        -FailureKind 'Elevation' `
        -Recovery 'Approve the Windows elevation prompt. If it was cancelled, rerun the bootstrap command.'
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
    function Get-WinMintPowerShellCandidate {
        Set-WinMintBootstrapOperation `
            -Operation 'Locating PowerShell 7.6.2 or newer.' `
            -FailureKind 'Runtime' `
            -Recovery 'Install or update PowerShell 7.6.2+, then rerun the bootstrap command.'
        $pwsh = Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue
        if (-not $pwsh) { return $null }

        $versionText = & $pwsh.Source -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null |
            Select-Object -First 1
        try {
            return [pscustomobject]@{
                Path = $pwsh.Source
                Version = [version]([string]$versionText).Trim()
            }
        }
        catch {
            throw "Could not determine PowerShell version from '$($pwsh.Source)'. Install PowerShell 7.6.2+, then run this launcher again."
        }
    }

    function Install-WinMintBootstrapPowerShell {
        Set-WinMintBootstrapOperation `
            -Operation 'Installing PowerShell 7.6.2+ through WinGet.' `
            -FailureKind 'Runtime' `
            -Recovery 'Install PowerShell 7.6.2+ manually from Microsoft or fix WinGet availability, then rerun the bootstrap command.'
        $winget = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
        if (-not $winget) {
            throw 'PowerShell 7.6.2+ is required, and WinGet was not available for automatic installation.'
        }

        Write-WinMintBootstrapLog 'Installing PowerShell 7.6.2+ via WinGet.'
        & $winget.Source install `
            --id Microsoft.PowerShell `
            --source winget `
            --accept-package-agreements `
            --accept-source-agreements `
            --disable-interactivity `
            --silent | Out-Null
    }

    $minimumVersion = [version]'7.6.2'
    $candidate = Get-WinMintPowerShellCandidate
    if (-not $candidate -or $candidate.Version -lt $minimumVersion) {
        Install-WinMintBootstrapPowerShell
        $candidate = Get-WinMintPowerShellCandidate
    }
    if (-not $candidate -or $candidate.Version -lt $minimumVersion) {
        $foundVersion = if ($candidate) { $candidate.Version } else { 'none' }
        $foundPath = if ($candidate) { $candidate.Path } else { 'pwsh.exe not found' }
        throw "PowerShell 7.6.2+ is required. Found $foundVersion at '$foundPath'. Update PowerShell, then run this launcher again."
    }

    Write-WinMintBootstrapLog "Using PowerShell $($candidate.Version) at '$($candidate.Path)'."
    return $candidate.Path
}

Enable-WinMintBootstrapTls

$sessionRoot = ''
$createdEphemeralSession = $false
$scriptExitCode = 0

try {
    Set-WinMintBootstrapOperation `
        -Operation 'Resolving launch mode and cache policy.' `
        -FailureKind 'Usage' `
        -Recovery 'Use only one launch mode, and use -InstallRoot or -CacheRelease only when a durable release cache is intentional.'
    $useDurableReleaseCache = $CacheRelease -or (-not [string]::IsNullOrWhiteSpace($InstallRoot))
    if ($useDurableReleaseCache -and [string]::IsNullOrWhiteSpace($InstallRoot)) {
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            throw 'LOCALAPPDATA is not set. Pass -InstallRoot or run on Windows.'
        }
        $InstallRoot = Join-Path $env:LOCALAPPDATA 'WinMint'
    }

    $launchMode = Resolve-WinMintLaunchMode -RequestedMode $Mode -UseGui:$Gui -UseHeadless:$Headless

    $release = Get-WinMintRelease -Repo $Repository -RequestedVersion $Version -ApiRoot $ReleaseApiRoot
    $tag = [string]$release.tag_name
    $safeTag = $tag -replace '[^A-Za-z0-9._-]', '_'
    $downloadRoot = ''
    $versionRoot = ''
    $installMarkerPath = ''

    if ($useDurableReleaseCache) {
        $downloadRoot = Join-Path $InstallRoot 'downloads'
        $versionRoot = Join-Path (Join-Path $InstallRoot 'versions') $safeTag
        $installMarkerPath = Join-Path $versionRoot '.winmint-install-complete.json'
        Write-WinMintBootstrapLog "Using explicit release cache root '$InstallRoot'."
    }
    else {
        $sessionRoot = New-WinMintBootstrapSessionRoot -Tag $tag
        $downloadRoot = Join-Path $sessionRoot 'downloads'
        $versionRoot = Join-Path $sessionRoot 'release'
        $createdEphemeralSession = $true
        Write-WinMintBootstrapLog "Using temporary session '$sessionRoot'."
    }

    $releasePayload = Resolve-WinMintBootstrapReleasePayload -Release $release -Tag $tag -DownloadRoot $downloadRoot
    $archive = $releasePayload.Archive
    $archivePath = [string]$releasePayload.ArchivePath

    New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null

    $guiScript = $null
    $useInstalledVersion = $false
    if ($useDurableReleaseCache) {
        $useInstalledVersion = (-not $Force) -and (Test-WinMintInstalledVersion `
            -Root $versionRoot `
            -MarkerPath $installMarkerPath `
            -Tag $tag `
            -ArchiveName $archive.name)
    }

    if ($useInstalledVersion) {
        Write-WinMintBootstrapLog "Using cached version '$tag' at '$versionRoot'."
    }
    else {
        Save-WinMintBootstrapReleasePayload -Payload $releasePayload

        Write-WinMintBootstrapLog "Extracting to '$versionRoot'."
        Expand-WinMintRelease -ArchivePath $archivePath -Destination $versionRoot -Overwrite
        $guiScript = Find-WinMintGuiScript -Root $versionRoot
        if ($useDurableReleaseCache) {
            Write-WinMintInstallMarker -MarkerPath $installMarkerPath -Tag $tag -ArchiveName $archive.name -GuiScript $guiScript
        }
    }

    if (-not $guiScript) {
        $guiScript = Find-WinMintGuiScript -Root $versionRoot
    }
    Write-WinMintBootstrapLog "Ready: $guiScript" 'OK'
    Write-WinMintBootstrapLog 'Retry behavior: rerunning the bootstrap is safe; the default path starts from a fresh temporary session.' 'INFO'

    if ($NoLaunch) {
        Write-WinMintBootstrapLog 'NoLaunch requested; not starting WinMint.'
    }
    else {
        $pwshExe = Get-WinMintPowerShell

        Write-WinMintBootstrapLog "Starting WinMint $launchMode."
        if ($launchMode -eq 'Gui') {
            $guiExe = Find-WinMintGuiExecutable -Root $versionRoot
            $guiArguments = New-WinMintGuiExecutableArguments
            $scriptExitCode = Start-WinMintElevatedGui -FilePath $guiExe -ArgumentList $guiArguments
            if ($scriptExitCode -ne 0) {
                Set-WinMintBootstrapOperation `
                    -Operation "Waiting for packaged GUI process '$guiExe'." `
                    -FailureKind 'Relaunch' `
                    -Recovery 'Review any GUI error message, then rerun the bootstrap command. If the process exited before the wizard opened, verify the release bundle and host requirements.'
                throw "Packaged GUI exited with code $scriptExitCode."
            }
        }
        else {
            $entryScript = Find-WinMintCliScript -Root $versionRoot
            $arguments = New-WinMintLaunchArguments -ScriptPath $entryScript -LaunchMode $launchMode
            Set-WinMintBootstrapOperation `
                -Operation "Handing off to packaged CLI through PowerShell: '$entryScript'." `
                -FailureKind 'Relaunch' `
                -Recovery 'Review the CLI error output, fix the profile or run-specific arguments, then rerun the bootstrap command.'
            & $pwshExe @arguments
            $scriptExitCode = if ($LASTEXITCODE -ne $null) { [int]$LASTEXITCODE } else { 0 }
            if ($scriptExitCode -ne 0) {
                throw "Packaged CLI exited with code $scriptExitCode."
            }
        }
    }
}
catch {
    Write-WinMintBootstrapFailure -ErrorRecord $_
    $scriptExitCode = 1
}
finally {
    if ($createdEphemeralSession) {
        Remove-WinMintBootstrapSessionRoot -Path $sessionRoot
    }
}

if ($scriptExitCode -ne 0) {
    exit $scriptExitCode
}
