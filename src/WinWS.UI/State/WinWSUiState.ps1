#Requires -Version 7.3

enum WinWSUiStage {
    Start       = 0
    Machine     = 1
    Disk        = 2
    Profile     = 3
    Workstation = 4
    Launch      = 5
}

enum WinWSIsoState {
    Idle
    Verifying
    Verified
    Error
}

if (-not (Get-Command Get-WinWSUiHostRegionalDefault -ErrorAction SilentlyContinue)) {
    function Get-WinWSUiHostRegionalDefault {
        $timeZoneId = 'UTC'
        $userLocaleName = [System.Globalization.CultureInfo]::CurrentCulture.Name
        $uiLanguageName = [System.Globalization.CultureInfo]::CurrentUICulture.Name
        $systemLocaleName = $userLocaleName
        if ([string]::IsNullOrWhiteSpace($uiLanguageName) -or $uiLanguageName -in @('en', 'en-001')) {
            $uiLanguageName = 'en-US'
        }
        $homeLocationGeoId = 244
        try { $timeZoneId = (Get-TimeZone).Id } catch {}
        try {
            $systemLocale = Get-WinSystemLocale -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($systemLocale.Name)) {
                $systemLocaleName = $systemLocale.Name
            }
        } catch {}
        if ([string]::IsNullOrWhiteSpace($userLocaleName)) { $userLocaleName = $systemLocaleName }
        try { $homeLocationGeoId = [int](Get-WinHomeLocation).GeoId } catch {}

        [pscustomobject]@{
            TimeZoneId         = $timeZoneId
            InputLocale        = $userLocaleName
            KeyboardLayouts    = @($userLocaleName)
            SystemLocale       = $systemLocaleName
            UILanguage         = $uiLanguageName
            UILanguageFallback = $uiLanguageName
            UserLocale         = $userLocaleName
            HomeLocationGeoId  = $homeLocationGeoId
        }
    }
}

function New-WinWSUiState {
    param([string]$RepositoryRoot)

    $regional = Get-WinWSUiHostRegionalDefault
    [pscustomobject]@{
        RepositoryRoot = $RepositoryRoot
        Stage          = [WinWSUiStage]::Start
        Iso            = [pscustomobject]@{
            Path         = ''
            Architecture = ''
            State        = [WinWSIsoState]::Idle
            Error        = ''
            Editions     = @()
        }
        Machine        = [pscustomobject]@{
            TargetDevice   = 'DifferentPC'
            EditionMode    = 'TargetLicense'
            Edition        = ''
            HardwareBypass = $false
        }
        Drivers        = [pscustomobject]@{
            Source            = 'None'
            Path              = ''
            ExportHostDrivers = $false
            Error             = ''
        }
        Disk           = [pscustomobject]@{ Mode = 'Manual'; WipeConfirmed = $false }
        ProfileGroups  = @('Minimal')
        Identity       = [pscustomobject]@{
            ComputerName    = ''
            AccountName     = ''
            Password        = ''
            ConfirmPassword = ''
            AutoLogon       = $false
        }
        Desktop        = [pscustomobject]@{
            Layers     = @('standard')
            CursorPack = 'BreezeXLight'
        }
        Development    = [pscustomobject]@{
            Editors    = @()
            WslDistros = @()
        }
        Regional       = $regional
        Build          = [pscustomobject]@{
            IsRunning  = $false
            OutputPath = ''
            LogText    = [System.Text.StringBuilder]::new()
        }
    }
}

function Set-WinWSUiStage {
    param(
        [Parameter(Mandatory)][object]$State,
        [WinWSUiStage]$Stage
    )

    $State.Stage = $Stage
}

function Get-WinWSUiStageIndex {
    param([Parameter(Mandatory)][object]$State)

    return [int]$State.Stage
}

function Get-WinWSUiStateProbeText {
    param([Parameter(Mandatory)][object]$State)

    $driverPathSet = -not [string]::IsNullOrWhiteSpace([string]$State.Drivers.Path)
    return 'stage={0};page={1};isoVerified={2};driverSource={3};driverPathSet={4}' -f `
        ([string]$State.Stage),
        ([int]$State.Stage),
        ([bool]($State.Iso.State -eq [WinWSIsoState]::Verified)).ToString().ToLowerInvariant(),
        ([string]$State.Drivers.Source),
        ([bool]$driverPathSet).ToString().ToLowerInvariant()
}
