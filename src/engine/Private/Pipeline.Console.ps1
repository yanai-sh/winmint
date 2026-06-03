#Requires -Version 7.3

function Resolve-WinMintConsoleIsoPath {
    param([string]$DefaultPath)

    if (-not [string]::IsNullOrWhiteSpace($DefaultPath) -and (Test-Path -LiteralPath $DefaultPath)) {
        return (Resolve-Path -LiteralPath $DefaultPath).Path
    }

    $root = Get-WinMintRepositoryRoot
    $isoFiles = @(Get-ChildItem -LiteralPath $root -Filter '*.iso' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($isoFiles.Count -eq 1) { return $isoFiles[0].FullName }
    if ($isoFiles.Count -gt 1) {
        $choice = Read-SpectreSelection `
            -Message '[bold]Source Windows ISO[/]' `
            -Choices @($isoFiles.FullName) `
            -EnableSearch `
            -PageSize $script:Win11IsoSpectrePageSizeList
        return [string]$choice
    }

    while ($true) {
        $typed = Read-SpectrePlainText -Message '[bold]Path to Windows 11 ISO[/]' -AllowEmpty
        if ([string]::IsNullOrWhiteSpace($typed)) { throw 'No ISO path was provided.' }
        if (Test-Path -LiteralPath $typed) { return (Resolve-Path -LiteralPath $typed).Path }
        LogWarn "ISO not found: $typed"
    }
}

function Resolve-WinMintConsoleDriverSelection {
    param([switch]$ExportHostDrivers)

    if ($ExportHostDrivers) { return [pscustomobject]@{ Source = 'Host'; Path = '' } }
    $none = 'No extra drivers'
    $hostChoice = 'Mirror drivers from this PC'
    $custom = 'Use a driver .msi/.inf file or folder path'
    $choice = Read-SpectreSelection `
        -Message '[bold]Additional drivers[/]' `
        -Choices @($none, $hostChoice, $custom) `
        -PageSize 4

    if ($choice -eq $hostChoice) { return [pscustomobject]@{ Source = 'Host'; Path = '' } }
    if ($choice -ne $custom) { return [pscustomobject]@{ Source = 'None'; Path = '' } }

    while ($true) {
        $path = Read-SpectrePlainText `
            -Message '[bold]Driver .msi/.inf file or driver folder path[/]' `
            -AllowEmpty
        if ([string]::IsNullOrWhiteSpace($path)) { return [pscustomobject]@{ Source = 'None'; Path = '' } }
        if (Test-Win11IsoDriverPath -Path $path) {
            return [pscustomobject]@{ Source = 'Custom'; Path = (Resolve-Path -LiteralPath $path).Path }
        }
        LogWarn 'Driver path must be a .inf file, .msi file, or folder containing driver payloads.'
    }
}

function Test-WinMintConsoleNonInteractive {
    [Console]::IsInputRedirected -or [Console]::IsOutputRedirected
}

function Import-WinMintConsoleBuildProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Build profile not found: $Path"
    }

    $buildProfile = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    Assert-WinMintBuildProfile -BuildProfile $buildProfile
    return $buildProfile
}

function New-WinMintConsoleHeadlessProfile {
    [CmdletBinding()]
    param(
        [string]$SourceIso,
        [string]$Architecture,
        [string]$ComputerName = 'WinMint',
        [string]$AccountName = 'dev',
        [ValidateSet('Local', 'MicrosoftOobe')]
        [string]$AccountMode = 'Local',
        [string]$Password = '',
        [switch]$AutoLogon,
        [switch]$AutoWipeDisk,
        [ValidateSet('Minimal', 'CopilotPlus')]
        [string]$SetupOption = 'Minimal',
        [ValidateSet('TargetLicense', 'Fixed')]
        [string]$EditionMode = 'TargetLicense',
        [string]$Edition = '',
        [ValidateSet('None', 'Host', 'Custom')]
        [string]$DriverSource = 'None',
        [string]$DriverPath = '',
        [string]$TimeZoneId,
        [string]$InputLocale,
        [string]$SystemLocale,
        [string]$UILanguage,
        [string]$UILanguageFallback,
        [string]$UserLocale,
        [switch]$ExportHostDrivers,
        [switch]$InstallWindhawk,
        [switch]$InstallYasb,
        [switch]$InstallKomorebi,
        [switch]$DryRun
    )

    if ($ExportHostDrivers) { $DriverSource = 'Host' }
    if ($DriverSource -eq 'Host') { $DriverPath = '' }

    $resolvedIso = ''
    if (-not [string]::IsNullOrWhiteSpace($SourceIso)) {
        if (-not (Test-Path -LiteralPath $SourceIso -PathType Leaf)) {
            throw "Source ISO not found: $SourceIso"
        }
        $resolvedIso = (Resolve-Path -LiteralPath $SourceIso).Path
    }
    elseif (-not $DryRun) {
        throw 'Headless builds require -SourceIso or -ProfilePath. Use -DryRun to validate defaults without an ISO.'
    }

    if ([string]::IsNullOrWhiteSpace($Architecture)) {
        if (-not [string]::IsNullOrWhiteSpace($resolvedIso)) {
            $Architecture = Get-ArchitectureFromFilename -Filename $resolvedIso
            if (-not $Architecture) { $Architecture = Get-WinMintIsoArchitectureHint -Path $resolvedIso }
        }
        if (-not $Architecture) { $Architecture = 'amd64' }
    }

    if ($DriverSource -eq 'Custom') {
        if ([string]::IsNullOrWhiteSpace($DriverPath)) {
            throw 'Custom driver source requires -DriverPath.'
        }
        if (-not (Test-Win11IsoDriverPath -Path $DriverPath)) {
            throw 'Driver path must be a .inf file, .msi file, or folder containing driver payloads.'
        }
        $DriverPath = (Resolve-Path -LiteralPath $DriverPath).Path
    }

    if ($AccountMode -eq 'MicrosoftOobe') {
        $Password = ''
        $AutoLogon = $false
    }
    elseif ($AutoLogon -and [string]::IsNullOrWhiteSpace($Password)) {
        throw 'Autologon requires -Password in headless mode.'
    }

    $regional = Get-HostUnattendRegionalDefault
    if ($TimeZoneId) { $regional.TimeZoneId = $TimeZoneId }
    if ($InputLocale) { $regional.InputLocale = $InputLocale }
    if ($SystemLocale) { $regional.SystemLocale = $SystemLocale }
    if ($UILanguage) { $regional.UILanguage = $UILanguage }
    if ($UILanguageFallback) { $regional.UILanguageFallback = $UILanguageFallback }
    if ($UserLocale) { $regional.UserLocale = $UserLocale }
    New-WinMintBuildProfile -Settings @{
        Profile = 'Developer'
        SetupOption = $SetupOption
        ISOPath = $resolvedIso
        Architecture = $Architecture
        EditionMode = $EditionMode
        Edition = $Edition
        ComputerName = $ComputerName
        AccountName = $AccountName
        AccountMode = $AccountMode
        Password = $Password
        AutoLogon = [bool]$AutoLogon
        AutoWipeDisk = [bool]$AutoWipeDisk
        CursorPackKind = $script:Win11IsoDefaultCursorPackKind
        TimeZoneId = $regional.TimeZoneId
        InputLocale = $regional.InputLocale
        SystemLocale = $regional.SystemLocale
        UILanguage = $regional.UILanguage
        UILanguageFallback = $regional.UILanguageFallback
        UserLocale = $regional.UserLocale
        HomeLocationGeoId = $regional.HomeLocationGeoId
        DriverSource = $DriverSource
        DriverPath = $DriverPath
        ExportHostDrivers = ($DriverSource -eq 'Host')
        InstallWindhawk = [bool]$InstallWindhawk
        InstallYasb = [bool]$InstallYasb
        InstallKomorebi = [bool]$InstallKomorebi
    } -IncludeSecrets
}

function New-WinMintConsoleDryRunProfile {
    [CmdletBinding()]
    param(
        [switch]$InstallWindhawk,
        [switch]$InstallYasb,
        [switch]$InstallKomorebi
    )

    $regional = Get-HostUnattendRegionalDefault
    New-WinMintBuildProfile -Settings @{
        Profile = 'Developer'
        ISOPath = ''
        Architecture = 'amd64'
        EditionMode = 'TargetLicense'
        Edition = ''
        ComputerName = 'WinMint'
        AccountName = 'dev'
        Password = ''
        AutoLogon = $false
        AutoWipeDisk = $false
        CursorPackKind = $script:Win11IsoDefaultCursorPackKind
        TimeZoneId = $regional.TimeZoneId
        InputLocale = $regional.InputLocale
        SystemLocale = $regional.SystemLocale
        UILanguage = $regional.UILanguage
        UILanguageFallback = $regional.UILanguageFallback
        UserLocale = $regional.UserLocale
        HomeLocationGeoId = $regional.HomeLocationGeoId
        DriverSource = 'None'
        DriverPath = ''
        ExportHostDrivers = $false
        InstallWindhawk = [bool]$InstallWindhawk
        InstallYasb = [bool]$InstallYasb
        InstallKomorebi = [bool]$InstallKomorebi
    } -IncludeSecrets
}

function New-WinMintConsoleBuildConfig {
    [CmdletBinding()]
    param(
        [switch]$DryRun,
        [switch]$ExportHostDrivers,
        [switch]$InstallWindhawk,
        [switch]$InstallYasb,
        [switch]$InstallKomorebi
    )

    Initialize-ConsoleUtf8ForSpectre
    Initialize-Spectre
    Show-BuildWelcomeHero

    $sourceIso = Resolve-WinMintConsoleIsoPath
    $archHint = Get-ArchitectureFromFilename -Filename $sourceIso
    if (-not $archHint) { $archHint = Get-WinMintIsoArchitectureHint -Path $sourceIso }
    if (-not $archHint) { $archHint = 'amd64' }

    Write-SectionHeader 'Identity'
    $computerName = Read-SpectrePlainText -Message '[bold]Computer name[/]' -DefaultAnswer 'WinMint' -AllowEmpty
    if ([string]::IsNullOrWhiteSpace($computerName)) { $computerName = 'WinMint' }
    $accountName = Read-SpectrePlainText -Message '[bold]Local admin account name[/]' -DefaultAnswer 'dev' -AllowEmpty
    if ([string]::IsNullOrWhiteSpace($accountName)) { $accountName = 'dev' }
    $password = Read-SpectreSecretText -Message '[bold]Local account password[/] [dim](empty allowed)[/]'
    $autoLogon = $false
    if (-not [string]::IsNullOrWhiteSpace($password)) {
        $autoLogon = [bool](Read-SpectreConfirm -Message '[bold]Enable autologon for this account?[/]' -DefaultAnswer n)
    }

    $regional = Get-HostUnattendRegionalDefault
    $mirrorRegional = [bool](Read-SpectreConfirm -Message '[bold]Mirror this PC regional settings?[/]' -DefaultAnswer y)
    if (-not $mirrorRegional) { $regional = Invoke-GoldImageRegionalPrompt }

    Write-SectionHeader 'Windows image'
    Log 'Edition mode: target license. Windows Setup will use the target device firmware key when available.'
    $autoWipeDisk = [bool](Read-SpectreConfirm -Message '[bold red]Unattended wipe primary disk during Setup?[/]' -DefaultAnswer n)
    $drivers = Resolve-WinMintConsoleDriverSelection -ExportHostDrivers:$ExportHostDrivers

    if (-not ($InstallWindhawk -or $InstallYasb -or $InstallKomorebi)) {
        Write-SectionHeader 'Desktop layers'
        Log 'Standard Windows desktop is the default. Optional layers are additive.'
        $InstallWindhawk = [bool](Read-SpectreConfirm -Message '[bold]Add Windhawk dock preset?[/]' -DefaultAnswer n)
        $InstallYasb = [bool](Read-SpectreConfirm -Message '[bold]Add YASB top bar preset?[/]' -DefaultAnswer n)
        $InstallKomorebi = [bool](Read-SpectreConfirm -Message '[bold]Add Komorebi tiling preset?[/]' -DefaultAnswer n)
    }

    $settings = @{
        ISOPath = $sourceIso
        Architecture = $archHint
        EditionMode = 'TargetLicense'
        Edition = ''
        ComputerName = $computerName
        AccountName = $accountName
        Password = $password
        AutoLogon = $autoLogon
        AutoWipeDisk = $autoWipeDisk
        CursorPackKind = $script:Win11IsoDefaultCursorPackKind
        TimeZoneId = $regional.TimeZoneId
        InputLocale = $regional.InputLocale
        SystemLocale = $regional.SystemLocale
        UILanguage = $regional.UILanguage
        UILanguageFallback = $regional.UILanguageFallback
        UserLocale = $regional.UserLocale
        HomeLocationGeoId = $regional.HomeLocationGeoId
        DriverSource = $drivers.Source
        DriverPath = $drivers.Path
        ExportHostDrivers = ($drivers.Source -eq 'Host')
        InstallWindhawk = [bool]$InstallWindhawk
        InstallYasb = [bool]$InstallYasb
        InstallKomorebi = [bool]$InstallKomorebi
    }

    $buildProfile = New-WinMintBuildProfile -Settings $settings -IncludeSecrets
    $layers = @($buildProfile.desktop.layers)
    $review = Show-BuildConfigurationSummaryAndConfirm `
        -SourceIsoPath ([string]$buildProfile.source.isoPath) `
        -TargetArchitecture ([string]$buildProfile.source.architecture) `
        -ComputerName ([string]$buildProfile.identity.computerName) `
        -UserName ([string]$buildProfile.identity.accountName) `
        -AccountPasswordProvided:($buildProfile.identity.passwordIncluded -and -not [string]::IsNullOrWhiteSpace([string]$buildProfile.identity.password)) `
        -AutoLogon:([bool]$buildProfile.identity.autoLogon) `
        -EditionName $(if ([string]$buildProfile.target.editionMode -eq 'Fixed') { [string]$buildProfile.target.edition } else { 'Target license' }) `
        -AutoWipeDisk:([string]$buildProfile.target.diskMode -eq 'AutoWipeDisk0') `
        -MirrorHostRegional:$mirrorRegional `
        -TimeZoneId ([string]$buildProfile.regional.timeZoneId) `
        -InputLocale ([string]$buildProfile.regional.inputLocale) `
        -UILanguage ([string]$buildProfile.regional.uiLanguage) `
        -UserLocale ([string]$buildProfile.regional.userLocale) `
        -CursorPackKind ([string]$buildProfile.desktop.cursorPack) `
        -DriverMode ([string]$buildProfile.drivers.source) `
        -DriverPath ([string]$buildProfile.drivers.path) `
        -InstallWindhawk:($layers -contains 'windhawk') `
        -InstallYasb:($layers -contains 'yasb') `
        -InstallKomorebi:($layers -contains 'komorebi') `
        -DryRun:$DryRun

    [pscustomobject]@{ Profile = $buildProfile; Review = $review }
}

function Invoke-WinMintConsoleBuild {
    [CmdletBinding()]
    param(
        [string]$ProfilePath,
        [string]$SourceIso,
        [string]$Architecture,
        [string]$ComputerName = 'WinMint',
        [string]$AccountName = 'dev',
        [ValidateSet('Local', 'MicrosoftOobe')]
        [string]$AccountMode = 'Local',
        [string]$Password = '',
        [switch]$AutoLogon,
        [switch]$AutoWipeDisk,
        [ValidateSet('Minimal', 'CopilotPlus')]
        [string]$SetupOption = 'Minimal',
        [ValidateSet('TargetLicense', 'Fixed')]
        [string]$EditionMode = 'TargetLicense',
        [string]$Edition = '',
        [ValidateSet('None', 'Host', 'Custom')]
        [string]$DriverSource = 'None',
        [string]$DriverPath = '',
        [string]$TimeZoneId,
        [string]$InputLocale,
        [string]$SystemLocale,
        [string]$UILanguage,
        [string]$UILanguageFallback,
        [string]$UserLocale,
        [switch]$NonInteractive,
        [switch]$DryRun,
        [switch]$ExportHostDrivers,
        [switch]$InstallWindhawk,
        [switch]$InstallYasb,
        [switch]$InstallKomorebi
    )

    if ($ProfilePath -and (Test-Path -LiteralPath $ProfilePath)) {
        $ProfilePath = (Resolve-Path -LiteralPath $ProfilePath).Path
    }
    if ($SourceIso -and (Test-Path -LiteralPath $SourceIso)) {
        $SourceIso = (Resolve-Path -LiteralPath $SourceIso).Path
    }
    if ($DriverPath -and (Test-Path -LiteralPath $DriverPath)) {
        $DriverPath = (Resolve-Path -LiteralPath $DriverPath).Path
    }

    $switches = @()
    if ($ProfilePath) { $switches += @('-ProfilePath', $ProfilePath) }
    if ($SourceIso) { $switches += @('-SourceIso', $SourceIso) }
    if ($Architecture) { $switches += @('-Architecture', $Architecture) }
    if ($ComputerName) { $switches += @('-ComputerName', $ComputerName) }
    if ($AccountName) { $switches += @('-AccountName', $AccountName) }
    if ($AccountMode) { $switches += @('-AccountMode', $AccountMode) }
    if ($Password) { $switches += @('-Password', $Password) }
    if ($AutoLogon) { $switches += '-AutoLogon' }
    if ($AutoWipeDisk) { $switches += '-AutoWipeDisk' }
    if ($SetupOption) { $switches += @('-SetupOption', $SetupOption) }
    if ($EditionMode) { $switches += @('-EditionMode', $EditionMode) }
    if ($Edition) { $switches += @('-Edition', $Edition) }
    if ($DriverSource) { $switches += @('-DriverSource', $DriverSource) }
    if ($DriverPath) { $switches += @('-DriverPath', $DriverPath) }
    if ($TimeZoneId) { $switches += @('-TimeZoneId', $TimeZoneId) }
    if ($InputLocale) { $switches += @('-InputLocale', $InputLocale) }
    if ($SystemLocale) { $switches += @('-SystemLocale', $SystemLocale) }
    if ($UILanguage) { $switches += @('-UILanguage', $UILanguage) }
    if ($UILanguageFallback) { $switches += @('-UILanguageFallback', $UILanguageFallback) }
    if ($UserLocale) { $switches += @('-UserLocale', $UserLocale) }
    if ($NonInteractive) { $switches += '-NonInteractive' }
    if ($DryRun) { $switches += '-DryRun' }
    if ($ExportHostDrivers) { $switches += '-ExportHostDrivers' }
    if ($InstallWindhawk) { $switches += '-InstallWindhawk' }
    if ($InstallYasb) { $switches += '-InstallYasb' }
    if ($InstallKomorebi) { $switches += '-InstallKomorebi' }
    Invoke-SelfElevate -Switches $switches

    if ($ProfilePath) {
        $selection = [pscustomobject]@{
            Profile = (Import-WinMintConsoleBuildProfile -Path $ProfilePath)
            Review = [pscustomobject]@{
                Proceed = $true
                PostBuildUsbDriveLetter = ''
            }
        }
    }
    elseif ($NonInteractive -or $SourceIso) {
        $selection = [pscustomobject]@{
            Profile = (New-WinMintConsoleHeadlessProfile `
                -SourceIso $SourceIso `
                -Architecture $Architecture `
                -ComputerName $ComputerName `
                -AccountName $AccountName `
                -AccountMode $AccountMode `
                -Password $Password `
                -AutoLogon:$AutoLogon `
                -AutoWipeDisk:$AutoWipeDisk `
                -SetupOption $SetupOption `
                -EditionMode $EditionMode `
                -Edition $Edition `
                -DriverSource $DriverSource `
                -DriverPath $DriverPath `
                -TimeZoneId $TimeZoneId `
                -InputLocale $InputLocale `
                -SystemLocale $SystemLocale `
                -UILanguage $UILanguage `
                -UILanguageFallback $UILanguageFallback `
                -UserLocale $UserLocale `
                -ExportHostDrivers:$ExportHostDrivers `
                -InstallWindhawk:$InstallWindhawk `
                -InstallYasb:$InstallYasb `
                -InstallKomorebi:$InstallKomorebi `
                -DryRun:$DryRun)
            Review = [pscustomobject]@{
                Proceed = $true
                PostBuildUsbDriveLetter = ''
            }
        }
    }
    elseif ($DryRun -and (Test-WinMintConsoleNonInteractive)) {
        $selection = [pscustomobject]@{
            Profile = (New-WinMintConsoleDryRunProfile `
                -InstallWindhawk:$InstallWindhawk `
                -InstallYasb:$InstallYasb `
                -InstallKomorebi:$InstallKomorebi)
            Review = [pscustomobject]@{
                Proceed = $true
                PostBuildUsbDriveLetter = ''
            }
        }
    }
    else {
        $selection = New-WinMintConsoleBuildConfig `
            -DryRun:$DryRun `
            -ExportHostDrivers:$ExportHostDrivers `
            -InstallWindhawk:$InstallWindhawk `
            -InstallYasb:$InstallYasb `
            -InstallKomorebi:$InstallKomorebi
    }
    if (-not $selection.Review.Proceed) { return }
    $canShowProgress = -not [Console]::IsOutputRedirected -and
                       -not (Test-Win11IsoVerboseLogging) -and
                       (Get-Command Invoke-SpectreCommandWithProgress -ErrorAction SilentlyContinue)

    if ($canShowProgress) {
        $capturedProfile = $selection.Profile
        $capturedDryRun  = [bool]$DryRun
        Invoke-SpectreCommandWithProgress -ScriptBlock {
            param([Spectre.Console.ProgressContext]$ctx)
            $script:PipelineTasks = @{
                'Stage ISO'    = $ctx.AddTask('[cyan]Stage ISO[/]',    $false, 100)
                'Service WIM'  = $ctx.AddTask('[cyan]Service WIM[/]',  $false, 100)
                'Assemble ISO' = $ctx.AddTask('[cyan]Assemble ISO[/]', $false, 100)
            }
            foreach ($t in $script:PipelineTasks.Values) { $t.StopTask() }
            $buildResult = $null
            try {
                $buildResult = Start-WinMintBuild -BuildProfile $capturedProfile -DryRun:$capturedDryRun
            } finally {
                $script:PipelineTasks = $null
            }
            # Emit explicitly so Invoke-SpectreCommandWithProgress passes the build
            # result back as its return value — needed for $result.OutputPath below.
            $buildResult
        }.GetNewClosure()
    } else {
        Start-WinMintBuild -BuildProfile $selection.Profile -DryRun:$DryRun
    }
}
