#Requires -Version 7.3

# Hero splash titles and oscdimg volume label (banner art is the primary logo).
$script:Win11IsoBuildShortName = 'WinMint'
$script:Win11IsoVolumeLabel = 'WINMINT'
# Searchable Spectre lists: consistent page size for wizard prompts.
$script:Win11IsoSpectrePageSizeList = 12
# When RawUI is missing or zero: assume Windows Terminal default ~120×30 (Cascadia Mono 12 pt) for Spectre sync and splash budgeting.
$script:Win11IsoAssumedTerminalCols = 120
$script:Win11IsoAssumedTerminalRows = 30
# Optional single-line panel title above the figlet (keep short; the ASCII already spells the product name). Usually leave empty.
$script:Win11IsoSplashPanelHeader = ''
# Optional Spectre markup block after the hero rule (e.g. extra links). Empty = no extra lines except -DryRun when set.
$script:Win11IsoSplashRuleTitleMarkup = ''

# Welcome hero — Windows 11 / Fluent-inspired accents (Spectre names; tweak for your terminal theme).
# On a light background profile, set Win11IsoSplashHeroBannerLeadMarkup to e.g. [grey30] or [black] instead of [grey93].
$script:Win11IsoSplashHeroPanelBorderColor = 'DodgerBlue1'
$script:Win11IsoSplashHeroBannerLeadMarkup = '[grey93]'
$script:Win11IsoSplashHeroBannerTrailMarkup = '[/]'
$script:Win11IsoSplashHeroPanelHeaderMarkupOpen = '[bold steelblue1]'
$script:Win11IsoSplashHeroPanelHeaderMarkupClose = '[/]'
$script:Win11IsoSplashHeroRuleAccentColor = 'DodgerBlue1'
$script:Win11IsoSplashHeroRuleLineColor = 'Grey'
$script:Win11IsoSplashHeroFallbackBannerMarkupOpen = '[bold grey93]'
$script:Win11IsoSplashHeroFallbackBannerMarkupClose = '[/]'
$script:Win11IsoSplashHeroDryRunMarkup = '[dim grey70]-DryRun[/] [dodgerblue1]·[/] [dim grey70]read-only; no WIM mount, ISO write, disk prep, or USB.[/]'

# Hero ASCII tiers:
# ``Normal`` = FIGlet ``digital`` (``WinMint``) centered + subtitle.
# ``Compact`` = same font for ``WinMint`` plus two caption lines for narrow viewports.
$script:Win11IsoHeroBannerNormal = @'
        +-+-+-+-+-+ +-+-+-+-+
        |W|i|n|W|S| |S|l|i|m|
        +-+-+-+-+-+ +-+-+-+-+

      WinMint
'@

$script:Win11IsoHeroBannerCompact = @'
             +-+-+-+-+-+
             |W|i|n|W|S|
             +-+-+-+-+-+
      WinMint
      autounattend · WIM · ISO
'@

$script:AppxBloatwareCategories = Get-WinMintAppxBloatwareCategories
$script:AppxBloatware = $script:AppxBloatwareCategories.Values | ForEach-Object { $_ } | Sort-Object -Unique
$_bwCheck = $script:AppxBloatware | Sort-Object Length
for ($i = 0; $i -lt $_bwCheck.Count; $i++) {
    for ($j = $i + 1; $j -lt $_bwCheck.Count; $j++) {
        if ($_bwCheck[$j] -like "*$($_bwCheck[$i])*") {
            Write-Verbose "Bloatware: prefix '$($_bwCheck[$i])' is a substring of '$($_bwCheck[$j])' — potential over-match."
        }
    }
}
Remove-Variable _bwCheck

# Cursor pack: fixed WinMint default, bundled with the repo.
$script:Win11IsoCursorPackCatalog = @{
    'Windows11Modern'     = @{
        ProjectPage         = ''
        PinnedReleaseLabel  = ''
        HostSourceDir       = 'Windows11ModernLight'
        SchemeName          = 'Windows 11 Modern'
        DestSegment         = 'Windows11Modern'
        MarkerRelPath       = 'Windows11ModernLight\Arrow.cur'
        ExtractedSourceDirs = @()
        ExpectedSha256      = ''
        Bundled             = $true
    }
}

$script:Win11IsoDefaultCursorPackKind = 'Windows11Modern'
$script:Win11IsoCursorSchemeOrder = @(
    'Arrow.cur', 'Help.cur', 'Work.ani', 'Busy.ani', 'Cross.cur', 'IBeam.cur', 'Handwriting.cur', 'Unavailable.cur',
    'SizeNS.cur', 'SizeWE.cur', 'SizeNWSE.cur', 'SizeNESW.cur', 'Move.cur', 'Alternate.cur', 'Link.cur',
    'Pin.cur', 'Person.cur'
)
$script:Win11IsoCursorRegistryPairs = @(
    @{ Name = 'Arrow'; File = 'Arrow.cur' }
    @{ Name = 'Help'; File = 'Help.cur' }
    @{ Name = 'AppStarting'; File = 'Work.ani' }
    @{ Name = 'Wait'; File = 'Busy.ani' }
    @{ Name = 'Crosshair'; File = 'Cross.cur' }
    @{ Name = 'IBeam'; File = 'IBeam.cur' }
    @{ Name = 'NWPen'; File = 'Handwriting.cur' }
    @{ Name = 'No'; File = 'Unavailable.cur' }
    @{ Name = 'SizeNS'; File = 'SizeNS.cur' }
    @{ Name = 'SizeWE'; File = 'SizeWE.cur' }
    @{ Name = 'SizeNWSE'; File = 'SizeNWSE.cur' }
    @{ Name = 'SizeNESW'; File = 'SizeNESW.cur' }
    @{ Name = 'SizeAll'; File = 'Move.cur' }
    @{ Name = 'UpArrow'; File = 'Alternate.cur' }
    @{ Name = 'Hand'; File = 'Link.cur' }
    @{ Name = 'Pin'; File = 'Pin.cur' }
    @{ Name = 'Person'; File = 'Person.cur' }
)
$script:Win11IsoCursorOptionalRegistryPairs = @()

function Assert-Win11IsoFileHash {
    <# <summary>Computes SHA256; logs it verbosely; throws on mismatch when ExpectedHash is set. Returns the computed hash.</summary> #>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$Label = '',
        [string]$ExpectedHash = ''
    )
    $hash = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash
    $tag  = if ($Label) { "$Label " } else { '' }
    LogVerbose "${tag}SHA256: $hash"
    if (-not [string]::IsNullOrWhiteSpace($ExpectedHash) -and $hash -ne $ExpectedHash.ToUpperInvariant()) {
        throw "${tag}SHA256 mismatch. Expected: $ExpectedHash  Got: $hash"
    }
    return $hash
}

$script:Win11IsoOpenAdminTerminalCommand =
    'pwsh.exe -WindowStyle Hidden -Command "Start-Process cmd.exe -ArgumentList ''/c cd /d `\"%V`\" ^&^& start wt.exe'' -Verb RunAs"'

$script:RegistryTweaks = @(
    @{ id = 'hardware-bypass'; description = 'Hardware compatibility bypass (TPM 2.0 / Secure Boot / CPU / RAM / Storage)'
        scope = 'offline registry'; risk = 'medium'; reversible = $true; phase = 'offline-image'
        intent = 'Allow Windows Setup to proceed on explicitly selected unsupported hardware.'
        set        = @(
            @{ path = 'zSYSTEM\Setup\MoSetup';   name = 'AllowUpgradesWithUnsupportedTPMOrCPU'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
            @{ path = 'zSYSTEM\Setup\LabConfig'; name = 'BypassTPMCheck';         type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
            @{ path = 'zSYSTEM\Setup\LabConfig'; name = 'BypassSecureBootCheck';  type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
            @{ path = 'zSYSTEM\Setup\LabConfig'; name = 'BypassCPUCheck';         type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
            @{ path = 'zSYSTEM\Setup\LabConfig'; name = 'BypassRAMCheck';         type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
            @{ path = 'zSYSTEM\Setup\LabConfig'; name = 'BypassStorageCheck';     type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } }
        ); remove  = @()
    }
    @{ id = 'developer-qol'; description = 'Explorer QoL (file extensions and hidden files)'
        scope = 'default user registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
        intent = 'Make Explorer friendlier for development by exposing file extensions and hidden files.'
        set        = @(
            @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'HideFileExt'; type = 'REG_DWORD'; value = '0'; undo = @{ type = 'REG_DWORD'; value = '1' } },
            @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'Hidden'; type = 'REG_DWORD'; value = '1'; undo = @{ type = 'REG_DWORD'; value = '2' } }
        ); remove  = @()
    }
    @{ id = 'powershell-remotesigned'; description = 'PowerShell execution policy: RemoteSigned for Windows PowerShell and PowerShell 7'
        scope = 'machine registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
        intent = 'Permit locally authored PowerShell scripts while keeping downloaded scripts signature-gated.'
        set        = @(
            @{ path = 'zSOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell'; name = 'ExecutionPolicy'; type = 'REG_SZ'; value = 'RemoteSigned'; undo = @{ action = 'delete' } },
            @{ path = 'zSOFTWARE\Microsoft\PowerShellCore\ShellIds\Microsoft.PowerShell'; name = 'ExecutionPolicy'; type = 'REG_SZ'; value = 'RemoteSigned'; undo = @{ action = 'delete' } }
        ); remove  = @()
    }
    @{ id = 'terminal-admin-context'; description = 'Open Terminal Here as Administrator Context Menu'
        scope = 'offline registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
        intent = 'Add a fast elevated terminal entry to directory context menus.'
        set        = @(
            @{ path = 'zSOFTWARE\Classes\Directory\shell\OpenWTHereAsAdmin'; name = 'MUIVerb'; type = 'REG_SZ'; value = 'Open Terminal Here as Administrator'; undo = @{ action = 'delete' } },
            @{ path = 'zSOFTWARE\Classes\Directory\shell\OpenWTHereAsAdmin'; name = 'Icon'; type = 'REG_SZ'; value = 'wt.exe' },
            @{ path = 'zSOFTWARE\Classes\Directory\shell\OpenWTHereAsAdmin'; name = 'HasLUAShield'; type = 'REG_SZ'; value = '' },
            @{ path = 'zSOFTWARE\Classes\Directory\shell\OpenWTHereAsAdmin\command'; name = ''; type = 'REG_SZ'; value = $script:Win11IsoOpenAdminTerminalCommand },
            @{ path = 'zSOFTWARE\Classes\Directory\Background\shell\OpenWTHereAsAdmin'; name = 'MUIVerb'; type = 'REG_SZ'; value = 'Open Terminal Here as Administrator' },
            @{ path = 'zSOFTWARE\Classes\Directory\Background\shell\OpenWTHereAsAdmin'; name = 'Icon'; type = 'REG_SZ'; value = 'wt.exe' },
            @{ path = 'zSOFTWARE\Classes\Directory\Background\shell\OpenWTHereAsAdmin'; name = 'HasLUAShield'; type = 'REG_SZ'; value = '' },
            @{ path = 'zSOFTWARE\Classes\Directory\Background\shell\OpenWTHereAsAdmin\command'; name = ''; type = 'REG_SZ'; value = $script:Win11IsoOpenAdminTerminalCommand }
        ); remove  = @()
    }
    @{ id = 'uac-no-secure-desktop'; description = 'UAC prompts without secure desktop dimming'
        scope = 'machine policy registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
        intent = 'Keep UAC consent prompts enabled while avoiding the disruptive screen-dimming secure desktop switch.'
        set        = @(
            @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; name = 'PromptOnSecureDesktop'; type = 'REG_DWORD'; value = '0'; undo = @{ type = 'REG_DWORD'; value = '1' } }
        ); remove  = @()
    }
    @{ id = 'edge-policy-minimal'; description = 'Edge Minimal cleanup (noise/privacy, commerce, widgets, image enhancement, sidebar)'
        scope = 'machine policy registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
        intent = 'Reduce Edge promotional, commerce, telemetry, and sidebar noise for Minimal builds.'
        set        = @(
            @{ path = 'zSOFTWARE\Policies\Microsoft\EdgeUpdate'; name = 'CreateDesktopShortcutDefault'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'EdgeEnhanceImagesEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'PersonalizationReportingEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'ShowRecommendationsEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'HideFirstRunExperience'; type = 'REG_DWORD'; value = '1' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'UserFeedbackAllowed'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'ConfigureDoNotTrack'; type = 'REG_DWORD'; value = '1' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'AlternateErrorPagesEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'EdgeCollectionsEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'EdgeFollowEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'EdgeShoppingAssistantEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'MicrosoftEdgeInsiderPromotionEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'ShowMicrosoftRewards'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'WebWidgetAllowed'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'HubsSidebarEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'StandaloneHubsSidebarEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'DiagnosticData'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'EdgeAssetDeliveryServiceEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'CryptoWalletEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'WalletDonationEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge\ExtensionInstallBlocklist'; name = '1'; type = 'REG_SZ'; value = 'ofefcgjbeghpigppfmkologfjadafddi' }
        ); remove  = @()
    }
    @{ id = 'edge-policy-copilotplus'; description = 'Edge CopilotPlus cleanup (noise/privacy and commerce only; keeps Copilot/sidebar, web widgets, image enhancement)'
        scope = 'machine policy registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
        intent = 'Reduce Edge promotional, commerce, and telemetry noise while preserving Copilot+ sidebar capabilities.'
        set        = @(
            @{ path = 'zSOFTWARE\Policies\Microsoft\EdgeUpdate'; name = 'CreateDesktopShortcutDefault'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'PersonalizationReportingEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'ShowRecommendationsEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'HideFirstRunExperience'; type = 'REG_DWORD'; value = '1' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'UserFeedbackAllowed'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'ConfigureDoNotTrack'; type = 'REG_DWORD'; value = '1' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'AlternateErrorPagesEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'EdgeShoppingAssistantEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'MicrosoftEdgeInsiderPromotionEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'ShowMicrosoftRewards'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'DiagnosticData'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'CryptoWalletEnabled'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'WalletDonationEnabled'; type = 'REG_DWORD'; value = '0' }
        ); remove  = @()
    }
    @{ id = 'dual-boot-windows-policy'; description = 'Dual boot: disable Fast Startup and prevent automatic BitLocker device encryption'
        scope = 'offline registry'; risk = 'medium'; reversible = $true; phase = 'offline-image'
        intent = 'Avoid dual-boot friction from Fast Startup, surprise device encryption, and firmware payload injection.'
        set        = @(
            @{ path = 'zSYSTEM\ControlSet001\Control\BitLocker'; name = 'PreventDeviceEncryption'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
            @{ path = 'zSYSTEM\ControlSet001\Control\Session Manager\Power'; name = 'HiberbootEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ type = 'REG_DWORD'; value = '1' } },
            @{ path = 'zSYSTEM\ControlSet001\Control\Session Manager'; name = 'DisableWpbtExecution'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } }
        ); remove  = @()
    }
    @{ id = 'onedrive-policy'; description = 'OneDrive: remove integration, block sync/reinstall, and force known folders back to local profile paths'
        scope = 'machine and default user registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
        intent = 'Remove OneDrive pressure and keep known folders local for new users.'
        set        = @(
            @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\OneDrive'; name = 'DisableFileSync'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\OneDrive'; name = 'DisableFileSyncNGSC'; type = 'REG_DWORD'; value = '1' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\OneDrive'; name = 'DisablePersonalSync';  type = 'REG_DWORD'; value = '1' },
            @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\OneDrive'; name = 'DisableLibrariesDefaultSaveToOneDrive'; type = 'REG_DWORD'; value = '1' },
            @{ path = 'zSOFTWARE\Wow6432Node\Policies\Microsoft\Windows\OneDrive'; name = 'DisableFileSync'; type = 'REG_DWORD'; value = '1' },
            @{ path = 'zSOFTWARE\Wow6432Node\Policies\Microsoft\Windows\OneDrive'; name = 'DisableFileSyncNGSC'; type = 'REG_DWORD'; value = '1' },
            @{ path = 'zSOFTWARE\Wow6432Node\Policies\Microsoft\Windows\OneDrive'; name = 'DisablePersonalSync'; type = 'REG_DWORD'; value = '1' },
            @{ path = 'zSOFTWARE\Wow6432Node\Policies\Microsoft\Windows\OneDrive'; name = 'DisableLibrariesDefaultSaveToOneDrive'; type = 'REG_DWORD'; value = '1' },
            @{ path = 'zSOFTWARE\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'; name = 'System.IsPinnedToNameSpaceTree'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zSOFTWARE\Classes\WOW6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'; name = 'System.IsPinnedToNameSpaceTree'; type = 'REG_DWORD'; value = '0' },
            @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'; name = 'Desktop'; type = 'REG_EXPAND_SZ'; value = '%USERPROFILE%\Desktop' },
            @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'; name = 'Personal'; type = 'REG_EXPAND_SZ'; value = '%USERPROFILE%\Documents' },
            @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'; name = 'My Pictures'; type = 'REG_EXPAND_SZ'; value = '%USERPROFILE%\Pictures' },
            @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'; name = 'My Music'; type = 'REG_EXPAND_SZ'; value = '%USERPROFILE%\Music' },
            @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'; name = 'My Video'; type = 'REG_EXPAND_SZ'; value = '%USERPROFILE%\Videos' },
            @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'; name = '{374DE290-123F-4565-9164-39C4925E467B}'; type = 'REG_EXPAND_SZ'; value = '%USERPROFILE%\Downloads' },
            @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'; name = 'Desktop'; type = 'REG_SZ'; value = 'C:\Users\Default\Desktop' },
            @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'; name = 'Personal'; type = 'REG_SZ'; value = 'C:\Users\Default\Documents' },
            @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'; name = 'My Pictures'; type = 'REG_SZ'; value = 'C:\Users\Default\Pictures' },
            @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'; name = 'My Music'; type = 'REG_SZ'; value = 'C:\Users\Default\Music' },
            @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'; name = 'My Video'; type = 'REG_SZ'; value = 'C:\Users\Default\Videos' },
            @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'; name = '{374DE290-123F-4565-9164-39C4925E467B}'; type = 'REG_SZ'; value = 'C:\Users\Default\Downloads' }
        ); remove  = @(
            @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\OneDrive' },
            @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\OneDriveSetup' },
            @{ path = 'zDEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\OneDrive' },
            @{ path = 'zDEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\OneDriveSetup' }
        )
    }
    @{ id = 'gamebar-policy'; description = 'Disable Xbox Game Bar / GameDVR overlay popup on controller connect'
        scope = 'machine and default user registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
        intent = 'Suppress Game Bar capture prompts and GameDVR recording defaults.'
        set        = @(
            @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\GameDVR'; name = 'AllowGameDVR'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
            @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR'; name = 'AppCaptureEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ type = 'REG_DWORD'; value = '1' } },
            @{ path = 'zNTUSER\System\GameConfigStore'; name = 'GameDVR_Enabled'; type = 'REG_DWORD'; value = '0'; undo = @{ type = 'REG_DWORD'; value = '1' } }
        ); remove  = @()
    }
    @{ id = 'developer-mode'; description = 'Windows Developer Mode (symlinks without UAC elevation, app sideloading)'
        scope = 'machine registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
        intent = 'Enable Windows Developer Mode features expected by developer workstations.'
        set        = @(
            @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'; name = 'AllowAllTrustedApps';              type = 'REG_DWORD'; value = '1'; undo = @{ type = 'REG_DWORD'; value = '0' } },
            @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'; name = 'AllowDevelopmentWithoutDevLicense'; type = 'REG_DWORD'; value = '1'; undo = @{ type = 'REG_DWORD'; value = '0' } }
        ); remove  = @()
    }
)

$script:HiveMap = @{
    'zDEFAULT'  = 'Windows\System32\config\default'
    'zNTUSER'   = 'Users\Default\ntuser.dat'
    'zSOFTWARE' = 'Windows\System32\config\SOFTWARE'
    'zSYSTEM'   = 'Windows\System32\config\SYSTEM'
}

# Filled by Test-OfflineStagingReadiness after ISO files are staged (overrides defaults)
$script:BootWimDriverMountIndexes = @(2)
$script:BootWimWinPEUtilityMountIndex = 2

# ═══════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════
