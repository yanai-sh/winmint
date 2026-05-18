#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SetupProfilePath = 'C:\Windows\Setup\Scripts\WinMintSetupProfile.json',
    [string]$RecommendedListPath = '',
    [string]$OutputPath = '',
    [switch]$AsJson
)

$ErrorActionPreference = 'Continue'

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $programData = if ($env:ProgramData) { $env:ProgramData } else { 'C:\ProgramData' }
    $OutputPath = Join-Path $programData 'WinMint\Logs\LiveInstallAudit.json'
}

function Add-AuditFinding {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        [ValidateSet('Info', 'Warning', 'Error')][string]$Severity,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Message
    )
    if ($null -eq $Findings) { return }
    $Findings.Add([ordered]@{
            severity = $Severity
            id       = $Id
            category = $Category
            name     = $Name
            message  = $Message
        }) | Out-Null
}

function Read-AuditJson {
    param([string]$Path)
    try {
        if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
            return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    }
    catch {
        return [pscustomobject]@{ readError = $_.Exception.Message }
    }
    return $null
}

function ConvertTo-AuditStringArray {
    param($Value)
    @(
        @($Value) |
            ForEach-Object { ([string]$_) -split ',' } |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )
}

function Get-AuditProvisionedAppx {
    try {
        @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            ForEach-Object {
                [ordered]@{
                    packageName = [string]$_.PackageName
                    displayName = [string]$_.DisplayName
                    version     = [string]$_.Version
                }
            })
    }
    catch { @() }
}

function Get-AuditInstalledAppx {
    try {
        @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
            ForEach-Object {
                [ordered]@{
                    name            = [string]$_.Name
                    packageFullName = [string]$_.PackageFullName
                    version         = [string]$_.Version
                    publisher       = [string]$_.Publisher
                }
            })
    }
    catch { @() }
}

function Get-AuditWin32UninstallEntry {
    $roots = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($rootPath in $roots) {
        if (-not (Test-Path -LiteralPath $rootPath)) { continue }
        try {
            Get-ChildItem -LiteralPath $rootPath -ErrorAction SilentlyContinue | ForEach-Object {
                $item = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                if (-not $item.DisplayName) { return }
                $entries.Add([ordered]@{
                        displayName    = [string]$item.DisplayName
                        displayVersion = [string]$item.DisplayVersion
                        publisher      = [string]$item.Publisher
                        keyPath        = [string]$_.Name
                    }) | Out-Null
            }
        }
        catch { }
    }
    @($entries.ToArray() | Sort-Object displayName, displayVersion -Unique)
}

function Test-AuditCommand {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    return [bool]$cmd
}

function Test-AuditAppxPackagePresent {
    param([string]$Name)
    try {
        $pkg = Get-AppxPackage -AllUsers -Name $Name -ErrorAction Stop | Select-Object -First 1
        return [bool]$pkg
    }
    catch {
        return $false
    }
}

function Get-AuditServiceStatus {
    param([string]$Name)
    try {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if (-not $svc) { return [ordered]@{ name = $Name; present = $false; status = ''; startType = '' } }
        return [ordered]@{ name = $Name; present = $true; status = [string]$svc.Status; startType = [string]$svc.StartType }
    }
    catch {
        return [ordered]@{ name = $Name; present = $false; status = ''; startType = ''; error = $_.Exception.Message }
    }
}

function Test-AuditRegistryValue {
    param([string]$Path, [string]$Name)
    try {
        $value = (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue).$Name
        return ($null -ne $value)
    }
    catch { return $false }
}

function Get-AuditPlatformProbe {
    param([object]$SetupProfile)
    $windowsFeatures = @()
    if ($SetupProfile -and $SetupProfile.PSObject.Properties['windowsFeatures']) {
        $windowsFeatures = @(ConvertTo-AuditStringArray $SetupProfile.windowsFeatures)
    }
    $expectsWsl = (
        $windowsFeatures -contains 'Microsoft-Windows-Subsystem-Linux' -or
        $windowsFeatures -contains 'VirtualMachinePlatform'
    )
    $programFilesX86 = ${env:ProgramFiles(x86)}
    [ordered]@{
        commands = [ordered]@{ winget = (Test-AuditCommand 'winget.exe') }
        appx = [ordered]@{
            store               = Test-AuditAppxPackagePresent -Name 'Microsoft.WindowsStore'
            desktopAppInstaller = Test-AuditAppxPackagePresent -Name 'Microsoft.DesktopAppInstaller'
            secHealthUi         = Test-AuditAppxPackagePresent -Name 'Microsoft.SecHealthUI'
        }
        runtime = [ordered]@{
            edgeRuntime     = (($programFilesX86 -and (Test-Path -LiteralPath (Join-Path $programFilesX86 'Microsoft\Edge\Application') -ErrorAction SilentlyContinue)) -or
                               ($env:ProgramFiles -and (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application') -ErrorAction SilentlyContinue)))
            webView2Runtime = (($programFilesX86 -and (Test-Path -LiteralPath (Join-Path $programFilesX86 'Microsoft\EdgeWebView\Application') -ErrorAction SilentlyContinue)) -or
                               ($env:ProgramFiles -and (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Microsoft\EdgeWebView\Application') -ErrorAction SilentlyContinue)))
        }
        services = [ordered]@{
            defender      = Get-AuditServiceStatus -Name 'WinDefend'
            firewall      = Get-AuditServiceStatus -Name 'mpssvc'
            windowsUpdate = Get-AuditServiceStatus -Name 'wuauserv'
            bits          = Get-AuditServiceStatus -Name 'BITS'
            waaSMedic     = Get-AuditServiceStatus -Name 'WaaSMedicSvc'
            hns           = Get-AuditServiceStatus -Name 'hns'
        }
        networking = [ordered]@{
            ipv6DisabledComponents = if (Test-AuditRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' -Name 'DisabledComponents') {
                (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' -Name 'DisabledComponents' -ErrorAction SilentlyContinue).DisabledComponents
            } else { $null }
        }
        wsl = [ordered]@{
            expected = [bool]$expectsWsl
            commandPresent = (Test-AuditCommand 'wsl.exe')
            lxssManager = Get-AuditServiceStatus -Name 'LxssManager'
        }
    }
}

function Get-AuditNestedProfileValue {
    param(
        [object]$Profile,
        [string]$Section,
        [string]$Nested,
        [string]$Name,
        $Default = $null
    )

    if (-not $Profile) { return $Default }
    $sectionProp = $Profile.PSObject.Properties[$Section]
    if (-not $sectionProp) { return $Default }
    $nestedProp = $sectionProp.Value.PSObject.Properties[$Nested]
    if (-not $nestedProp) { return $Default }
    $valueProp = $nestedProp.Value.PSObject.Properties[$Name]
    if (-not $valueProp) { return $Default }
    return $valueProp.Value
}

function Get-AuditProfileValue {
    param(
        [object]$Profile,
        [string]$Section,
        [string]$Name,
        $Default = $null
    )

    if (-not $Profile) { return $Default }
    $sectionProp = $Profile.PSObject.Properties[$Section]
    if (-not $sectionProp) { return $Default }
    $valueProp = $sectionProp.Value.PSObject.Properties[$Name]
    if (-not $valueProp) { return $Default }
    return $valueProp.Value
}

function Get-AuditDmaInteropProbe {
    param([object]$SetupProfile)

    $enabled = [bool](Get-AuditNestedProfileValue -Profile $SetupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'enabled' -Default $false)
    $setupCountry = [string](Get-AuditNestedProfileValue -Profile $SetupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'setupCountry' -Default '')
    $setupUserLocale = [string](Get-AuditNestedProfileValue -Profile $SetupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'setupUserLocale' -Default '')
    $setupGeoId = [int](Get-AuditNestedProfileValue -Profile $SetupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'setupHomeLocationGeoId' -Default 0)
    $restoreTimeZoneId = [string](Get-AuditNestedProfileValue -Profile $SetupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'restoreTimeZoneId' -Default '')
    if ([string]::IsNullOrWhiteSpace($restoreTimeZoneId)) {
        $restoreTimeZoneId = [string](Get-AuditProfileValue -Profile $SetupProfile -Section 'regional' -Name 'timeZoneId' -Default '')
    }
    $restoreUserLocale = [string](Get-AuditNestedProfileValue -Profile $SetupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'restoreUserLocale' -Default '')
    $restoreGeoId = [int](Get-AuditNestedProfileValue -Profile $SetupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'restoreHomeLocationGeoId' -Default 0)
    $eeaSetupGeoIds = @(68, 94)

    $timeZone = $null
    try { $timeZone = Get-TimeZone } catch { }
    $homeLocation = $null
    try { $homeLocation = Get-WinHomeLocation } catch { }
    $autoTimeZoneService = Get-AuditServiceStatus -Name 'tzautoupdate'
    $autoTimeZoneStart = $null
    try {
        $autoTimeZoneStart = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate' -Name Start -ErrorAction SilentlyContinue).Start
    } catch { }

    [ordered]@{
        enabled = $enabled
        setup = [ordered]@{
            country = $setupCountry
            userLocale = $setupUserLocale
            homeLocationGeoId = $setupGeoId
            knownEeaSetupGeoId = ($eeaSetupGeoIds -contains $setupGeoId)
        }
        restore = [ordered]@{
            timeZoneId = $restoreTimeZoneId
            userLocale = $restoreUserLocale
            homeLocationGeoId = $restoreGeoId
        }
        current = [ordered]@{
            timeZoneId = if ($timeZone) { [string]$timeZone.Id } else { '' }
            homeLocationGeoId = if ($homeLocation) { [int]$homeLocation.GeoId } else { 0 }
            homeLocation = if ($homeLocation) { [string]$homeLocation.HomeLocation } else { '' }
        }
        autoTimeZone = [ordered]@{
            service = $autoTimeZoneService
            registryStart = $autoTimeZoneStart
            disabled = ($autoTimeZoneService.present -and [string]$autoTimeZoneService.startType -eq 'Disabled' -and $null -ne $autoTimeZoneStart -and [int]$autoTimeZoneStart -eq 4)
            policy = 'DMA builds must not leave automatic time-zone updates active; users may still set the time zone manually or re-enable location-based time zone later.'
        }
    }
}

function Get-AuditRecommendedClassification {
    param([object[]]$Recommended)
    $preservePatterns = @('Windows Subsystem for Linux', 'Microsoft Edge', 'Microsoft Edge WebView2 Runtime', 'Microsoft Visual C\+\+', 'Desktop App Installer', 'Windows Store', 'Git')
    $candidatePatterns = @('Clipchamp', 'Solitaire', 'Teams', 'Xbox', 'Dev Home', 'Outlook', 'Power Automate', 'McAfee', 'Norton', 'ExpressVPN', 'Surfshark', 'CCleaner')
    @($Recommended | ForEach-Object {
            $name = [string]$_.Name
            $classification = 'unknown'
            foreach ($pattern in $preservePatterns) {
                if ($name -match $pattern) { $classification = 'preserve'; break }
            }
            if ($classification -eq 'unknown') {
                foreach ($pattern in $candidatePatterns) {
                    if ($name -match $pattern) { $classification = 'candidate'; break }
                }
            }
            [ordered]@{
                name = $name
                type = [string]$_.Type
                sourceClassification = [string]$_.Classification
                winmintClassification = $classification
            }
        })
}

$findings = [System.Collections.Generic.List[object]]::new()
$setupProfile = Read-AuditJson -Path $SetupProfilePath
$recommended = Read-AuditJson -Path $RecommendedListPath

if ($setupProfile -and $setupProfile.PSObject.Properties['readError']) {
    Add-AuditFinding -Findings $findings -Severity Error -Id 'setup-profile-read' -Category 'profile' -Name $SetupProfilePath -Message $setupProfile.readError
    $setupProfile = $null
}

$expectedRemovalPrefixes = @()
if ($setupProfile -and $setupProfile.PSObject.Properties['appxRemovalPrefixes']) {
    $expectedRemovalPrefixes = @(ConvertTo-AuditStringArray $setupProfile.appxRemovalPrefixes)
}
elseif (Test-Path -LiteralPath $SetupProfilePath) {
    Add-AuditFinding -Findings $findings -Severity Warning -Id 'setup-profile-prefixes-missing' -Category 'profile' -Name $SetupProfilePath -Message 'Setup profile exists but appxRemovalPrefixes was not found.'
}
else {
    Add-AuditFinding -Findings $findings -Severity Warning -Id 'setup-profile-missing' -Category 'profile' -Name $SetupProfilePath -Message 'Setup profile was not found; AppX drift checks use an empty expected list.'
}

$provisionedAppx = @(Get-AuditProvisionedAppx)
$installedAppx = @(Get-AuditInstalledAppx)
$win32Entries = @(Get-AuditWin32UninstallEntry)
$platform = Get-AuditPlatformProbe -SetupProfile $setupProfile
$dmaInterop = Get-AuditDmaInteropProbe -SetupProfile $setupProfile

foreach ($prefix in $expectedRemovalPrefixes) {
    foreach ($pkg in @($provisionedAppx | Where-Object { [string]$_.packageName -like "*$prefix*" -or [string]$_.displayName -like "*$prefix*" })) {
        Add-AuditFinding -Findings $findings -Severity Warning -Id 'appx-provisioned-drift' -Category 'appx' -Name ([string]$pkg.packageName) -Message "Provisioned AppX still matches expected removal prefix '$prefix'."
    }
    foreach ($pkg in @($installedAppx | Where-Object { [string]$_.packageFullName -like "*$prefix*" -or [string]$_.name -like "*$prefix*" })) {
        Add-AuditFinding -Findings $findings -Severity Warning -Id 'appx-installed-drift' -Category 'appx' -Name ([string]$pkg.packageFullName) -Message "Installed AppX still matches expected removal prefix '$prefix'."
    }
}

foreach ($required in @(
        @('store', 'Store AppX', $platform.appx.store),
        @('desktop-app-installer', 'Desktop App Installer AppX', $platform.appx.desktopAppInstaller),
        @('winget', 'winget command', $platform.commands.winget),
        @('edge-runtime', 'Microsoft Edge runtime', $platform.runtime.edgeRuntime),
        @('webview2-runtime', 'Microsoft Edge WebView2 Runtime', $platform.runtime.webView2Runtime),
        @('defender-service', 'Defender service', $platform.services.defender.present),
        @('firewall-service', 'Firewall service', $platform.services.firewall.present),
        @('windows-update-service', 'Windows Update service', $platform.services.windowsUpdate.present),
        @('bits-service', 'BITS service', $platform.services.bits.present),
        @('waasmedic-service', 'WaaSMedic service', $platform.services.waaSMedic.present),
        @('hns-service', 'HNS service', $platform.services.hns.present)
    )) {
    if (-not [bool]$required[2]) {
        Add-AuditFinding -Findings $findings -Severity Error -Id $required[0] -Category 'platform' -Name $required[1] -Message "$($required[1]) is missing."
    }
}

if ($null -ne $platform.networking.ipv6DisabledComponents -and [int64]$platform.networking.ipv6DisabledComponents -ne 0) {
    Add-AuditFinding -Findings $findings -Severity Error -Id 'ipv6-disabled' -Category 'platform' -Name 'IPv6' -Message "IPv6 DisabledComponents is set to $($platform.networking.ipv6DisabledComponents)."
}
if ($platform.wsl.expected -and -not $platform.wsl.commandPresent) {
    Add-AuditFinding -Findings $findings -Severity Error -Id 'wsl-command-missing' -Category 'platform' -Name 'WSL' -Message 'WSL is expected by profile but wsl.exe was not found.'
}
if ($platform.wsl.expected -and -not $platform.wsl.lxssManager.present) {
    Add-AuditFinding -Findings $findings -Severity Error -Id 'wsl-service-missing' -Category 'platform' -Name 'LxssManager' -Message 'WSL is expected by profile but LxssManager service was not found.'
}

if ($dmaInterop.enabled) {
    if (-not [bool]$dmaInterop.setup.knownEeaSetupGeoId) {
        Add-AuditFinding -Findings $findings -Severity Error -Id 'dma-setup-region' -Category 'dmaInterop' -Name 'DMA setup region' -Message "DMA interoperability is enabled, but setupHomeLocationGeoId is '$($dmaInterop.setup.homeLocationGeoId)' rather than a known WinMint EEA setup GeoID."
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$dmaInterop.restore.timeZoneId) -and [string]$dmaInterop.current.timeZoneId -ne [string]$dmaInterop.restore.timeZoneId) {
        Add-AuditFinding -Findings $findings -Severity Error -Id 'dma-time-zone-restore' -Category 'dmaInterop' -Name 'Time zone restore' -Message "Current time zone '$($dmaInterop.current.timeZoneId)' does not match configured restore time zone '$($dmaInterop.restore.timeZoneId)'."
    }
    if ([int]$dmaInterop.restore.homeLocationGeoId -gt 0 -and [int]$dmaInterop.current.homeLocationGeoId -ne [int]$dmaInterop.restore.homeLocationGeoId) {
        Add-AuditFinding -Findings $findings -Severity Error -Id 'dma-home-location-restore' -Category 'dmaInterop' -Name 'Home location restore' -Message "Current home location GeoID '$($dmaInterop.current.homeLocationGeoId)' does not match configured restore GeoID '$($dmaInterop.restore.homeLocationGeoId)'."
    }
    if (-not [bool]$dmaInterop.autoTimeZone.disabled) {
        Add-AuditFinding -Findings $findings -Severity Error -Id 'dma-auto-time-zone-active' -Category 'dmaInterop' -Name 'Auto Time Zone Updater' -Message 'DMA interoperability is enabled, but Auto Time Zone Updater is not disabled. Windows may automatically change the time zone after the user sets it.'
    }
}

$recommendedClassification = @()
if ($recommended -and -not $recommended.PSObject.Properties['readError']) {
    $recommendedClassification = @(Get-AuditRecommendedClassification -Recommended @($recommended))
}
elseif ($recommended -and $recommended.PSObject.Properties['readError']) {
    Add-AuditFinding -Findings $findings -Severity Warning -Id 'recommended-list-read' -Category 'recommended-list' -Name $RecommendedListPath -Message $recommended.readError
}

$summary = [ordered]@{
    info     = @($findings | Where-Object { $_.severity -eq 'Info' }).Count
    warning  = @($findings | Where-Object { $_.severity -eq 'Warning' }).Count
    error    = @($findings | Where-Object { $_.severity -eq 'Error' }).Count
    observed = [ordered]@{
        provisionedAppx = $provisionedAppx.Count
        installedAppx   = $installedAppx.Count
        win32           = $win32Entries.Count
    }
}

$report = [ordered]@{
    schemaVersion           = 1
    generatedAt             = Get-Date -Format o
    setupProfilePath        = $SetupProfilePath
    recommendedListPath     = $RecommendedListPath
    expectedRemovalPrefixes = @($expectedRemovalPrefixes)
    summary                 = $summary
    findings                = @($findings.ToArray())
    observed                = [ordered]@{
        provisionedAppx = @($provisionedAppx)
        installedAppx   = @($installedAppx)
        win32           = @($win32Entries)
        platform        = $platform
        dmaInterop      = $dmaInterop
        recommended     = @($recommendedClassification)
    }
}

$json = $report | ConvertTo-Json -Depth 12
$outDir = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outDir)) {
    $null = New-Item -ItemType Directory -Path $outDir -Force -ErrorAction SilentlyContinue
}
$json | Set-Content -LiteralPath $OutputPath -Encoding UTF8

if ($AsJson) {
    $json
}
else {
    Write-Host "Live install audit: $($summary.error) error(s), $($summary.warning) warning(s)."
    Write-Host "Report: $OutputPath"
}
