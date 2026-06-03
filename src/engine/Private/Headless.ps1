#Requires -Version 7.3

$script:WinMintHeadlessBuildId = ''
$script:WinMintHeadlessStatePath = ''
$script:WinMintSourcePrepResult = $null

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

function Assert-WinMintHeadlessParameterSet {
    param([Parameter(Mandatory)][hashtable]$BoundParameters)

    if ($BoundParameters.ContainsKey('ListWork') -and $BoundParameters.ContainsKey('CleanWork')) {
        throw 'Use either -ListWork or -CleanWork, not both.'
    }
    if ($BoundParameters.ContainsKey('SourceIso') -and $BoundParameters.ContainsKey('UupDumpSource')) {
        throw 'Use either -SourceIso or -UupDumpSource, not both. If UUP Dump already produced an ISO, pass that ISO with -SourceIso.'
    }
    if ($BoundParameters.ContainsKey('SourceIsoOverride') -and -not $BoundParameters.ContainsKey('ProfilePath')) {
        throw '-SourceIsoOverride is only valid with -ProfilePath. Use -SourceIso for flag-built profiles.'
    }
    if ($BoundParameters.ContainsKey('NewProfile') -and $BoundParameters.ContainsKey('OutProfile')) {
        throw 'Use either -NewProfile or -OutProfile, not both.'
    }
    if ($BoundParameters.ContainsKey('NewProfile') -and $BoundParameters.ContainsKey('ProfilePath')) {
        throw 'Use either -NewProfile to create a profile template or -ProfilePath to consume one, not both.'
    }
    if ($BoundParameters.ContainsKey('WriteUsb')) {
        if ($BoundParameters.ContainsKey('DryRun')) { throw '-WriteUsb cannot be used with -DryRun.' }
        if ($BoundParameters.ContainsKey('ValidateOnly')) { throw '-WriteUsb cannot be used with -ValidateOnly.' }
        if (-not $BoundParameters.ContainsKey('UsbDiskNumber')) { throw '-WriteUsb requires -UsbDiskNumber.' }
    }
    if (($BoundParameters.ContainsKey('UsbDiskNumber') -or $BoundParameters.ContainsKey('ConfirmUsbDiskNumber') -or $BoundParameters.ContainsKey('AllowFixedUsbDisk')) -and
        -not $BoundParameters.ContainsKey('WriteUsb')) {
        throw 'USB target flags require -WriteUsb.'
    }
    if (($BoundParameters.ContainsKey('NewProfile') -or $BoundParameters.ContainsKey('OutProfile')) -and
        $BoundParameters.ContainsKey('UupDumpSource')) {
        throw 'Profile templates store the resolved source ISO only. Use -SourceIso for profile authoring. Use -UupDumpSource only when running a build that should perform UUP source prep.'
    }
    if ($BoundParameters.ContainsKey('DriverPack') -and
        ($BoundParameters.ContainsKey('DriverSource') -or $BoundParameters.ContainsKey('DriverPath') -or $BoundParameters.ContainsKey('ExportHostDrivers'))) {
        throw 'Use only one driver source style: -DriverPack or -DriverSource/-DriverPath/-ExportHostDrivers.'
    }
    if ($BoundParameters.ContainsKey('LocationServices') -and $BoundParameters.ContainsKey('NoLocationServices')) {
        throw 'Use either -LocationServices or -NoLocationServices, not both.'
    }
    if ($BoundParameters.ContainsKey('DmaInterop') -and $BoundParameters.ContainsKey('NoDmaInterop')) {
        throw 'Use either -DmaInterop or -NoDmaInterop, not both.'
    }
    $secretInputs = @('Password', 'PasswordPath', 'PasswordEnvVar') | Where-Object {
        $BoundParameters.ContainsKey($_) -and -not [string]::IsNullOrWhiteSpace([string]$BoundParameters[$_])
    }
    if (@($secretInputs).Count -gt 1) {
        throw 'Use only one password input: -Password, -PasswordPath, or -PasswordEnvVar.'
    }
    if ($BoundParameters.ContainsKey('ProfilePath')) {
        $allowed = @(
            'ProfilePath', 'SourceIsoOverride', 'UupDumpSource', 'Yes', 'ValidateOnly', 'Json', 'NoProgress', 'Quiet',
            'DryRun', 'WriteUsb', 'UsbDiskNumber', 'ConfirmUsbDiskNumber', 'AllowFixedUsbDisk',
            'AllowElevate', 'Verbose', 'Debug', 'ErrorAction', 'WarningAction',
            'InformationAction', 'ProgressAction', 'ErrorVariable', 'WarningVariable',
            'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable'
        )
        $mixed = @($BoundParameters.Keys | Where-Object { $_ -notin $allowed })
        if ($mixed.Count -gt 0) {
            $mixedText = $mixed -join ', '
            throw (
                "-ProfilePath is the source of truth for profile-backed builds. Remove mixed profile-authoring flags: $mixedText. " +
                'Allowed overrides are source-prep, -SourceIsoOverride, validation/output flags, and elevation flags.'
            )
        }
    }
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
        [switch]$Yes,
        [switch]$ValidateOnly
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "UUP Dump source not found: $Path"
    }

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.PSIsContainer) {
        throw "UUP Dump folders are not accepted as source input: $($item.FullName). If UUP Dump already produced an ISO, pass that ISO with -SourceIso. Use -UupDumpSource only with a UUP Dump conversion zip."
    }

    if ($item.Extension -ieq '.iso') {
        return [pscustomobject]@{
            SourceKind = 'Iso'
            SourceIso = $item.FullName
            GeneratedIso = $item.FullName
            Reused = $true
            RanConversion = $false
            Logs = ''
        }
    }

    if ($item.Extension -ieq '.zip') {
        return Invoke-WinMintUupDumpSourcePrep -UupDumpZip $item.FullName -Yes:$Yes -ValidateOnly:$ValidateOnly
    }

    throw "UUP Dump source must be a final ISO or UUP Dump conversion zip: $($item.FullName). If UUP Dump already produced an ISO, prefer -SourceIso."
}

function Resolve-WinMintHeadlessDriverIntent {
    param(
        [ValidateSet('ThisPC', 'DifferentPC')][string]$TargetDevice = 'DifferentPC',
        [string]$DriverPack = '',
        [ValidateSet('None', 'Host', 'Custom')][string]$DriverSource = 'None',
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
        return [pscustomobject]@{ Source = 'Custom'; Path = $item.FullName; ExportHostDrivers = $false }
    }
    if ($ExportHostDrivers) { return [pscustomobject]@{ Source = 'Host'; Path = ''; ExportHostDrivers = $true } }
    if ($DriverSource -eq 'Custom') {
        if ([string]::IsNullOrWhiteSpace($DriverPath)) { throw 'Custom driver source requires -DriverPath.' }
        return [pscustomobject]@{ Source = 'Custom'; Path = $DriverPath; ExportHostDrivers = $false }
    }
    if ($DriverSource -eq 'Host' -or $TargetDevice -eq 'ThisPC') {
        return [pscustomobject]@{ Source = 'Host'; Path = ''; ExportHostDrivers = $true }
    }
    [pscustomobject]@{ Source = 'None'; Path = ''; ExportHostDrivers = $false }
}

function Resolve-WinMintHeadlessProfileGroups {
    param(
        [ValidateSet('Minimal', 'Developer', 'CopilotPlus', 'Gaming', 'DesktopUI')][string]$Preset = 'Minimal',
        [ValidateSet('Minimal', 'CopilotPlus')][string]$SetupOption = 'Minimal',
        [switch]$Developer,
        [switch]$Copilot,
        [switch]$DesktopUI,
        [switch]$Gaming
    )

    $groups = [System.Collections.Generic.List[string]]::new()
    $groups.Add('Minimal') | Out-Null
    switch ($Preset) {
        'Developer' { $groups.Add('Developer') | Out-Null }
        'CopilotPlus' { $groups.Add('CopilotPlus') | Out-Null }
        'Gaming' { $groups.Add('Gaming') | Out-Null }
        'DesktopUI' { $groups.Add('DesktopUI') | Out-Null }
    }
    if ($Developer) { $groups.Add('Developer') | Out-Null }
    if ($Copilot -or $SetupOption -eq 'CopilotPlus') { $groups.Add('CopilotPlus') | Out-Null }
    if ($Gaming) { $groups.Add('Gaming') | Out-Null }
    if ($DesktopUI) { $groups.Add('DesktopUI') | Out-Null }
    @($groups.ToArray() | Select-Object -Unique)
}

function New-WinMintHeadlessProfileFromFlags {
    [CmdletBinding()]
    param(
        [string]$SourceIso,
        [ValidateSet('Minimal', 'Developer', 'CopilotPlus', 'Gaming', 'DesktopUI')][string]$Preset = 'Minimal',
        [string]$Architecture,
        [string]$ComputerName = 'WinMint',
        [string]$AccountName = 'dev',
        [ValidateSet('Local', 'MicrosoftOobe')][string]$AccountMode = 'Local',
        [string]$Password = '',
        [switch]$AutoLogon,
        [switch]$AutoWipeDisk,
        [ValidateSet('Minimal', 'CopilotPlus')][string]$SetupOption = 'Minimal',
        [ValidateSet('TargetLicense', 'Fixed')][string]$EditionMode = 'TargetLicense',
        [string]$Edition = '',
        [ValidateSet('None', 'Host', 'Custom')][string]$DriverSource = 'None',
        [string]$DriverPath = '',
        [ValidateSet('ThisPC', 'DifferentPC')][string]$TargetDevice = 'DifferentPC',
        [string]$DriverPack = '',
        [switch]$ExportHostDrivers,
        [string]$TimeZoneId = '',
        [string]$InputLocale = '',
        [string]$SystemLocale = '',
        [string]$UILanguage = '',
        [string]$UILanguageFallback = '',
        [string]$UserLocale = '',
        [switch]$Developer,
        [switch]$Copilot,
        [switch]$DesktopUI,
        [switch]$Gaming,
        [switch]$KeepEdge,
        [switch]$KeepGaming,
        [switch]$KeepCopilot,
        [switch]$DmaInterop,
        [switch]$NoDmaInterop,
        [ValidateSet('None', 'FlowEverything', 'Raycast')][string]$Launcher = 'None',
        [switch]$LiveInstallAudit,
        [switch]$PhoneLink,
        [switch]$LocationServices,
        [switch]$NoLocationServices,
        [switch]$InstallWindhawk,
        [switch]$InstallYasb,
        [switch]$InstallKomorebi,
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

    $drivers = Resolve-WinMintHeadlessDriverIntent `
        -TargetDevice $TargetDevice `
        -DriverPack $DriverPack `
        -DriverSource $DriverSource `
        -DriverPath $DriverPath `
        -ExportHostDrivers:$ExportHostDrivers

    # Subtractive model: default removes everything. Opt-in keep flags suppress a
    # domain. Legacy -Gaming / -Preset Gaming map to -KeepGaming (same meaning the
    # old Gaming group had). -Developer is now baseline; old -Copilot / CopilotPlus
    # (which requested MORE AI removal) are no-ops because full removal is the
    # default — keeping Copilot+ AI now requires the explicit -KeepCopilot.
    $resolvedKeepGaming = [bool]$KeepGaming -or [bool]$Gaming -or ($Preset -eq 'Gaming')
    $resolvedKeepCopilot = [bool]$KeepCopilot
    $resolvedKeepEdge = [bool]$KeepEdge
    $resolvedDesktopUi = ([bool]$DesktopUI -or ($Preset -eq 'DesktopUI')) -and -not [bool]$TemplateMode

    New-WinMintBuildProfileFromSettings -Settings @{
        Profile = 'WinMint'
        KeepEdge = $resolvedKeepEdge
        KeepGaming = $resolvedKeepGaming
        KeepCopilot = $resolvedKeepCopilot
        ISOPath = $SourceIso
        Architecture = $Architecture
        TargetDevice = $TargetDevice
        ComputerName = $ComputerName
        AccountName = $AccountName
        AccountMode = $AccountMode
        Password = $Password
        AutoLogon = [bool]$AutoLogon
        AutoWipeDisk = [bool]$AutoWipeDisk
        EditionMode = $EditionMode
        Edition = $Edition
        DriverSource = $drivers.Source
        DriverPath = $drivers.Path
        ExportHostDrivers = $drivers.ExportHostDrivers
        TimeZoneId = $TimeZoneId
        InputLocale = $InputLocale
        SystemLocale = $SystemLocale
        UILanguage = $UILanguage
        UILanguageFallback = $UILanguageFallback
        UserLocale = $UserLocale
        DesktopUiDefault = $resolvedDesktopUi
        InstallWindhawk = [bool]$InstallWindhawk
        InstallYasb = [bool]$InstallYasb
        InstallKomorebi = [bool]$InstallKomorebi
        Launcher = $Launcher
        LiveInstallAudit = [bool]$LiveInstallAudit
        PhoneLink = [bool]$PhoneLink
        TweakDmaInterop = if ($NoDmaInterop) { $false } else { $true }
        PrivLocation = if ($NoLocationServices) { $false } else { $true }
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
    if ($status -in @('success', 'dry-run', 'cleaned', 'listed')) {
        Write-Host "WinMint headless result: $status"
    } else {
        Write-Host "WinMint headless result: $status"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Result.buildId)) { Write-Host "Build ID: $($Result.buildId)" }
    if (-not [string]::IsNullOrWhiteSpace([string]$Result.outputIso)) { Write-Host "Output ISO: $($Result.outputIso)" }
    if ($Result.reports -and $Result.reports.PSObject.Properties['profile'] -and
        -not [string]::IsNullOrWhiteSpace([string]$Result.reports.profile)) {
        Write-Host "Profile: $($Result.reports.profile)"
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
    $pre = Test-WinMintBuildPrerequisite -Config $config -AllowMissingSourceIso:$DryRun
    $report = New-WinMintBuildReport -Config $config -DetectedArchitecture $config.Architecture -Warnings $pre.Warnings -Failures $pre.Failures
    $paths = Save-WinMintBuildReport -Report $report
    $reports = [pscustomobject]@{
        json = $paths.Json
        markdown = $paths.Markdown
        manifest = ''
        state = Get-WinMintHeadlessStatePath -BuildId $BuildId
        sourcePrep = $script:WinMintSourcePrepResult
    }
    $resultName = if ($pre.Passed) { 'success' } else { 'validation-failed' }
    Complete-WinMintHeadlessJournal -Result $resultName -Reports $reports -Warnings $pre.Warnings -Failures $pre.Failures
    New-WinMintHeadlessResult -Result $resultName -BuildId $BuildId -Reports $reports -Warnings $pre.Warnings -Failures $pre.Failures
}

function Invoke-WinMintHeadlessCli {
    [CmdletBinding()]
    param(
        [hashtable]$BoundParameters,
        [string]$ProfilePath,
        [string]$NewProfile,
        [ValidateSet('Minimal', 'Developer', 'CopilotPlus', 'Gaming', 'DesktopUI')][string]$Preset = 'Minimal',
        [string]$OutProfile,
        [string]$SourceIso,
        [string]$UupDumpSource,
        [string]$SourceIsoOverride,
        [string]$Architecture,
        [string]$ComputerName = 'WinMint',
        [string]$AccountName = 'dev',
        [ValidateSet('Local', 'MicrosoftOobe')][string]$AccountMode = 'Local',
        [string]$Password = '',
        [string]$PasswordPath = '',
        [string]$PasswordEnvVar = '',
        [switch]$AutoLogon,
        [switch]$AutoWipeDisk,
        [ValidateSet('Minimal', 'CopilotPlus')][string]$SetupOption = 'Minimal',
        [ValidateSet('TargetLicense', 'Fixed')][string]$EditionMode = 'TargetLicense',
        [string]$Edition = '',
        [ValidateSet('None', 'Host', 'Custom')][string]$DriverSource = 'None',
        [string]$DriverPath = '',
        [ValidateSet('ThisPC', 'DifferentPC')][string]$TargetDevice = 'DifferentPC',
        [string]$DriverPack = '',
        [switch]$ExportHostDrivers,
        [string]$TimeZoneId = '',
        [string]$InputLocale = '',
        [string]$SystemLocale = '',
        [string]$UILanguage = '',
        [string]$UILanguageFallback = '',
        [string]$UserLocale = '',
        [switch]$Developer,
        [switch]$Copilot,
        [switch]$DesktopUI,
        [switch]$Gaming,
        [switch]$KeepEdge,
        [switch]$KeepGaming,
        [switch]$KeepCopilot,
        [switch]$DmaInterop,
        [switch]$NoDmaInterop,
        [ValidateSet('None', 'FlowEverything', 'Raycast')][string]$Launcher = 'None',
        [switch]$LiveInstallAudit,
        [switch]$PhoneLink,
        [switch]$LocationServices,
        [switch]$NoLocationServices,
        [switch]$InstallWindhawk,
        [switch]$InstallYasb,
        [switch]$InstallKomorebi,
        [switch]$DryRun,
        [switch]$ValidateOnly,
        [switch]$Json,
        [switch]$Quiet,
        [switch]$NoProgress,
        [switch]$AllowElevate,
        [switch]$Yes,
        [switch]$WriteUsb,
        [int]$UsbDiskNumber = -1,
        [int]$ConfirmUsbDiskNumber = -1,
        [switch]$AllowFixedUsbDisk,
        [switch]$ListWork,
        [string]$CleanWork
    )

    try {
        Assert-WinMintHeadlessParameterSet -BoundParameters $BoundParameters
        if ($ListWork) {
            $work = @(Get-WinMintHeadlessWorkItem)
            $result = New-WinMintHeadlessResult -Result 'listed' -Reports ([pscustomobject]@{ work = $work })
            if ($Json) { Write-WinMintHeadlessJsonResult -Result $result } elseif (-not $Quiet) { $work | Format-Table buildId, phase, result, stale, workDir }
            return $result
        }
        if (-not [string]::IsNullOrWhiteSpace($CleanWork)) {
            $cleaned = @(Invoke-WinMintHeadlessCleanWork -Target $CleanWork)
            $result = New-WinMintHeadlessResult -Result 'cleaned' -Reports ([pscustomobject]@{ cleaned = $cleaned })
            if ($Json) { Write-WinMintHeadlessJsonResult -Result $result } elseif (-not $Quiet) { Write-WinMintHeadlessHumanResult -Result $result }
            return $result
        }

        if (-not [string]::IsNullOrWhiteSpace($NewProfile) -or -not [string]::IsNullOrWhiteSpace($OutProfile)) {
            $profilePath = if (-not [string]::IsNullOrWhiteSpace($NewProfile)) { $NewProfile } else { $OutProfile }
            $secret = Resolve-WinMintHeadlessSecret -Password $Password -PasswordPath $PasswordPath -PasswordEnvVar $PasswordEnvVar
            $buildProfile = New-WinMintHeadlessProfileFromFlags `
                -SourceIso $SourceIso `
                -Preset $Preset `
                -Architecture $Architecture `
                -ComputerName $ComputerName `
                -AccountName $AccountName `
                -AccountMode $AccountMode `
                -Password $secret.Password `
                -AutoLogon:$AutoLogon `
                -AutoWipeDisk:$AutoWipeDisk `
                -SetupOption $SetupOption `
                -EditionMode $EditionMode `
                -Edition $Edition `
                -DriverSource $DriverSource `
                -DriverPath $DriverPath `
                -TargetDevice $TargetDevice `
                -DriverPack $DriverPack `
                -ExportHostDrivers:$ExportHostDrivers `
                -TimeZoneId $TimeZoneId `
                -InputLocale $InputLocale `
                -SystemLocale $SystemLocale `
                -UILanguage $UILanguage `
                -UILanguageFallback $UILanguageFallback `
                -UserLocale $UserLocale `
                -Developer:$Developer `
                -Copilot:$Copilot `
                -KeepEdge:$KeepEdge `
                -KeepGaming:$KeepGaming `
                -KeepCopilot:$KeepCopilot `
                -DesktopUI:$DesktopUI `
                -Gaming:$Gaming `
                -DmaInterop:$DmaInterop `
                -NoDmaInterop:$NoDmaInterop `
                -Launcher $Launcher `
                -LiveInstallAudit:$LiveInstallAudit `
                -PhoneLink:$PhoneLink `
                -LocationServices:$LocationServices `
                -NoLocationServices:$NoLocationServices `
                -InstallWindhawk:$InstallWindhawk `
                -InstallYasb:$InstallYasb `
                -InstallKomorebi:$InstallKomorebi `
                -DryRun `
                -ValidateOnly `
                -TemplateMode
            $result = New-WinMintHeadlessProfileAuthoringResult -Path $profilePath -BuildProfile $buildProfile
            if ($Json) { Write-WinMintHeadlessJsonResult -Result $result } elseif (-not $Quiet) { Write-WinMintHeadlessHumanResult -Result $result }
            return $result
        }

        if (-not (Test-WinMintAdministrator)) {
            if (-not $AllowElevate) {
                throw 'WinMint headless runs require an elevated shell, including -DryRun, -ValidateOnly, UUP source prep, and driver checks. Re-run as Administrator or pass -AllowElevate for an explicit UAC prompt.'
            }
            $switches = @()
            foreach ($key in $BoundParameters.Keys) {
                if ($key -in @('Password', 'BoundParameters', 'AllowElevate')) { continue }
                $value = $BoundParameters[$key]
                if ($value -is [switch] -or $value -is [bool]) {
                    if ([bool]$value) { $switches += "-$key" }
                } elseif ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                    $switches += "-$key"
                    $switches += [string]$value
                }
            }
            $switches += '-AllowElevate'
            Invoke-SelfElevate -Switches $switches
            return
        }

        $warnings = [System.Collections.Generic.List[string]]::new()
        $secret = Resolve-WinMintHeadlessSecret -Password $Password -PasswordPath $PasswordPath -PasswordEnvVar $PasswordEnvVar
        if ($secret.UsedDeprecatedPassword) {
            $warnings.Add('Prefer -PasswordPath or -PasswordEnvVar for automation instead of inline -Password.')
        }

        Set-WinMintHeadlessJournalPhase -Phase 'Profile'
        $sourcePrep = $null
        if (-not [string]::IsNullOrWhiteSpace($UupDumpSource)) {
            $sourcePrep = Invoke-WinMintHeadlessSourcePrep -Path $UupDumpSource -Yes:$Yes -ValidateOnly:$ValidateOnly
            $script:WinMintSourcePrepResult = $sourcePrep
            if (-not [string]::IsNullOrWhiteSpace([string]$sourcePrep.GeneratedIso)) {
                $SourceIso = [string]$sourcePrep.GeneratedIso
            }
            elseif (-not $ValidateOnly -and -not $DryRun) {
                throw 'UUP Dump source prep did not produce a source ISO.'
            }
            $warnings.Add("UUP Dump source selected: $([IO.Path]::GetFileName($UupDumpSource))")
        }
        if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) {
            $profileSourceOverride = if (-not [string]::IsNullOrWhiteSpace($SourceIso)) { $SourceIso } else { $SourceIsoOverride }
            $buildProfile = Import-WinMintHeadlessBuildProfile -ProfilePath $ProfilePath -SourceIsoOverride $profileSourceOverride
        } else {
            $buildProfile = New-WinMintHeadlessProfileFromFlags `
                -SourceIso $SourceIso `
                -Preset $Preset `
                -Architecture $Architecture `
                -ComputerName $ComputerName `
                -AccountName $AccountName `
                -AccountMode $AccountMode `
                -Password $secret.Password `
                -AutoLogon:$AutoLogon `
                -AutoWipeDisk:$AutoWipeDisk `
                -SetupOption $SetupOption `
                -EditionMode $EditionMode `
                -Edition $Edition `
                -DriverSource $DriverSource `
                -DriverPath $DriverPath `
                -TargetDevice $TargetDevice `
                -DriverPack $DriverPack `
                -ExportHostDrivers:$ExportHostDrivers `
                -TimeZoneId $TimeZoneId `
                -InputLocale $InputLocale `
                -SystemLocale $SystemLocale `
                -UILanguage $UILanguage `
                -UILanguageFallback $UILanguageFallback `
                -UserLocale $UserLocale `
                -Developer:$Developer `
                -Copilot:$Copilot `
                -KeepEdge:$KeepEdge `
                -KeepGaming:$KeepGaming `
                -KeepCopilot:$KeepCopilot `
                -DesktopUI:$DesktopUI `
                -Gaming:$Gaming `
                -DmaInterop:$DmaInterop `
                -NoDmaInterop:$NoDmaInterop `
                -Launcher $Launcher `
                -LiveInstallAudit:$LiveInstallAudit `
                -PhoneLink:$PhoneLink `
                -LocationServices:$LocationServices `
                -NoLocationServices:$NoLocationServices `
                -InstallWindhawk:$InstallWindhawk `
                -InstallYasb:$InstallYasb `
                -InstallKomorebi:$InstallKomorebi `
                -DryRun:$DryRun `
                -ValidateOnly:$ValidateOnly
        }

        $sourceForState = [string](Get-WinMintProfileSetting (Get-WinMintProfileSetting $buildProfile 'source' @{}) 'isoPath' '')
        $script:WinMintHeadlessBuildId = New-WinMintHeadlessBuildId
        $state = New-WinMintHeadlessState -BuildId $script:WinMintHeadlessBuildId -ProfilePath $ProfilePath -SourceIso $sourceForState
        $script:WinMintHeadlessStatePath = Save-WinMintHeadlessState -State $state

        if ($ValidateOnly) {
            $allowProfileOnly = $DryRun -or ($null -ne $script:WinMintSourcePrepResult -and [string]::IsNullOrWhiteSpace([string]$buildProfile.source.isoPath))
            $result = Invoke-WinMintHeadlessValidateOnly -BuildProfile $buildProfile -BuildId $script:WinMintHeadlessBuildId -DryRun:$allowProfileOnly
            $result.warnings = @($warnings.ToArray() + @($result.warnings))
            Complete-WinMintHeadlessJournal -Result $result.result -Reports $result.reports -Warnings $result.warnings -Failures $result.failures
        } else {
            Set-WinMintHeadlessJournalPhase -Phase 'Preflight'
            $progress = {
                param($ProgressEvent)
                if ($NoProgress -or $Quiet -or $Json) { return }
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
                state = Get-WinMintHeadlessStatePath -BuildId $script:WinMintHeadlessBuildId
                sourcePrep = $script:WinMintSourcePrepResult
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
