#Requires -Version 7.6

$script:WinMintHeadlessBuildId = ''
$script:WinMintHeadlessStatePath = ''
function Get-WinMintHeadlessStateRoot {
    Join-Path (Get-WinMintOutputDirectory) '.state'
}

function New-WinMintHeadlessBuildId {
    '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([Guid]::NewGuid().ToString('n').Substring(0, 8))
}

function Get-WinMintHeadlessStatePath {
    param([Parameter(Mandatory)][string]$BuildId)
    Join-Path (Get-WinMintHeadlessStateRoot) "$BuildId.json"
}

function Read-WinMintHeadlessState {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Save-WinMintHeadlessState {
    param([Parameter(Mandatory)][object]$State)

    $root = Get-WinMintHeadlessStateRoot
    $null = New-Item -ItemType Directory -Path $root -Force
    $path = Get-WinMintHeadlessStatePath -BuildId ([string]$State.buildId)
    $json = $State | ConvertTo-Json -Depth 16
    [System.IO.File]::WriteAllText($path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    return $path
}

function New-WinMintHeadlessState {
    param(
        [Parameter(Mandatory)][string]$BuildId,
        [string]$ProfilePath = '',
        [string]$SourceIso = ''
    )

    $profileHash = ''
    if (-not [string]::IsNullOrWhiteSpace($ProfilePath) -and (Test-Path -LiteralPath $ProfilePath)) {
        $profileHash = (Get-FileHash -LiteralPath $ProfilePath -Algorithm SHA256).Hash
    }
    [pscustomobject]@{
        marker = 'WinMintHeadlessState'
        buildId = $BuildId
        repositoryRoot = Get-WinMintRepositoryRoot
        sourceIso = $SourceIso
        sourceIsoFingerprint = ''
        profilePath = $ProfilePath
        profileHash = $profileHash
        workDir = ''
        mountDir = ''
        isoContents = ''
        phase = 'Initialize'
        startedAt = [DateTimeOffset]::Now.ToString('o')
        completedAt = $null
        processId = $PID
        result = 'running'
        cleanupEligible = $true
        reports = [pscustomobject]@{}
        warnings = @()
        failures = @()
    }
}

function Set-WinMintHeadlessJournalPhase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Phase,
        [string]$WorkDir,
        [string]$MountDir,
        [string]$IsoContents
    )

    if ([string]::IsNullOrWhiteSpace([string]$script:WinMintHeadlessStatePath)) { return }
    $state = Read-WinMintHeadlessState -Path $script:WinMintHeadlessStatePath
    if ($null -eq $state) { return }
    $state.phase = $Phase
    if (-not [string]::IsNullOrWhiteSpace($WorkDir)) { $state.workDir = $WorkDir }
    if (-not [string]::IsNullOrWhiteSpace($MountDir)) { $state.mountDir = $MountDir }
    if (-not [string]::IsNullOrWhiteSpace($IsoContents)) { $state.isoContents = $IsoContents }
    [void](Save-WinMintHeadlessState -State $state)
}

function Complete-WinMintHeadlessJournal {
    param(
        [Parameter(Mandatory)][string]$Result,
        [object]$Reports,
        [string[]]$Warnings = @(),
        [string[]]$Failures = @()
    )

    if ([string]::IsNullOrWhiteSpace([string]$script:WinMintHeadlessStatePath)) { return }
    $state = Read-WinMintHeadlessState -Path $script:WinMintHeadlessStatePath
    if ($null -eq $state) { return }
    $state.phase = 'Report'
    $state.completedAt = [DateTimeOffset]::Now.ToString('o')
    $state.result = $Result
    if ($Reports) { $state.reports = $Reports }
    $state.warnings = @($Warnings)
    $state.failures = @($Failures)
    [void](Save-WinMintHeadlessState -State $state)
}

function Write-WinMintHeadlessWorkMarker {
    param(
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string]$MountDir,
        [Parameter(Mandatory)][string]$IsoContents
    )

    if ([string]::IsNullOrWhiteSpace([string]$script:WinMintHeadlessBuildId)) { return }
    $marker = [pscustomobject]@{
        marker = 'WinMintHeadlessWork'
        buildId = $script:WinMintHeadlessBuildId
        processId = $PID
        createdAt = [DateTimeOffset]::Now.ToString('o')
        mountDir = $MountDir
        isoContents = $IsoContents
    }
    $path = Join-Path $WorkDir '.winmint-work.json'
    $json = $marker | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Test-WinMintProcessRunning {
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return $false }
    $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Get-WinMintHeadlessWorkItem {
    $items = [System.Collections.Generic.List[object]]::new()
    $root = Get-WinMintHeadlessStateRoot
    if (Test-Path -LiteralPath $root) {
        foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.json' -File -ErrorAction SilentlyContinue) {
            $state = Read-WinMintHeadlessState -Path $file.FullName
            if ($null -eq $state -or [string]$state.marker -ne 'WinMintHeadlessState') { continue }
            $running = Test-WinMintProcessRunning -ProcessId ([int]$state.processId)
            $stale = ([string]$state.result -eq 'running' -and -not $running)
            $items.Add([pscustomobject]@{
                buildId = [string]$state.buildId
                phase = [string]$state.phase
                result = [string]$state.result
                processId = [int]$state.processId
                processRunning = $running
                stale = $stale
                workDir = [string]$state.workDir
                mountDir = [string]$state.mountDir
                statePath = $file.FullName
            }) | Out-Null
        }
    }
    return $items.ToArray()
}

function Invoke-WinMintHeadlessCleanWork {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Target)

    $items = @(Get-WinMintHeadlessWorkItem)
    if ($Target -eq 'AllStale') {
        $items = @($items | Where-Object { $_.stale })
    } else {
        $items = @($items | Where-Object { $_.buildId -eq $Target })
    }

    $cleaned = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $items) {
        if ($item.processRunning) { continue }
        $workDir = [string]$item.workDir
        $markerPath = if ([string]::IsNullOrWhiteSpace($workDir)) { '' } else { Join-Path $workDir '.winmint-work.json' }
        $markerOwned = -not [string]::IsNullOrWhiteSpace($markerPath) -and (Test-Path -LiteralPath $markerPath)
        if ($markerOwned -and -not [string]::IsNullOrWhiteSpace([string]$item.mountDir)) {
            try {
                if (Test-WinMintMountedImagePath -Path ([string]$item.mountDir)) {
                    Dismount-WindowsImage -Path ([string]$item.mountDir) -Discard -ErrorAction SilentlyContinue | Out-Null
                }
            } catch {
                Write-Verbose "Could not discard stale mount '$($item.mountDir)': $($_.Exception.Message)"
            }
        }
        if ($markerOwned -and (Test-Path -LiteralPath $workDir)) {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        $state = Read-WinMintHeadlessState -Path ([string]$item.statePath)
        if ($state) {
            $state.result = 'cleaned'
            $state.phase = 'Cleanup'
            $state.completedAt = [DateTimeOffset]::Now.ToString('o')
            [void](Save-WinMintHeadlessState -State $state)
        }
        $cleaned.Add($item) | Out-Null
    }
    return $cleaned.ToArray()
}

function Resolve-WinMintHeadlessSecret {
    param(
        [string]$Password = '',
        [string]$PasswordPath = '',
        [string]$PasswordEnvVar = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($PasswordPath)) {
        if (-not (Test-Path -LiteralPath $PasswordPath)) { throw "Password file not found: $PasswordPath" }
        return [pscustomobject]@{ Password = (Get-Content -LiteralPath $PasswordPath -Raw).TrimEnd("`r", "`n"); UsedDeprecatedPassword = $false }
    }
    if (-not [string]::IsNullOrWhiteSpace($PasswordEnvVar)) {
        $value = [Environment]::GetEnvironmentVariable($PasswordEnvVar)
        if ($null -eq $value) { throw "Password environment variable is not set: $PasswordEnvVar" }
        return [pscustomobject]@{ Password = $value; UsedDeprecatedPassword = $false }
    }
    [pscustomobject]@{ Password = $Password; UsedDeprecatedPassword = -not [string]::IsNullOrWhiteSpace($Password) }
}

function Import-WinMintHeadlessBuildProfile {
    param(
        [Parameter(Mandatory)][string]$ProfilePath,
        [string]$SourceIsoOverride = ''
    )

    if (-not (Test-Path -LiteralPath $ProfilePath)) { throw "Profile not found: $ProfilePath" }
    $buildProfile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
    if (-not [string]::IsNullOrWhiteSpace($SourceIsoOverride)) {
        $buildProfile.source.isoPath = $SourceIsoOverride
    }
    Assert-WinMintBuildProfile -BuildProfile $buildProfile
    return $buildProfile
}

function Invoke-WinMintHeadlessSourcePrep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$ValidateOnly
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Source ISO not found: $Path"
    }

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.PSIsContainer) {
        throw "Source folders are not accepted. Pass a final Microsoft ISO with -SourceIso: $($item.FullName)"
    }
    if ($item.Extension -ine '.iso') {
        throw "Source input must be a Microsoft ISO: $($item.FullName)"
    }

    [pscustomobject]@{
        SourceKind = 'Iso'
        SourceIso = $item.FullName
        GeneratedIso = $item.FullName
        Reused = $true
        RanConversion = $false
        Logs = ''
        ValidateOnly = [bool]$ValidateOnly
    }
}

function Resolve-WinMintHeadlessDriverIntent {
    param(
        [ValidateSet('ThisPC', 'DifferentPC')][string]$TargetDevice = 'DifferentPC',
        [string]$DriverPack = '',
        [ValidateSet('None', 'Host', 'Custom', 'HostExport', 'CustomInfFolder', 'OemMsi', 'SurfaceMsiSafe', 'SurfaceCatalog')][string]$DriverSource = 'None',
        [string]$DriverPath = '',
        [switch]$ExportHostDrivers
    )

    if (-not [string]::IsNullOrWhiteSpace($DriverPack)) {
        if (-not (Test-Path -LiteralPath $DriverPack -PathType Leaf)) {
            throw "Driver pack not found: $DriverPack"
        }
        $item = Get-Item -LiteralPath $DriverPack
        if ($item.Extension -notin '.msi', '.zip') {
            throw 'DriverPack must be an OEM .msi or .zip file.'
        }
        $source = if ($item.Extension -ieq '.msi') { 'OemMsi' } else { 'Custom' }
        return [pscustomobject]@{ Source = $source; Path = $item.FullName; ExportHostDrivers = $false }
    }
    if ($ExportHostDrivers) { return [pscustomobject]@{ Source = 'Host'; Path = ''; ExportHostDrivers = $true } }
    if (Test-WinMintDriverSourceUsesSurfaceCatalog -Source $DriverSource) {
        if ([string]::IsNullOrWhiteSpace($DriverPath)) { throw 'SurfaceCatalog driver source requires -DriverPath with a Surface catalog device id.' }
        return [pscustomobject]@{ Source = $DriverSource; Path = $DriverPath; ExportHostDrivers = $false }
    }
    if (Test-WinMintDriverSourceUsesPath -Source $DriverSource) {
        if ([string]::IsNullOrWhiteSpace($DriverPath)) { throw 'Custom driver source requires -DriverPath.' }
        if ((Test-WinMintDriverSourceRequiresMsi -Source $DriverSource) -and -not ($DriverPath -match '(?i)\.msi$')) {
            throw "$DriverSource requires an OEM .msi file."
        }
        return [pscustomobject]@{ Source = $DriverSource; Path = $DriverPath; ExportHostDrivers = $false }
    }
    if ((Test-WinMintDriverSourceUsesHostExport -Source $DriverSource) -or $TargetDevice -eq 'ThisPC') {
        return [pscustomobject]@{ Source = 'Host'; Path = ''; ExportHostDrivers = $true }
    }
    [pscustomobject]@{ Source = 'None'; Path = ''; ExportHostDrivers = $false }
}

function New-WinMintHeadlessProfileFromFlags {
    [CmdletBinding()]
    param(
        [string]$SourceIso,
        [string]$Architecture,
        [string]$ComputerName = 'WinMint',
        [string]$AccountName = 'dev',
        [ValidateSet('Local', 'MicrosoftOobe')][string]$AccountMode = 'Local',
        [string]$Password = '',
        [switch]$AutoLogon,
        [switch]$AutoWipeDisk,
        [ValidateSet('TargetLicense', 'Fixed')][string]$EditionMode = 'TargetLicense',
        [string]$Edition = '',
        [string]$ProductKey = '',
        [ValidateSet('None', 'Host', 'Custom', 'HostExport', 'CustomInfFolder', 'OemMsi', 'SurfaceMsiSafe', 'SurfaceCatalog')][string]$DriverSource = 'None',
        [string]$DriverPath = '',
        [ValidateSet('ThisPC', 'DifferentPC')][string]$TargetDevice = 'DifferentPC',
        [ValidateSet('Balanced', 'EnergySaver', 'HighPerformance', 'UltimatePerformance')][string]$PowerPlan = 'Balanced',
        [string]$DriverPack = '',
        [switch]$ExportHostDrivers,
        [string]$TimeZoneId = '',
        [string]$InputLocale = '',
        [string]$SystemLocale = '',
        [string]$UILanguage = '',
        [string]$UILanguageFallback = '',
        [string]$UserLocale = '',
        [string[]]$Editor = @(),
        [string[]]$Browser = @(),
        [string[]]$Wsl2Distros = @(),
        [switch]$DesktopUI,
        [switch]$KeepEdge,
        [switch]$KeepGaming,
        [switch]$KeepCopilot,
        [ValidateSet('On', 'Off')][string]$Dma = 'On',
        [ValidateSet('None', 'Raycast')][string]$Launcher = 'None',
        [switch]$LiveInstallAudit,
        [switch]$PhoneLink,
        [ValidateSet('On', 'Off')][string]$Location = 'On',
        [ValidateSet('None', 'Stable25H2')][string]$UpdateImage = 'None',
        [string]$UpdatePayloadRoot = '',
        [ValidateSet('On', 'Off')][string]$UpdateProvisionedApps = 'On',
        [ValidateSet('windhawk', 'yasb', 'thide', 'komorebi', 'nilesoft')][string[]]$Install = @(),
        [switch]$DryRun,
        [switch]$ValidateOnly,
        [switch]$TemplateMode
    )

    if (-not $DryRun -and -not $ValidateOnly -and -not $TemplateMode -and [string]::IsNullOrWhiteSpace($SourceIso)) {
        throw 'SourceIso is required for headless builds. Use -ProfilePath or -DryRun for profile-only validation.'
    }
    if ($AutoLogon -and [string]::IsNullOrWhiteSpace($Password)) {
        throw 'Autologon requires an included account password.'
    }
    if ($AccountMode -eq 'MicrosoftOobe') {
        $Password = ''
        $AutoLogon = $false
    }

    $normalizeSelection = {
        param([string[]]$Values, [string[]]$Allowed, [string]$Name)
        $selected = @(
            @($Values) |
                ForEach-Object { ([string]$_) -split '[,\s]+' } |
                ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } |
                Where-Object { $_ }
        )
        $bad = @($selected | Where-Object { $_ -notin $Allowed })
        if ($bad.Count -gt 0) {
            throw "$Name contains unsupported value(s): $($bad -join ', ')."
        }
        return @($selected | Select-Object -Unique)
    }

    $selectedEditors = & $normalizeSelection $Editor @('cursor', 'vscode', 'zed', 'antigravity', 'neovim') 'Editor'
    $selectedBrowsers = & $normalizeSelection $Browser @('zen-browser', 'helium', 'firefox-developer-edition', 'brave', 'edge') 'Browser'
    $selectedWslDistros = @((ConvertTo-WinMintWslSelection -Values $Wsl2Distros).ProfileTokens)

    $drivers = Resolve-WinMintHeadlessDriverIntent `
        -TargetDevice $TargetDevice `
        -DriverPack $DriverPack `
        -DriverSource $DriverSource `
        -DriverPath $DriverPath `
        -ExportHostDrivers:$ExportHostDrivers

    # Subtractive model: the default build removes everything. Opt-in keep flags
    # suppress a domain's removal.
    $resolvedKeepGaming = [bool]$KeepGaming
    $resolvedKeepCopilot = [bool]$KeepCopilot
    $resolvedKeepEdge = [bool]$KeepEdge
    $resolvedDesktopUi = [bool]$DesktopUI -and -not [bool]$TemplateMode

    New-WinMintBuildProfileFromSettings -Settings @{
        Profile = 'WinMint'
        KeepEdge = $resolvedKeepEdge
        KeepGaming = $resolvedKeepGaming
        KeepCopilot = $resolvedKeepCopilot
        ISOPath = $SourceIso
        Architecture = $Architecture
        TargetDevice = $TargetDevice
        PowerPlan = $PowerPlan
        ComputerName = $ComputerName
        AccountName = $AccountName
        AccountMode = $AccountMode
        Password = $Password
        AutoLogon = [bool]$AutoLogon
        AutoWipeDisk = [bool]$AutoWipeDisk
        EditionMode = $EditionMode
        Edition = $Edition
        ProductKey = $ProductKey
        DriverSource = $drivers.Source
        DriverPath = $drivers.Path
        ExportHostDrivers = $drivers.ExportHostDrivers
        TimeZoneId = $TimeZoneId
        InputLocale = $InputLocale
        SystemLocale = $SystemLocale
        UILanguage = $UILanguage
        UILanguageFallback = $UILanguageFallback
        UserLocale = $UserLocale
        Editors = @($selectedEditors)
        Browsers = @($selectedBrowsers)
        Wsl2Distros = @($selectedWslDistros)
        DesktopUiDefault = $resolvedDesktopUi
        InstallWindhawk = [bool]('windhawk' -in $Install)
        InstallYasb = [bool]('yasb' -in $Install)
        InstallThide = [bool]('thide' -in $Install)
        InstallKomorebi = [bool]('komorebi' -in $Install)
        InstallNilesoft = [bool]('nilesoft' -in $Install)
        Launcher = $Launcher
        LiveInstallAudit = [bool]$LiveInstallAudit
        PhoneLink = [bool]$PhoneLink
        TweakDmaInterop = ($Dma -ne 'Off')
        PrivLocation = ($Location -ne 'Off')
        UpdateImage = $UpdateImage
        UpdatePayloadRoot = $UpdatePayloadRoot
        UpdateProvisionedApps = $UpdateProvisionedApps
    } -IncludeSecrets:($AccountMode -eq 'Local' -and -not [string]::IsNullOrWhiteSpace($Password))
}

function New-WinMintHeadlessResult {
    param(
        [Parameter(Mandatory)][string]$Result,
        [string]$BuildId = '',
        [string]$OutputIso = '',
        [object]$Reports,
        [string[]]$Warnings = @(),
        [string[]]$Failures = @()
    )
    [pscustomobject]@{
        result = $Result
        buildId = $BuildId
        outputIso = $OutputIso
        reports = if ($Reports) { $Reports } else { [pscustomobject]@{} }
        warnings = @($Warnings)
        failures = @($Failures)
    }
}

function New-WinMintHeadlessProfileAuthoringResult {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$BuildProfile
    )

    Assert-WinMintBuildProfile -BuildProfile $BuildProfile
    $savedPath = Save-WinMintBuildProfile -BuildProfile $BuildProfile -Path $Path
    New-WinMintHeadlessResult -Result 'profile-created' -Reports ([pscustomobject]@{ profile = $savedPath })
}

function Write-WinMintHeadlessJsonResult {
    param([Parameter(Mandatory)][object]$Result)
    [Console]::Out.WriteLine(($Result | ConvertTo-Json -Depth 16 -Compress))
}

function Write-WinMintHeadlessHumanResult {
    param([Parameter(Mandatory)][object]$Result)
    $status = [string]$Result.result
    Write-Host "WinMint headless result: $status"
    if (-not [string]::IsNullOrWhiteSpace([string]$Result.buildId)) { Write-Host "Build ID: $($Result.buildId)" }
    if (-not [string]::IsNullOrWhiteSpace([string]$Result.outputIso)) { Write-Host "Output ISO: $($Result.outputIso)" }
    if ($Result.reports -and $Result.reports.PSObject.Properties['profile'] -and
        -not [string]::IsNullOrWhiteSpace([string]$Result.reports.profile)) {
        Write-Host "Profile: $($Result.reports.profile)"
    }
    $buildDeltaPath = ''
    if ($Result.reports -and $Result.reports.PSObject.Properties['buildDelta']) {
        $buildDeltaPath = [string]$Result.reports.buildDelta
    }
    if (-not [string]::IsNullOrWhiteSpace($buildDeltaPath) -and
        (Get-Command Get-WinMintBuildDeltaSummary -ErrorAction SilentlyContinue)) {
        $deltaSummary = Get-WinMintBuildDeltaSummary -BuildDeltaPath $buildDeltaPath
        if ($deltaSummary -and $deltaSummary.totalRecords -gt 0) {
            Write-Host "BuildDelta: $buildDeltaPath"
            Write-Host "  Records: $($deltaSummary.totalRecords) total, $($deltaSummary.userControlledCount) user-controlled"
            $phaseSegments = @(
                @($deltaSummary.phaseCounts.PSObject.Properties) |
                    ForEach-Object { "$($_.Name)=$($_.Value)" }
            )
            if ($phaseSegments.Count -gt 0) {
                Write-Host "  Phases:  $($phaseSegments -join ', ')"
            }
            foreach ($highlight in @($deltaSummary.highlights | Select-Object -First 5)) {
                Write-Host "  - $($highlight.title) [$($highlight.phase)]"
            }
        }
    }
    foreach ($warning in @($Result.warnings)) { Write-Warning $warning }
    foreach ($failure in @($Result.failures)) { Write-Error $failure -ErrorAction Continue }
}

function Invoke-WinMintHeadlessValidateOnly {
    param(
        [Parameter(Mandatory)]$BuildProfile,
        [Parameter(Mandatory)][string]$BuildId,
        [switch]$DryRun
    )

    Set-WinMintHeadlessJournalPhase -Phase 'Preflight'
    $config = New-WinMintBuildConfig -BuildProfile $BuildProfile
    $installPlan = New-WinMintInstallPlanFromBuildConfig -BuildConfig $config
    $null = New-WinMintBuildDeltaCatalog -BuildConfig $config -InstallPlan $installPlan
    $buildDeltaPath = Save-WinMintBuildDeltaCatalog -OutputDir (Get-WinMintOutputDirectory)
    $runMode = if ($DryRun) { 'DryRun' } else { 'ValidateOnly' }
    $pre = Test-WinMintBuildPrerequisite -Config $config -RunMode $runMode
    $report = New-WinMintBuildReport -Config $config -DetectedArchitecture $config.Architecture -Warnings $pre.Warnings -Failures $pre.Failures
    $paths = Save-WinMintBuildReport -Report $report
    $reports = [pscustomobject]@{
        json = $paths.Json
        markdown = $paths.Markdown
        manifest = ''
        buildDelta = $buildDeltaPath
        state = Get-WinMintHeadlessStatePath -BuildId $BuildId
    }
    $resultName = if ($pre.Passed) { 'success' } else { 'validation-failed' }
    Complete-WinMintHeadlessJournal -Result $resultName -Reports $reports -Warnings $pre.Warnings -Failures $pre.Failures
    New-WinMintHeadlessResult -Result $resultName -BuildId $BuildId -Reports $reports -Warnings $pre.Warnings -Failures $pre.Failures
}

function Invoke-WinMintProfileRun {
    <#
    .SYNOPSIS
    Execute a profile-backed build or validation. The profile is the source of
    truth; the only run-specific inputs are the source override, USB target, and
    output/validation switches. Elevation is the caller's responsibility.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProfilePath,
        [string]$SourceIsoOverride = '',
        [switch]$DryRun,
        [switch]$ValidateOnly,
        [switch]$WriteUsb,
        [int]$UsbDiskNumber = -1,
        [int]$ConfirmUsbDiskNumber = -1,
        [switch]$AllowFixedUsbDisk,
        [switch]$AllowElevate,
        [switch]$Yes,
        [switch]$Json,
        [switch]$Quiet
    )

    try {
        if (-not (Resolve-WinMintCliElevation -AllowElevate:$AllowElevate)) { return $null }

        $warnings = [System.Collections.Generic.List[string]]::new()

        Set-WinMintHeadlessJournalPhase -Phase 'Profile'
        $resolvedSourceOverride = $SourceIsoOverride
        $buildProfile = Import-WinMintHeadlessBuildProfile -ProfilePath $ProfilePath -SourceIsoOverride $resolvedSourceOverride

        $sourceForState = [string](Get-WinMintProfileSetting (Get-WinMintProfileSetting $buildProfile 'source' @{}) 'isoPath' '')
        $script:WinMintHeadlessBuildId = New-WinMintHeadlessBuildId
        $state = New-WinMintHeadlessState -BuildId $script:WinMintHeadlessBuildId -ProfilePath $ProfilePath -SourceIso $sourceForState
        $script:WinMintHeadlessStatePath = Save-WinMintHeadlessState -State $state

        if ($ValidateOnly) {
            $result = Invoke-WinMintHeadlessValidateOnly -BuildProfile $buildProfile -BuildId $script:WinMintHeadlessBuildId -DryRun:$DryRun
            $result.warnings = @($warnings.ToArray() + @($result.warnings))
            Complete-WinMintHeadlessJournal -Result $result.result -Reports $result.reports -Warnings $result.warnings -Failures $result.failures
        } else {
            Set-WinMintHeadlessJournalPhase -Phase 'Preflight'
            $progress = {
                param($ProgressEvent)
                if ($Quiet -or $Json) { return }
                $level = [string]$ProgressEvent.Level
                $message = [string]$ProgressEvent.Message
                # This handler is the sole console sink for headless builds (the
                # engine's Log functions suppress their direct write while a handler
                # is active), so render the same glyph cues the engine uses.
                switch ($level) {
                    'Error'   { Write-Error $message -ErrorAction Continue }
                    'Warn'    { Write-Warning $message }
                    'OK'      { Write-Host "+ $message" }
                    'Section' { Write-Host $message }
                    default   { Write-Host "> $message" }
                }
            }
            $build = Start-WinMintBuild `
                -BuildProfile $buildProfile `
                -DryRun:$DryRun `
                -WriteUsb:$WriteUsb `
                -UsbDiskNumber $UsbDiskNumber `
                -ConfirmUsbDiskNumber $ConfirmUsbDiskNumber `
                -AllowFixedUsbDisk:$AllowFixedUsbDisk `
                -ProgressHandler $progress
            $reports = [pscustomobject]@{
                json = $build.Paths.Json
                markdown = $build.Paths.Markdown
                manifest = Join-Path (Get-WinMintOutputDirectory) 'WinMint-BuildManifest.json'
                buildDelta = Join-Path (Get-WinMintOutputDirectory) 'WinMint-BuildDelta.json'
                state = Get-WinMintHeadlessStatePath -BuildId $script:WinMintHeadlessBuildId
            }
            $resultName = if ($DryRun) { 'dry-run' } else { 'success' }
            $outputIso = if ($DryRun) { '' } else { [string]$build.OutputPath }
            $result = New-WinMintHeadlessResult -Result $resultName -BuildId $script:WinMintHeadlessBuildId -OutputIso $outputIso -Reports $reports -Warnings $warnings.ToArray()
            Complete-WinMintHeadlessJournal -Result $result.result -Reports $reports -Warnings $result.warnings
        }
    }
    catch {
        $failure = $_.Exception.Message
        $buildId = [string]$script:WinMintHeadlessBuildId
        $reports = [pscustomobject]@{}
        if (-not [string]::IsNullOrWhiteSpace($buildId)) {
            $reports = [pscustomobject]@{ state = Get-WinMintHeadlessStatePath -BuildId $buildId }
            Complete-WinMintHeadlessJournal -Result 'failed' -Reports $reports -Failures @($failure)
        }
        $result = New-WinMintHeadlessResult -Result 'failed' -BuildId $buildId -Reports $reports -Failures @($failure)
        if ($Json) { Write-WinMintHeadlessJsonResult -Result $result } elseif (-not $Quiet) { Write-WinMintHeadlessHumanResult -Result $result }
        return $result
    }

    if ($Json) { Write-WinMintHeadlessJsonResult -Result $result } elseif (-not $Quiet) { Write-WinMintHeadlessHumanResult -Result $result }
    return $result
}

