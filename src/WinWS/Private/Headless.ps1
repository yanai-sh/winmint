#Requires -Version 7.3

$script:WinWSHeadlessBuildId = ''
$script:WinWSHeadlessStatePath = ''
$script:WinWSSourcePrepResult = $null

function Get-WinWSHeadlessStateRoot {
    Join-Path (Get-WinWSOutputDirectory) '.state'
}

function New-WinWSHeadlessBuildId {
    '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([Guid]::NewGuid().ToString('n').Substring(0, 8))
}

function Get-WinWSHeadlessStatePath {
    param([Parameter(Mandatory)][string]$BuildId)
    Join-Path (Get-WinWSHeadlessStateRoot) "$BuildId.json"
}

function Read-WinWSHeadlessState {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Save-WinWSHeadlessState {
    param([Parameter(Mandatory)][object]$State)

    $root = Get-WinWSHeadlessStateRoot
    $null = New-Item -ItemType Directory -Path $root -Force
    $path = Get-WinWSHeadlessStatePath -BuildId ([string]$State.buildId)
    $json = $State | ConvertTo-Json -Depth 16
    [System.IO.File]::WriteAllText($path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    return $path
}

function New-WinWSHeadlessState {
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
        marker = 'WinWSHeadlessState'
        buildId = $BuildId
        repositoryRoot = Get-WinWSRepositoryRoot
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

function Set-WinWSHeadlessJournalPhase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Phase,
        [string]$WorkDir,
        [string]$MountDir,
        [string]$IsoContents
    )

    if ([string]::IsNullOrWhiteSpace([string]$script:WinWSHeadlessStatePath)) { return }
    $state = Read-WinWSHeadlessState -Path $script:WinWSHeadlessStatePath
    if ($null -eq $state) { return }
    $state.phase = $Phase
    if (-not [string]::IsNullOrWhiteSpace($WorkDir)) { $state.workDir = $WorkDir }
    if (-not [string]::IsNullOrWhiteSpace($MountDir)) { $state.mountDir = $MountDir }
    if (-not [string]::IsNullOrWhiteSpace($IsoContents)) { $state.isoContents = $IsoContents }
    [void](Save-WinWSHeadlessState -State $state)
}

function Complete-WinWSHeadlessJournal {
    param(
        [Parameter(Mandatory)][string]$Result,
        [object]$Reports,
        [string[]]$Warnings = @(),
        [string[]]$Failures = @()
    )

    if ([string]::IsNullOrWhiteSpace([string]$script:WinWSHeadlessStatePath)) { return }
    $state = Read-WinWSHeadlessState -Path $script:WinWSHeadlessStatePath
    if ($null -eq $state) { return }
    $state.phase = 'Report'
    $state.completedAt = [DateTimeOffset]::Now.ToString('o')
    $state.result = $Result
    if ($Reports) { $state.reports = $Reports }
    $state.warnings = @($Warnings)
    $state.failures = @($Failures)
    [void](Save-WinWSHeadlessState -State $state)
}

function Write-WinWSHeadlessWorkMarker {
    param(
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string]$MountDir,
        [Parameter(Mandatory)][string]$IsoContents
    )

    if ([string]::IsNullOrWhiteSpace([string]$script:WinWSHeadlessBuildId)) { return }
    $marker = [pscustomobject]@{
        marker = 'WinWSHeadlessWork'
        buildId = $script:WinWSHeadlessBuildId
        processId = $PID
        createdAt = [DateTimeOffset]::Now.ToString('o')
        mountDir = $MountDir
        isoContents = $IsoContents
    }
    $path = Join-Path $WorkDir '.winws-work.json'
    $json = $marker | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Test-WinWSProcessRunning {
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return $false }
    $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Get-WinWSHeadlessWorkItem {
    $items = [System.Collections.Generic.List[object]]::new()
    $root = Get-WinWSHeadlessStateRoot
    if (Test-Path -LiteralPath $root) {
        foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.json' -File -ErrorAction SilentlyContinue) {
            $state = Read-WinWSHeadlessState -Path $file.FullName
            if ($null -eq $state -or [string]$state.marker -ne 'WinWSHeadlessState') { continue }
            $running = Test-WinWSProcessRunning -ProcessId ([int]$state.processId)
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

function Invoke-WinWSHeadlessCleanWork {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Target)

    $items = @(Get-WinWSHeadlessWorkItem)
    if ($Target -eq 'AllStale') {
        $items = @($items | Where-Object { $_.stale })
    } else {
        $items = @($items | Where-Object { $_.buildId -eq $Target })
    }

    $cleaned = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $items) {
        if ($item.processRunning) { continue }
        $workDir = [string]$item.workDir
        $markerPath = if ([string]::IsNullOrWhiteSpace($workDir)) { '' } else { Join-Path $workDir '.winws-work.json' }
        $markerOwned = -not [string]::IsNullOrWhiteSpace($markerPath) -and (Test-Path -LiteralPath $markerPath)
        if ($markerOwned -and -not [string]::IsNullOrWhiteSpace([string]$item.mountDir)) {
            try {
                if (Test-WinWSMountedImagePath -Path ([string]$item.mountDir)) {
                    Dismount-WindowsImage -Path ([string]$item.mountDir) -Discard -ErrorAction SilentlyContinue | Out-Null
                }
            } catch {
                Write-Verbose "Could not discard stale mount '$($item.mountDir)': $($_.Exception.Message)"
            }
        }
        if ($markerOwned -and (Test-Path -LiteralPath $workDir)) {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        $state = Read-WinWSHeadlessState -Path ([string]$item.statePath)
        if ($state) {
            $state.result = 'cleaned'
            $state.phase = 'Cleanup'
            $state.completedAt = [DateTimeOffset]::Now.ToString('o')
            [void](Save-WinWSHeadlessState -State $state)
        }
        $cleaned.Add($item) | Out-Null
    }
    return $cleaned.ToArray()
}

function Assert-WinWSHeadlessParameterSet {
    param([Parameter(Mandatory)][hashtable]$BoundParameters)

    if ($BoundParameters.ContainsKey('ListWork') -and $BoundParameters.ContainsKey('CleanWork')) {
        throw 'Use either -ListWork or -CleanWork, not both.'
    }
    if ($BoundParameters.ContainsKey('SourceIso') -and $BoundParameters.ContainsKey('UupDumpZip')) {
        throw 'Use either -SourceIso or -UupDumpZip, not both.'
    }
    if ($BoundParameters.ContainsKey('SourceIsoOverride') -and -not $BoundParameters.ContainsKey('ProfilePath')) {
        throw '-SourceIsoOverride is only valid with -ProfilePath. Use -SourceIso for flag-built profiles.'
    }
    if ($BoundParameters.ContainsKey('DriverPack') -and
        ($BoundParameters.ContainsKey('DriverSource') -or $BoundParameters.ContainsKey('DriverPath') -or $BoundParameters.ContainsKey('ExportHostDrivers'))) {
        throw 'Use -DriverPack or legacy -DriverSource/-DriverPath/-ExportHostDrivers, not both.'
    }
    if ($BoundParameters.ContainsKey('LocationServices') -and $BoundParameters.ContainsKey('NoLocationServices')) {
        throw 'Use either -LocationServices or -NoLocationServices, not both.'
    }
    $secretInputs = @('Password', 'PasswordPath', 'PasswordEnvVar') | Where-Object {
        $BoundParameters.ContainsKey($_) -and -not [string]::IsNullOrWhiteSpace([string]$BoundParameters[$_])
    }
    if (@($secretInputs).Count -gt 1) {
        throw 'Use only one password input: -Password, -PasswordPath, or -PasswordEnvVar.'
    }
    if ($BoundParameters.ContainsKey('ProfilePath')) {
        $allowed = @(
            'ProfilePath', 'SourceIsoOverride', 'UupDumpZip', 'Yes', 'ValidateOnly', 'Json', 'NoProgress', 'Quiet',
            'DryRun', 'AllowElevate', 'Verbose', 'Debug', 'ErrorAction', 'WarningAction',
            'InformationAction', 'ProgressAction', 'ErrorVariable', 'WarningVariable',
            'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable'
        )
        $mixed = @($BoundParameters.Keys | Where-Object { $_ -notin $allowed })
        if ($mixed.Count -gt 0) {
            throw "-ProfilePath is source of truth; remove mixed profile flags: $($mixed -join ', ')."
        }
    }
}

function Resolve-WinWSHeadlessSecret {
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

function Import-WinWSHeadlessBuildProfile {
    param(
        [Parameter(Mandatory)][string]$ProfilePath,
        [string]$SourceIsoOverride = ''
    )

    if (-not (Test-Path -LiteralPath $ProfilePath)) { throw "Profile not found: $ProfilePath" }
    $buildProfile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
    if (-not [string]::IsNullOrWhiteSpace($SourceIsoOverride)) {
        $buildProfile.source.isoPath = $SourceIsoOverride
    }
    Assert-WinWSBuildProfile -BuildProfile $buildProfile
    return $buildProfile
}

function Resolve-WinWSHeadlessDriverIntent {
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

function Resolve-WinWSHeadlessProfileGroups {
    param(
        [ValidateSet('Minimal', 'CopilotPlus')][string]$SetupOption = 'Minimal',
        [switch]$Developer,
        [switch]$Copilot,
        [switch]$DesktopUI,
        [switch]$Gaming
    )

    $groups = [System.Collections.Generic.List[string]]::new()
    $groups.Add('Minimal') | Out-Null
    if ($Developer) { $groups.Add('Developer') | Out-Null }
    if ($Copilot -or $SetupOption -eq 'CopilotPlus') { $groups.Add('CopilotPlus') | Out-Null }
    if ($Gaming) { $groups.Add('Gaming') | Out-Null }
    if ($DesktopUI) { $groups.Add('DesktopUI') | Out-Null }
    @($groups.ToArray() | Select-Object -Unique)
}

function New-WinWSHeadlessProfileFromFlags {
    [CmdletBinding()]
    param(
        [string]$SourceIso,
        [string]$Architecture,
        [string]$ComputerName = 'WinWS',
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
        [switch]$LocationServices,
        [switch]$NoLocationServices,
        [switch]$InstallWindhawk,
        [switch]$InstallYasb,
        [switch]$InstallKomorebi,
        [switch]$DryRun,
        [switch]$ValidateOnly
    )

    if (-not $DryRun -and -not $ValidateOnly -and [string]::IsNullOrWhiteSpace($SourceIso)) {
        throw 'SourceIso is required for headless builds. Use -ProfilePath or -DryRun for profile-only validation.'
    }
    if ($AutoLogon -and [string]::IsNullOrWhiteSpace($Password)) {
        throw 'Autologon requires an included account password.'
    }
    if ($AccountMode -eq 'MicrosoftOobe') {
        $Password = ''
        $AutoLogon = $false
    }

    $drivers = Resolve-WinWSHeadlessDriverIntent `
        -TargetDevice $TargetDevice `
        -DriverPack $DriverPack `
        -DriverSource $DriverSource `
        -DriverPath $DriverPath `
        -ExportHostDrivers:$ExportHostDrivers

    $profileGroups = @(Resolve-WinWSHeadlessProfileGroups `
        -SetupOption $SetupOption `
        -Developer:$Developer `
        -Copilot:$Copilot `
        -DesktopUI:$DesktopUI `
        -Gaming:$Gaming)

    New-WinWSBuildProfile -Settings @{
        Profile = 'Minimal'
        ProfileGroups = @($profileGroups)
        ISOPath = $SourceIso
        Architecture = $Architecture
        TargetDevice = $TargetDevice
        ComputerName = $ComputerName
        AccountName = $AccountName
        AccountMode = $AccountMode
        Password = $Password
        AutoLogon = [bool]$AutoLogon
        AutoWipeDisk = [bool]$AutoWipeDisk
        SetupOption = if ($profileGroups -contains 'CopilotPlus') { 'CopilotPlus' } else { $SetupOption }
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
        DesktopUiDefault = [bool]$DesktopUI
        InstallWindhawk = [bool]$InstallWindhawk
        InstallYasb = [bool]$InstallYasb
        InstallKomorebi = [bool]$InstallKomorebi
        PrivLocation = [bool]$NoLocationServices
    } -IncludeSecrets:($AccountMode -eq 'Local' -and -not [string]::IsNullOrWhiteSpace($Password))
}

function New-WinWSHeadlessResult {
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

function Write-WinWSHeadlessJsonResult {
    param([Parameter(Mandatory)][object]$Result)
    [Console]::Out.WriteLine(($Result | ConvertTo-Json -Depth 16 -Compress))
}

function Write-WinWSHeadlessHumanResult {
    param([Parameter(Mandatory)][object]$Result)
    $status = [string]$Result.result
    if ($status -in @('success', 'dry-run', 'cleaned', 'listed')) {
        Write-Host "WinWS headless result: $status"
    } else {
        Write-Host "WinWS headless result: $status"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Result.buildId)) { Write-Host "Build ID: $($Result.buildId)" }
    if (-not [string]::IsNullOrWhiteSpace([string]$Result.outputIso)) { Write-Host "Output ISO: $($Result.outputIso)" }
    foreach ($warning in @($Result.warnings)) { Write-Warning $warning }
    foreach ($failure in @($Result.failures)) { Write-Error $failure -ErrorAction Continue }
}

function Invoke-WinWSHeadlessValidateOnly {
    param(
        [Parameter(Mandatory)]$BuildProfile,
        [Parameter(Mandatory)][string]$BuildId,
        [switch]$DryRun
    )

    Set-WinWSHeadlessJournalPhase -Phase 'Preflight'
    $config = New-WinWSBuildConfig -BuildProfile $BuildProfile
    $pre = Test-WinWSBuildPrerequisite -Config $config -AllowMissingSourceIso:$DryRun
    $report = New-WinWSBuildReport -Config $config -DetectedArchitecture $config.Architecture -Warnings $pre.Warnings -Failures $pre.Failures
    $paths = Save-WinWSBuildReport -Report $report
    $reports = [pscustomobject]@{
        json = $paths.Json
        markdown = $paths.Markdown
        manifest = ''
        state = Get-WinWSHeadlessStatePath -BuildId $BuildId
        sourcePrep = $script:WinWSSourcePrepResult
    }
    $resultName = if ($pre.Passed) { 'success' } else { 'validation-failed' }
    Complete-WinWSHeadlessJournal -Result $resultName -Reports $reports -Warnings $pre.Warnings -Failures $pre.Failures
    New-WinWSHeadlessResult -Result $resultName -BuildId $BuildId -Reports $reports -Warnings $pre.Warnings -Failures $pre.Failures
}

function Invoke-WinWSHeadlessCli {
    [CmdletBinding()]
    param(
        [hashtable]$BoundParameters,
        [string]$ProfilePath,
        [string]$SourceIso,
        [string]$UupDumpZip,
        [string]$SourceIsoOverride,
        [string]$Architecture,
        [string]$ComputerName = 'WinWS',
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
        [switch]$ListWork,
        [string]$CleanWork
    )

    try {
        Assert-WinWSHeadlessParameterSet -BoundParameters $BoundParameters
        if ($ListWork) {
            $work = @(Get-WinWSHeadlessWorkItem)
            $result = New-WinWSHeadlessResult -Result 'listed' -Reports ([pscustomobject]@{ work = $work })
            if ($Json) { Write-WinWSHeadlessJsonResult -Result $result } elseif (-not $Quiet) { $work | Format-Table buildId, phase, result, stale, workDir }
            return $result
        }
        if (-not [string]::IsNullOrWhiteSpace($CleanWork)) {
            $cleaned = @(Invoke-WinWSHeadlessCleanWork -Target $CleanWork)
            $result = New-WinWSHeadlessResult -Result 'cleaned' -Reports ([pscustomobject]@{ cleaned = $cleaned })
            if ($Json) { Write-WinWSHeadlessJsonResult -Result $result } elseif (-not $Quiet) { Write-WinWSHeadlessHumanResult -Result $result }
            return $result
        }

        if (-not (Test-WinWSAdministrator)) {
            if (-not $AllowElevate) {
                throw 'WinWS headless runs require an elevated shell, including -DryRun, -ValidateOnly, UUP source prep, and driver checks. Re-run as Administrator or pass -AllowElevate for an explicit UAC prompt.'
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
        $secret = Resolve-WinWSHeadlessSecret -Password $Password -PasswordPath $PasswordPath -PasswordEnvVar $PasswordEnvVar
        if ($secret.UsedDeprecatedPassword) {
            $warnings.Add('-Password is accepted for compatibility but is not recommended for automation. Prefer -PasswordPath or -PasswordEnvVar.')
        }

        Set-WinWSHeadlessJournalPhase -Phase 'Profile'
        $sourcePrep = $null
        if (-not [string]::IsNullOrWhiteSpace($UupDumpZip)) {
            $sourcePrep = Invoke-WinWSUupDumpSourcePrep -UupDumpZip $UupDumpZip -Yes:$Yes -ValidateOnly:$ValidateOnly
            $script:WinWSSourcePrepResult = $sourcePrep
            if (-not [string]::IsNullOrWhiteSpace([string]$sourcePrep.GeneratedIso)) {
                $SourceIso = [string]$sourcePrep.GeneratedIso
            }
            elseif (-not $ValidateOnly -and -not $DryRun) {
                throw 'UUP Dump source prep did not produce a source ISO.'
            }
            $warnings.Add("UUP Dump source selected: $([IO.Path]::GetFileName($UupDumpZip))")
        }
        if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) {
            $profileSourceOverride = if (-not [string]::IsNullOrWhiteSpace($SourceIso)) { $SourceIso } else { $SourceIsoOverride }
            $buildProfile = Import-WinWSHeadlessBuildProfile -ProfilePath $ProfilePath -SourceIsoOverride $profileSourceOverride
        } else {
            $buildProfile = New-WinWSHeadlessProfileFromFlags `
                -SourceIso $SourceIso `
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
                -DesktopUI:$DesktopUI `
                -Gaming:$Gaming `
                -LocationServices:$LocationServices `
                -NoLocationServices:$NoLocationServices `
                -InstallWindhawk:$InstallWindhawk `
                -InstallYasb:$InstallYasb `
                -InstallKomorebi:$InstallKomorebi `
                -DryRun:$DryRun `
                -ValidateOnly:$ValidateOnly
        }

        $sourceForState = [string](Get-WinWSProfileSetting (Get-WinWSProfileSetting $buildProfile 'source' @{}) 'isoPath' '')
        $script:WinWSHeadlessBuildId = New-WinWSHeadlessBuildId
        $state = New-WinWSHeadlessState -BuildId $script:WinWSHeadlessBuildId -ProfilePath $ProfilePath -SourceIso $sourceForState
        $script:WinWSHeadlessStatePath = Save-WinWSHeadlessState -State $state

        if ($ValidateOnly) {
            $allowProfileOnly = $DryRun -or ($null -ne $script:WinWSSourcePrepResult -and [string]::IsNullOrWhiteSpace([string]$buildProfile.source.isoPath))
            $result = Invoke-WinWSHeadlessValidateOnly -BuildProfile $buildProfile -BuildId $script:WinWSHeadlessBuildId -DryRun:$allowProfileOnly
            $result.warnings = @($warnings.ToArray() + @($result.warnings))
            Complete-WinWSHeadlessJournal -Result $result.result -Reports $result.reports -Warnings $result.warnings -Failures $result.failures
        } else {
            Set-WinWSHeadlessJournalPhase -Phase 'Preflight'
            $progress = {
                param($ProgressEvent)
                if ($NoProgress -or $Quiet -or $Json) { return }
                $level = [string]$ProgressEvent.Level
                $message = [string]$ProgressEvent.Message
                if ($level -eq 'Error') { Write-Error $message -ErrorAction Continue }
                elseif ($level -eq 'Warn') { Write-Warning $message }
                else { Write-Host $message }
            }
            $build = Start-WinWSBuild -BuildProfile $buildProfile -DryRun:$DryRun -ProgressHandler $progress
            $reports = [pscustomobject]@{
                json = $build.Paths.Json
                markdown = $build.Paths.Markdown
                manifest = Join-Path (Get-WinWSOutputDirectory) 'WinWS-BuildManifest.json'
                state = Get-WinWSHeadlessStatePath -BuildId $script:WinWSHeadlessBuildId
                sourcePrep = $script:WinWSSourcePrepResult
            }
            $resultName = if ($DryRun) { 'dry-run' } else { 'success' }
            $outputIso = if ($DryRun) { '' } else { [string]$build.OutputPath }
            $result = New-WinWSHeadlessResult -Result $resultName -BuildId $script:WinWSHeadlessBuildId -OutputIso $outputIso -Reports $reports -Warnings $warnings.ToArray()
            Complete-WinWSHeadlessJournal -Result $result.result -Reports $reports -Warnings $result.warnings
        }
    }
    catch {
        $failure = $_.Exception.Message
        $buildId = [string]$script:WinWSHeadlessBuildId
        $reports = [pscustomobject]@{}
        if (-not [string]::IsNullOrWhiteSpace($buildId)) {
            $reports = [pscustomobject]@{ state = Get-WinWSHeadlessStatePath -BuildId $buildId }
            Complete-WinWSHeadlessJournal -Result 'failed' -Reports $reports -Failures @($failure)
        }
        $result = New-WinWSHeadlessResult -Result 'failed' -BuildId $buildId -Reports $reports -Failures @($failure)
        if ($Json) { Write-WinWSHeadlessJsonResult -Result $result } elseif (-not $Quiet) { Write-WinWSHeadlessHumanResult -Result $result }
        return $result
    }

    if ($Json) { Write-WinWSHeadlessJsonResult -Result $result } elseif (-not $Quiet) { Write-WinWSHeadlessHumanResult -Result $result }
    return $result
}
