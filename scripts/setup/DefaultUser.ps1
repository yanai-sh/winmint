# Default user hive tweaks (loaded as HKU\DefaultUser during specialize).
$ErrorActionPreference = 'Continue'
$logDir = Join-Path $env:ProgramData 'WinWS\Logs'
$null = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue
$payloadDir = 'C:\Windows\Setup\Scripts'
$setupProfilePath = Join-Path $payloadDir 'WinWSSetupProfile.json'
$setupProfile = $null
try {
    if (Test-Path -LiteralPath $setupProfilePath) {
        $setupProfile = Get-Content -LiteralPath $setupProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
} catch {
    "DefaultUser profile read failed: $_" | Out-File (Join-Path $logDir 'DefaultUser_errors.log') -Append
}

function Get-SetupProfileBool {
    param(
        [string]$Section,
        [string]$Name,
        [bool]$Default
    )
    if (-not $setupProfile) { return $Default }
    $sectionProp = $setupProfile.PSObject.Properties[$Section]
    if (-not $sectionProp) { return $Default }
    $valueProp = $sectionProp.Value.PSObject.Properties[$Name]
    if (-not $valueProp) { return $Default }
    return [bool]$valueProp.Value
}

function Set-DefaultUserRegistryValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$Type,
        [Parameter(Mandatory)]
        [string]$Data
    )
    $null = & reg.exe add $Path /v $Name /t $Type /d $Data /f 2>$null
}

function Set-DefaultUserRegistryDefaultValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Type,
        [Parameter(Mandatory)]
        [string]$Data
    )
    $null = & reg.exe add $Path /ve /t $Type /d $Data /f 2>$null
}

function Remove-DefaultUserRegistryValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Name
    )
    $null = & reg.exe delete $Path /v $Name /f 2>$null
}

function Invoke-DefaultUserRegistrySet {
    param(
        [Parameter(Mandatory)]
        [object[]]$Entries
    )
    foreach ($entry in $Entries) {
        Set-DefaultUserRegistryValue -Path $entry.Path -Name $entry.Name -Type $entry.Type -Data $entry.Data
    }
}

$stickyKeysOff = Get-SetupProfileBool -Section 'defaultUser' -Name 'stickyKeysOff' -Default $true
$winwsWallpaperPath = 'C:\Windows\Web\Wallpaper\WinWS\WinWS-Bloom-OLED.png'

$scripts = @(
    {
        foreach ($folder in @('Desktop', 'Documents', 'Downloads', 'Pictures', 'Music', 'Videos')) {
            New-Item -ItemType Directory -Path (Join-Path 'C:\Users\Default' $folder) -Force -ErrorAction SilentlyContinue | Out-Null
        }
        $userShellFolders = 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
        $shellFolders = 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'
        foreach ($known in @(
                @{ Name = 'Desktop'; Local = 'Desktop' },
                @{ Name = 'Personal'; Local = 'Documents' },
                @{ Name = 'My Pictures'; Local = 'Pictures' },
                @{ Name = 'My Music'; Local = 'Music' },
                @{ Name = 'My Video'; Local = 'Videos' },
                @{ Name = '{374DE290-123F-4565-9164-39C4925E467B}'; Local = 'Downloads' }
            )) {
            Set-DefaultUserRegistryValue -Path $userShellFolders -Name $known.Name -Type REG_EXPAND_SZ -Data "%USERPROFILE%\$($known.Local)"
            Set-DefaultUserRegistryValue -Path $shellFolders -Name $known.Name -Type REG_SZ -Data "C:\Users\Default\$($known.Local)"
        }
        foreach ($runKey in @(
                'HKU\DefaultUser\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
                'HKU\DefaultUser\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
            )) {
            foreach ($value in @('OneDrive', 'OneDriveSetup')) {
                Remove-DefaultUserRegistryValue -Path $runKey -Name $value
            }
        }
    }
    { Set-DefaultUserRegistryValue -Path 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name ShowTaskViewButton -Type REG_DWORD -Data 0 }
    {
        foreach ($root in 'Registry::HKU\.DEFAULT', 'Registry::HKU\DefaultUser') {
            Set-ItemProperty -LiteralPath "$root\Control Panel\Keyboard" -Name 'InitialKeyboardIndicators' -Type 'String' -Value 2 -Force
        }
    }
    { Set-DefaultUserRegistryValue -Path 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' -Name TaskbarEndTask -Type REG_DWORD -Data 1 }
    {
        if (-not $stickyKeysOff) { return }
        foreach ($root in 'HKU\.DEFAULT', 'HKU\DefaultUser') {
            Set-DefaultUserRegistryValue -Path "$root\Control Panel\Accessibility\StickyKeys" -Name Flags -Type REG_SZ -Data 506
        }
    }
    {
        $desktopKey = 'HKU\DefaultUser\Control Panel\Desktop'
        if (Test-Path -LiteralPath $winwsWallpaperPath) {
            Invoke-DefaultUserRegistrySet -Entries @(
                @{ Path = $desktopKey; Name = 'Wallpaper'; Type = 'REG_SZ'; Data = $winwsWallpaperPath },
                @{ Path = $desktopKey; Name = 'WallpaperStyle'; Type = 'REG_SZ'; Data = '10' },
                @{ Path = $desktopKey; Name = 'TileWallpaper'; Type = 'REG_SZ'; Data = '0' }
            )
        }
        Invoke-DefaultUserRegistrySet -Entries @(
            @{ Path = 'HKU\DefaultUser\Software\Microsoft\Windows\DWM'; Name = 'ColorPrevalence'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'AppsUseLightTheme'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'SystemUsesLightTheme'; Type = 'REG_DWORD'; Data = '0' }
        )
    }
    { Set-DefaultUserRegistryValue -Path 'HKU\DefaultUser\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.svg\UserChoice' -Name ProgId -Type REG_SZ -Data 'AppXvhc4p7vz4b485xfp46hhk3fq3grkdgjg' }

    # ── Privacy: advertising ID ────────────────────────────────────────────────
    { Set-DefaultUserRegistryValue -Path 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name Enabled -Type REG_DWORD -Data 0 }

    # ── Privacy: feedback frequency ───────────────────────────────────────────
    { Set-DefaultUserRegistryValue -Path 'HKU\DefaultUser\Software\Microsoft\Siuf\Rules' -Name NumberOfSIUFInPeriod -Type REG_DWORD -Data 0 }

    # ── Privacy: contact harvesting (People/Mail are removed; key is inert) ───
    { Set-DefaultUserRegistryValue -Path 'HKU\DefaultUser\Software\Microsoft\InputPersonalization\TrainedDataStore' -Name HarvestContacts -Type REG_DWORD -Data 0 }

    # ── Search: disable Bing in Start and search box web suggestions ──────────
    {
        Invoke-DefaultUserRegistrySet -Entries @(
            @{ Path = 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'BingSearchEnabled'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'CortanaConsent'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = 'HKU\DefaultUser\Software\Policies\Microsoft\Windows\Explorer'; Name = 'DisableSearchBoxSuggestions'; Type = 'REG_DWORD'; Data = '1' }
        )
    }

    # ── UX: instant menus ─────────────────────────────────────────────────────
    { Set-DefaultUserRegistryValue -Path 'HKU\DefaultUser\Control Panel\Desktop' -Name MenuShowDelay -Type REG_SZ -Data '0' }

    # ── Explorer: disable date-grouping (Today/Yesterday/Last week) ───────────
    { Set-DefaultUserRegistryValue -Path 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name GroupByDateModified -Type REG_DWORD -Data 0 }

    # ── Explorer: open Win+E/File Explorer to This PC instead of Home ─────────
    { Set-DefaultUserRegistryValue -Path 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name LaunchTo -Type REG_DWORD -Data 1 }

    # ── Search: disable search highlights (news/seasonal images in search) ────
    { Set-DefaultUserRegistryValue -Path 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\SearchSettings' -Name IsDynamicSearchBoxEnabled -Type REG_DWORD -Data 0 }

    # ── Start: hide Recommended section (recent files, suggested content) ─────
    { Set-DefaultUserRegistryValue -Path 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name Start_IrisRecommendations -Type REG_DWORD -Data 0 }

    # ── Privacy: disable app launch tracking for Start/search suggestions ─────
    { Set-DefaultUserRegistryValue -Path 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name Start_TrackProgs -Type REG_DWORD -Data 0 }

    # ── Settings/notifications: disable suggestions and setup prompts ─────────
    {
        $contentDeliveryPath = 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        Invoke-DefaultUserRegistrySet -Entries @(
            @{ Path = $contentDeliveryPath; Name = 'SubscribedContent-310093Enabled'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = $contentDeliveryPath; Name = 'SubscribedContent-338388Enabled'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = $contentDeliveryPath; Name = 'SubscribedContent-338389Enabled'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = $contentDeliveryPath; Name = 'SubscribedContent-338393Enabled'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = $contentDeliveryPath; Name = 'SubscribedContent-353694Enabled'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = $contentDeliveryPath; Name = 'SubscribedContent-353696Enabled'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = $contentDeliveryPath; Name = 'SubscribedContent-353698Enabled'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = $contentDeliveryPath; Name = 'SoftLandingEnabled'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = $contentDeliveryPath; Name = 'SystemPaneSuggestionsEnabled'; Type = 'REG_DWORD'; Data = '0' }
        )
        Set-DefaultUserRegistryValue -Path 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' -Name ScoobeSystemSettingEnabled -Type REG_DWORD -Data 0
    }

    # ── Content delivery: prevent silent app installs from CDM ───────────────
    {
        Invoke-DefaultUserRegistrySet -Entries @(
            @{ Path = 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'PreInstalledAppsEnabled'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'OemPreInstalledAppsEnabled'; Type = 'REG_DWORD'; Data = '0' }
        )
    }

    # ── Lock screen: disable Spotlight rotating ads and overlay ──────────────
    {
        Invoke-DefaultUserRegistrySet -Entries @(
            @{ Path = 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'RotatingLockScreenEnabled'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'RotatingLockScreenOverlayEnabled'; Type = 'REG_DWORD'; Data = '0' }
        )
    }

    # ── Privacy: tailored experiences from diagnostic data ───────────────────
    { Set-DefaultUserRegistryValue -Path 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Privacy' -Name TailoredExperiencesWithDiagnosticDataEnabled -Type REG_DWORD -Data 0 }

    # ── F1 key: disable launching browser help page on accidental press ───────
    { Set-DefaultUserRegistryDefaultValue -Path 'HKU\DefaultUser\SOFTWARE\Classes\TypeLib\{8cec5860-07a1-11d9-b15e-000d56bfe6ee}\1.0\0\win32' -Type REG_SZ -Data '' }
    { Set-DefaultUserRegistryDefaultValue -Path 'HKU\DefaultUser\SOFTWARE\Classes\TypeLib\{8cec5860-07a1-11d9-b15e-000d56bfe6ee}\1.0\0\win64' -Type REG_SZ -Data '' }

    # ── Default terminal: open cmd/PS via Windows Terminal instead of legacy host
    {
        Invoke-DefaultUserRegistrySet -Entries @(
            @{ Path = 'HKU\DefaultUser\Console\%%Startup'; Name = 'DelegationConsole'; Type = 'REG_SZ'; Data = '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}' },
            @{ Path = 'HKU\DefaultUser\Console\%%Startup'; Name = 'DelegationTerminal'; Type = 'REG_SZ'; Data = '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}' }
        )
    }
)

$errors = @()
foreach ($s in $scripts) {
    try { & $s } catch { $errors += "DefaultUser: $_" }
}
if ($errors.Count -gt 0) {
    ($errors -join "`n") | Out-File (Join-Path $logDir 'DefaultUser_errors.log') -Append
}
