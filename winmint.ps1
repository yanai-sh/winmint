#Requires -Version 5.1
# WinMint no-clone bootstrap: download verified toolkit zip, launch Wizard (default) or Cli (-Headless).
[CmdletBinding()]
param(
    [string]$Repository = 'yanai-sh/winmint',
    [string]$Version = 'latest',
    [string]$ReleaseApiRoot = 'https://api.github.com',
    [string]$InstallRoot = '',
    [switch]$CacheRelease,
    [ValidateSet('Gui', 'Headless')]
    [string]$Mode = 'Gui',
    [switch]$Gui,
    [switch]$Headless,
    [string]$ProfilePath = '',
    [string]$SourceIso = '',
    [string]$Work = '',
    [switch]$ValidateOnly,
    # Gate B wipe ISO: Release + --package-strict (same bar as just primary-gate).
    [switch]$PrimaryGate,
    [switch]$NoLaunch,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Write-WinMintBootstrapLog {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR', 'OK')][string]$Level = 'INFO')
    $stamp = Get-Date -Format 'HH:mm:ss.fff'
    Write-Host "[$stamp] [$Level] $Message"
}

$script:WinMintBootstrapOperation = 'Starting WinMint bootstrap.'
$script:WinMintBootstrapFailureKind = 'Unexpected'
$script:WinMintBootstrapRecovery = 'Retry the command. If it fails again, inspect the error text above.'
$script:WinMintBootstrapRetrySafe = $true

function Set-WinMintBootstrapOperation {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [ValidateSet('Network', 'Integrity', 'Package', 'Runtime', 'Elevation', 'Relaunch', 'Usage', 'Unexpected')]
        [string]$FailureKind = 'Unexpected',
        [string]$Recovery = 'Retry the command.',
        [bool]$RetrySafe = $true
    )
    $script:WinMintBootstrapOperation = $Operation
    $script:WinMintBootstrapFailureKind = $FailureKind
    $script:WinMintBootstrapRecovery = $Recovery
    $script:WinMintBootstrapRetrySafe = $RetrySafe
}

function Write-WinMintBootstrapFailure {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)
    $retryText = if ($script:WinMintBootstrapRetrySafe) {
        'Safe to retry: yes. A retry starts from a fresh temporary session unless -InstallRoot or -CacheRelease was used.'
    }
    else {
        'Safe to retry: no, not until the release asset or local input is corrected.'
    }
    Write-WinMintBootstrapLog "Bootstrap failed during: $script:WinMintBootstrapOperation" 'ERROR'
    Write-WinMintBootstrapLog "Failure kind: $script:WinMintBootstrapFailureKind" 'ERROR'
    Write-WinMintBootstrapLog "Reason: $($ErrorRecord.Exception.Message)" 'ERROR'
    Write-WinMintBootstrapLog "Recovery: $script:WinMintBootstrapRecovery" 'ERROR'
    Write-WinMintBootstrapLog $retryText 'ERROR'
}

try {
    $sessionRoot = $null
    try {
        $tls12 = [Net.SecurityProtocolType]::Tls12
        if (-not ([Net.ServicePointManager]::SecurityProtocol -band $tls12)) {
            [Net.ServicePointManager]::SecurityProtocol =
                [Net.ServicePointManager]::SecurityProtocol -bor $tls12
        }
    }
    catch {
        Write-WinMintBootstrapLog "TLS setup warning: $($_.Exception.Message)" 'WARN'
    }

    $explicit = @($Gui, $Headless) | Where-Object { $_ }
    if (@($explicit).Count -gt 1) { throw 'Use only one of -Gui or -Headless.' }
    if ($Gui) { $Mode = 'Gui' }
    if ($Headless) { $Mode = 'Headless' }

    function Test-WinMintPwshVersion {
        $v = $PSVersionTable.PSVersion
        return ($v.Major -gt 7) -or ($v.Major -eq 7 -and $v.Minor -ge 6)
    }

    function Get-WinMintHostPwshMsiRid {
        # W6432 is the native host when this process is emulated (not PROCESSOR_ARCHITECTURE alone).
        $wow = $env:PROCESSOR_ARCHITEW6432
        $pa = $env:PROCESSOR_ARCHITECTURE
        if ($wow -eq 'ARM64' -or $pa -eq 'ARM64') { return 'win-arm64' }
        if ($wow -eq 'AMD64' -or $pa -eq 'AMD64') { return 'win-x64' }
        throw ('Unsupported host architecture for GitHub pwsh MSI (PROCESSOR_ARCHITECTURE={0} PROCESSOR_ARCHITEW6432={1}).' -f $pa, $wow)
    }

    function Test-WinMintServicingPwsh {
        Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')
    }

    function Install-WinMintServicingPwsh {
        $rid = Get-WinMintHostPwshMsiRid
        $msiName = 'PowerShell-*-{0}.msi' -f $rid
        Set-WinMintBootstrapOperation -Operation 'Installing GitHub pwsh MSI.' -FailureKind 'Runtime' -Recovery 'Download PowerShell-*-win-arm64.msi (or win-x64) from https://github.com/PowerShell/PowerShell/releases/latest. winget Microsoft.PowerShell is MSIX and cannot run DISM. msiexec, then retry from Program Files\PowerShell\7\pwsh.exe.'
        Write-WinMintBootstrapLog 'winget Microsoft.PowerShell is MSIX; DISM needs the GitHub MSI.'
        $apiBase = $ReleaseApiRoot.TrimEnd('/')
        $psUri = $apiBase + '/repos/PowerShell/PowerShell/releases/latest'
        $psRelease = Invoke-RestMethod -Uri $psUri -Headers @{
            'Accept'     = 'application/vnd.github+json'
            'User-Agent' = 'WinMint-Bootstrap'
        }
        $asset = @($psRelease.assets) | Where-Object { $_.name -like $msiName } | Select-Object -First 1
        if (-not $asset) {
            throw ('GitHub PowerShell release {0} has no {1}.' -f $psRelease.tag_name, $msiName)
        }
        $msiPath = Join-Path $env:TEMP $asset.name
        Write-WinMintBootstrapLog ('Downloading {0}.' -f $asset.name)
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msiPath -Headers @{ 'User-Agent' = 'WinMint-Bootstrap' } -UseBasicParsing
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $msiPath, '/qn', 'ADD_PATH=1') -Wait -PassThru
        if ($p.ExitCode -ne 0) {
            throw ('msiexec exited {0} installing {1}.' -f $p.ExitCode, $asset.name)
        }
        if (-not (Test-WinMintServicingPwsh)) {
            throw 'GitHub pwsh MSI installed but Program Files\PowerShell\7\pwsh.exe is missing.'
        }
        Write-WinMintBootstrapLog 'Installed servicing pwsh under Program Files\PowerShell\7.' 'OK'
    }

    if (-not (Test-WinMintServicingPwsh)) {
        Install-WinMintServicingPwsh
    }

    if (-not (Test-WinMintPwshVersion)) {
        Set-WinMintBootstrapOperation -Operation 'Ensuring PowerShell 7.6+.' -FailureKind 'Runtime' -Recovery 'Relaunch irm https://winmint.yanai.sh | iex from Program Files\PowerShell\7\pwsh.exe (GitHub MSI, not winget MSIX).'
        throw 'Relaunch this command from pwsh 7.6+ after the PowerShell MSI install finishes.'
    }

    function Test-WinMintJust {
        return [bool](Get-Command just -ErrorAction SilentlyContinue)
    }

    if (-not (Test-WinMintJust)) {
        Set-WinMintBootstrapOperation -Operation 'Ensuring Just.' -FailureKind 'Runtime' `
            -Recovery 'Install Just (winget install Casey.Just), then retry.'
        Write-WinMintBootstrapLog 'Installing Just via WinGet (Casey.Just)…'
        & winget install --id Casey.Just -e --accept-package-agreements --accept-source-agreements
        if (-not (Test-WinMintJust)) {
            throw 'just not found on PATH after winget install. Open a new terminal and retry.'
        }
    }

    function Get-WinMintRelease {
        param([string]$Repo, [string]$RequestedVersion, [string]$ApiRoot)
        $encodedVersion = [uri]::EscapeDataString($RequestedVersion)
        $apiBase = $ApiRoot.TrimEnd('/')
        $releasePath = if ($RequestedVersion -eq 'latest') {
            "$apiBase/repos/$Repo/releases/latest"
        }
        else {
            "$apiBase/repos/$Repo/releases/tags/$encodedVersion"
        }
        Set-WinMintBootstrapOperation -Operation "Querying release metadata for '$RequestedVersion' from $Repo." `
            -FailureKind 'Network' `
            -Recovery 'Check network access to GitHub. If using winmint.yanai.sh, verify Cloudflare is not blocking CLI clients.'
        Write-WinMintBootstrapLog "Querying GitHub release '$RequestedVersion' from $Repo."
        Invoke-RestMethod -Uri $releasePath -Headers @{
            'Accept'     = 'application/vnd.github+json'
            'User-Agent' = 'WinMint-Bootstrap'
        } -UseBasicParsing
    }

    function Select-WinMintAsset {
        param($Release, [string]$PreferredName)
        $assets = @($Release.assets)
        if ($assets.Count -eq 0) { throw "Release '$($Release.tag_name)' has no downloadable assets." }
        $preferred = $assets | Where-Object { $_.name -eq $PreferredName } | Select-Object -First 1
        if ($preferred) { return $preferred }
        return $assets | Where-Object { $_.name -like 'WinMint-*.zip' -and $_.name -notlike '*.sha256' } | Select-Object -First 1
    }

    function Get-WinMintFileSha256 {
        param([string]$Path)
        $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
        return $hash.Hash.ToUpperInvariant()
    }

    function Test-WinMintArchiveHash {
        param([string]$ArchivePath, [string]$ChecksumPath)
        Set-WinMintBootstrapOperation -Operation 'Verifying release archive SHA256.' -FailureKind 'Integrity' `
            -Recovery 'Do not run this release. Wait for corrected zip + .sha256 assets.' -RetrySafe $false
        $text = Get-Content -LiteralPath $ChecksumPath -Raw
        $match = [regex]::Match($text, '(?i)\b[a-f0-9]{64}\b')
        if (-not $match.Success) { throw "Checksum file '$ChecksumPath' does not contain a SHA256 hash." }
        $expected = $match.Value.ToUpperInvariant()
        $actual = Get-WinMintFileSha256 -Path $ArchivePath
        if ($actual -ne $expected) { throw "Archive SHA256 mismatch. Expected $expected, got $actual." }
        Write-WinMintBootstrapLog "Verified SHA256 $actual." 'OK'
    }

    function Resolve-WinMintBootstrapReleasePayload {
        param($Release, [string]$Tag, [string]$DownloadRoot)
        $archiveName = "WinMint-$Tag.zip"
        Set-WinMintBootstrapOperation -Operation "Resolving release assets for '$Tag'." -FailureKind 'Package' `
            -Recovery 'The selected GitHub release is incomplete. Use another version or wait for assets.' -RetrySafe $false
        $archive = Select-WinMintAsset -Release $Release -PreferredName $archiveName
        if (-not $archive) { throw "Release '$Tag' does not include a WinMint zip asset." }
        $checksumName = "$($archive.name).sha256"
        $checksum = @($Release.assets | Where-Object { $_.name -eq $checksumName } | Select-Object -First 1)
        if (-not $checksum) {
            throw "Release '$Tag' is missing required checksum asset '$checksumName'. Refusing to install without release integrity verification."
        }
        [pscustomobject]@{
            Archive      = $archive
            Checksum     = $checksum
            ArchivePath  = Join-Path $DownloadRoot $archive.name
            ChecksumPath = Join-Path $DownloadRoot $checksum.name
            Version      = $Tag
        }
    }

    function New-WinMintBootstrapSessionRoot {
        param([string]$Tag)
        $safeTag = $Tag -replace '[^A-Za-z0-9._-]', '_'
        $name = "WinMintBootstrap-$safeTag-$([guid]::NewGuid().ToString('N'))"
        return Join-Path ([IO.Path]::GetTempPath()) $name
    }

    function Remove-WinMintBootstrapSessionRoot {
        param([string]$Path)
        if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return }
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            Write-WinMintBootstrapLog "Removed temporary session '$Path'." 'OK'
        }
        catch {
            Write-WinMintBootstrapLog "Could not remove temporary session '$Path': $($_.Exception.Message)" 'WARN'
        }
    }

    function Find-WinMintToolkitRoot {
        param([string]$ExtractRoot)
        if ((Test-Path -LiteralPath (Join-Path $ExtractRoot 'Justfile')) -or
            (Test-Path -LiteralPath (Join-Path $ExtractRoot 'justfile'))) {
            return $ExtractRoot
        }
        $child = Get-ChildItem -LiteralPath $ExtractRoot -Directory | Select-Object -First 1
        if ($child -and ((Test-Path (Join-Path $child.FullName 'Justfile')) -or (Test-Path (Join-Path $child.FullName 'justfile')))) {
            return $child.FullName
        }
        throw "Toolkit Justfile not found under '$ExtractRoot'."
    }

    $release = Get-WinMintRelease -Repo $Repository -RequestedVersion $Version -ApiRoot $ReleaseApiRoot
    $tag = [string]$release.tag_name
    if ([string]::IsNullOrWhiteSpace($tag)) { throw 'Release metadata missing tag_name.' }

    $useCache = $CacheRelease -or -not [string]::IsNullOrWhiteSpace($InstallRoot)
    $sessionRoot = $null
    $downloadRoot = $null
    $toolkitRoot = $null

    if ($useCache) {
        if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
            $InstallRoot = Join-Path $env:LOCALAPPDATA "WinMint\versions\$tag"
        }
        Write-WinMintBootstrapLog "Using explicit release cache root '$InstallRoot'."
        $toolkitRoot = $InstallRoot
        $downloadRoot = Join-Path $env:TEMP "WinMintDownload-$tag"
        New-Item -ItemType Directory -Force -Path $downloadRoot | Out-Null
        if ((Test-Path -LiteralPath (Join-Path $toolkitRoot 'Justfile')) -or (Test-Path -LiteralPath (Join-Path $toolkitRoot 'justfile'))) {
            if (-not $Force) {
                Write-WinMintBootstrapLog "Reusing cached toolkit at '$toolkitRoot'."
            }
        }
        else {
            $Force = $true
        }
    }
    else {
        $sessionRoot = New-WinMintBootstrapSessionRoot -Tag $tag
        Write-WinMintBootstrapLog "Using temporary session '$sessionRoot'."
        New-Item -ItemType Directory -Force -Path $sessionRoot | Out-Null
        $downloadRoot = $sessionRoot
        $toolkitRoot = $null
        $Force = $true
    }

    if ($Force -or -not $toolkitRoot -or -not (Test-Path -LiteralPath (Join-Path $toolkitRoot 'Justfile'))) {
        $payload = Resolve-WinMintBootstrapReleasePayload -Release $release -Tag $tag -DownloadRoot $downloadRoot
        Set-WinMintBootstrapOperation -Operation "Downloading release asset '$($payload.Archive.name)'." -FailureKind 'Network'
        Write-WinMintBootstrapLog "Downloading $($payload.Archive.name)."
        Invoke-WebRequest -Uri $payload.Archive.browser_download_url -OutFile $payload.ArchivePath -Headers @{ 'User-Agent' = 'WinMint-Bootstrap' } -UseBasicParsing
        Invoke-WebRequest -Uri $payload.Checksum.browser_download_url -OutFile $payload.ChecksumPath -Headers @{ 'User-Agent' = 'WinMint-Bootstrap' } -UseBasicParsing
        Test-WinMintArchiveHash -ArchivePath $payload.ArchivePath -ChecksumPath $payload.ChecksumPath

        $extractTo = if ($useCache) { $InstallRoot } else { Join-Path $sessionRoot 'toolkit' }
        if (Test-Path -LiteralPath $extractTo) { Remove-Item -LiteralPath $extractTo -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $extractTo | Out-Null
        Set-WinMintBootstrapOperation -Operation "Extracting release archive to '$extractTo'." -FailureKind 'Package'
        Expand-Archive -LiteralPath $payload.ArchivePath -DestinationPath $extractTo -Force
        $toolkitRoot = Find-WinMintToolkitRoot -ExtractRoot $extractTo
    }

    if ($PrimaryGate) {
        $Mode = 'Headless'
        if ($ValidateOnly) { throw 'Use only one of -PrimaryGate or -ValidateOnly.' }
    }

    if ($NoLaunch) {
        Write-WinMintBootstrapLog 'NoLaunch requested; not starting WinMint.'
        Write-Host $toolkitRoot
        if ($sessionRoot) {
            # Leave TEMP toolkit for this job (live-session / disposable path). Not a durable install.
            Write-WinMintBootstrapLog "Ephemeral toolkit left at '$toolkitRoot' — run just primary-gate from there, then delete the folder." 'WARN'
        }
        exit 0
    }

    Set-Location -LiteralPath $toolkitRoot
    if ($Mode -eq 'Gui') {
        $wizard = Join-Path $toolkitRoot 'bin\wizard\WinMint.Wizard.exe'
        if (-not (Test-Path -LiteralPath $wizard -PathType Leaf)) {
            throw "WinMint.Wizard.exe was not found at '$wizard'."
        }
        Write-WinMintBootstrapLog "Launching Wizard: $wizard"
        if ($null -ne $sessionRoot) {
            Write-WinMintBootstrapLog "Ephemeral session toolkit: $toolkitRoot"
            Write-WinMintBootstrapLog 'Wipe ISO while Wizard is open: second terminal → cd to toolkit root → just primary-gate. Or one-shot: irm …/primary-gate?SourceIso=… | iex (see README).' 'WARN'
        }
        $p = Start-Process -FilePath $wizard -WorkingDirectory $toolkitRoot -PassThru -Wait
        $code = $p.ExitCode
    }
    else {
        $cli = Join-Path $toolkitRoot 'bin\cli\WinMint.Cli.exe'
        if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) {
            throw "WinMint.Cli.exe was not found at '$cli'."
        }
        $cliArgs = [System.Collections.Generic.List[string]]::new()
        if ($ValidateOnly) {
            if ([string]::IsNullOrWhiteSpace($ProfilePath)) { throw '-ProfilePath is required with -ValidateOnly.' }
            $cliArgs.Add('validate')
            $cliArgs.Add($ProfilePath)
        }
        else {
            if ([string]::IsNullOrWhiteSpace($ProfilePath)) { throw '-ProfilePath is required for -Headless build.' }
            if ([string]::IsNullOrWhiteSpace($SourceIso)) { throw '-SourceIso is required for -Headless build.' }
            # Keep Apply workdir outside TEMP toolkit so Output ISO survives ephemeral cleanup.
            if ([string]::IsNullOrWhiteSpace($Work)) {
                if ($PrimaryGate) {
                    $Work = Join-Path $env:LOCALAPPDATA 'WinMint\work\gate-b' # must match Get-WinMintGateBWorkDirectory
                }
                else {
                    $Work = Join-Path $env:LOCALAPPDATA 'WinMint\work\scratch'
                }
            }
            New-Item -ItemType Directory -Force -Path $Work | Out-Null
            $cliArgs.Add('build')
            $cliArgs.Add($ProfilePath)
            $cliArgs.Add('--iso')
            $cliArgs.Add($SourceIso)
            $cliArgs.Add('--work')
            $cliArgs.Add($Work)
            if ($PrimaryGate) {
                $cliArgs.Add('--image-quality')
                $cliArgs.Add('Release')
                $cliArgs.Add('--package-strict')
                $cliArgs.Add('--package-audit-strict')
            }
        }
        Write-WinMintBootstrapLog "Launching Cli: $cli $($cliArgs -join ' ')"
        & $cli @cliArgs
        $code = $LASTEXITCODE
        if ($PrimaryGate -and $code -eq 0) {
            Write-WinMintBootstrapLog "Gate B workdir: $Work (Output ISO + evidence). Toolkit session may be deleted next; workdir is kept."
        }
    }

    if ($sessionRoot) { Remove-WinMintBootstrapSessionRoot -Path $sessionRoot }
    exit $code
}
catch {
    Write-WinMintBootstrapFailure -ErrorRecord $_
    if ($sessionRoot) { Remove-WinMintBootstrapSessionRoot -Path $sessionRoot }
    exit 1
}
