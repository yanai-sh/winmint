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

# Offline registry tweak catalog ($script:RegistryTweaks) and curation predicates
# are assembled from the per-tweak modules in Private\Image\Tweaks\ via
# Private\Image\Tweaks\TweakRegistry.ps1 (dot-sourced ahead of this file's
# consumers). Add or change a tweak by editing/adding a single module file there.

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
