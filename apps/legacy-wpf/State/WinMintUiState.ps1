#Requires -Version 7.3

enum WinMintUiStage {
    Start       = 0
    Machine     = 1
    Disk        = 2
    Profile     = 3
    Workstation = 4
    Launch      = 5
}

enum WinMintIsoState {
    Idle
    Verifying
    Verified
    Error
}

if (-not (Get-Command Get-WinMintUiHostRegionalDefault -ErrorAction SilentlyContinue)) {
    function Get-WinMintUiHostRegionalDefault {
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
        $keyboardLayouts = [System.Collections.Generic.List[string]]::new()
        try {
            foreach ($language in @(Get-WinUserLanguageList -ErrorAction Stop)) {
                foreach ($tip in [string[]]@($language.InputMethodTips)) {
                    if ([string]::IsNullOrWhiteSpace($tip)) { continue }
                    $layout = $tip.Trim()
                    if (-not $keyboardLayouts.Contains($layout)) {
                        $keyboardLayouts.Add($layout) | Out-Null
                    }
                }
            }
        } catch {}
        if ($keyboardLayouts.Count -gt 0) {
            $inputLocaleName = ($keyboardLayouts.ToArray() -join ';')
        } else {
            $inputLocaleName = $userLocaleName
            $keyboardLayouts.Add($userLocaleName) | Out-Null
        }

        [pscustomobject]@{
            TimeZoneId         = $timeZoneId
            InputLocale        = $inputLocaleName
            KeyboardLayouts    = @($keyboardLayouts.ToArray())
            SystemLocale       = $systemLocaleName
            UILanguage         = $uiLanguageName
            UILanguageFallback = $uiLanguageName
            UserLocale         = $userLocaleName
            HomeLocationGeoId  = $homeLocationGeoId
        }
    }
}

function New-WinMintUiState {
    param([string]$RepositoryRoot)

    $regional = Get-WinMintUiHostRegionalDefault
    [pscustomobject]@{
        RepositoryRoot = $RepositoryRoot
        Stage          = [WinMintUiStage]::Start
        Iso            = [pscustomobject]@{
            Path         = ''
            Architecture = ''
            State        = [WinMintIsoState]::Idle
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
            CursorPack = 'Windows11Modern'
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

function Set-WinMintUiStage {
    param(
        [Parameter(Mandatory)][object]$State,
        [WinMintUiStage]$Stage
    )

    $State.Stage = $Stage
}

function Get-WinMintUiStageIndex {
    param([Parameter(Mandatory)][object]$State)

    return [int]$State.Stage
}

function Get-WinMintUiStateProbeText {
    param([Parameter(Mandatory)][object]$State)

    $driverPathSet = -not [string]::IsNullOrWhiteSpace([string]$State.Drivers.Path)
    return 'stage={0};page={1};isoVerified={2};driverSource={3};driverPathSet={4}' -f `
        ([string]$State.Stage),
        ([int]$State.Stage),
        ([bool]($State.Iso.State -eq [WinMintIsoState]::Verified)).ToString().ToLowerInvariant(),
        ([string]$State.Drivers.Source),
        ([bool]$driverPathSet).ToString().ToLowerInvariant()
}
