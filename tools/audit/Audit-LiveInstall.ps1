#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SetupProfilePath = 'C:\Windows\Setup\Scripts\WinMintSetupProfile.json',
    [string]$RecommendedListPath = '',
    [string]$OutputPath = '',
    [switch]$IncludeInventory,
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
                    nonRemovable    = [bool]$_.NonRemovable
                    signatureKind   = [string]$_.SignatureKind
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

function Get-AuditWindowsOptionalFeatureStatus {
    param([string]$Name)
    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction SilentlyContinue
        if (-not $feature) { return [ordered]@{ name = $Name; present = $false; state = '' } }
        return [ordered]@{ name = $Name; present = $true; state = [string]$feature.State }
    }
    catch {
        return [ordered]@{ name = $Name; present = $false; state = ''; error = $_.Exception.Message }
    }
}

function Get-AuditScheduledTaskMatches {
    param([string[]]$Patterns = @())
    $regex = '(' + (($Patterns | ForEach-Object { [regex]::Escape([string]$_) }) -join '|') + ')'
    if ([string]::IsNullOrWhiteSpace($regex) -or $regex -eq '()') { return @() }
    try {
        @(Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -match $regex -or $_.TaskPath -match $regex } |
            ForEach-Object {
                [ordered]@{
                    path = [string]$_.TaskPath
                    name = [string]$_.TaskName
                    state = [string]$_.State
                }
            })
    }
    catch { @() }
}

function Get-AuditScheduledTaskInventory {
    $tasks = [System.Collections.Generic.List[object]]::new()
    try {
        foreach ($task in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
            $include = $false
            $taskPath = [string]$task.TaskPath
            $taskName = [string]$task.TaskName
            $state = [string]$task.State
            if ($taskPath -notlike '\Microsoft\Windows\*') {
                $include = $true
            }
            foreach ($pattern in @('Copilot', 'Recall', 'WindowsAI', 'DevHome', 'Outlook', 'Chat', 'Xbox', 'OneDrive', 'EdgeUpdate', 'GameAssist')) {
                if ($taskPath -match [regex]::Escape($pattern) -or $taskName -match [regex]::Escape($pattern)) {
                    $include = $true
                    break
                }
            }
            if (-not $include) { continue }

            $tasks.Add([ordered]@{
                    path = $taskPath
                    name = $taskName
                    state = $state
                }) | Out-Null
        }
    }
    catch { }
    @($tasks.ToArray() | Sort-Object path, name -Unique)
}

function Get-AuditServiceInventory {
    $services = [System.Collections.Generic.List[object]]::new()
    try {
        foreach ($service in @(Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue)) {
            $services.Add([ordered]@{
                    name        = [string]$service.Name
                    displayName = [string]$service.DisplayName
                    state       = [string]$service.State
                    startMode   = [string]$service.StartMode
                    startName   = [string]$service.StartName
                    pathName    = [string]$service.PathName
                }) | Out-Null
        }
    }
    catch { }
    @($services.ToArray() | Sort-Object name -Unique)
}

function Get-AuditStartupInventory {
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($root in @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        )) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        try {
            $item = Get-ItemProperty -LiteralPath $root -ErrorAction SilentlyContinue
            foreach ($property in @($item.PSObject.Properties)) {
                if ($property.Name -in @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) { continue }
                $entries.Add([ordered]@{
                        source = $root
                        name   = [string]$property.Name
                        value  = [string]$property.Value
                    }) | Out-Null
            }
        }
        catch { }
    }
    foreach ($folder in @(
            [Environment]::GetFolderPath('Startup'),
            [Environment]::GetFolderPath('CommonStartup')
        )) {
        if ([string]::IsNullOrWhiteSpace($folder) -or -not (Test-Path -LiteralPath $folder)) { continue }
        try {
            foreach ($item in @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue)) {
                $entries.Add([ordered]@{
                        source = $folder
                        name   = [string]$item.Name
                        value  = [string]$item.FullName
                    }) | Out-Null
            }
        }
        catch { }
    }
    @($entries.ToArray() | Sort-Object source, name -Unique)
}

function Test-AuditRegistryValue {
    param([string]$Path, [string]$Name)
    try {
        $value = (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue).$Name
        return ($null -ne $value)
    }
    catch { return $false }
}

function Get-AuditRegistryValue {
    param([string]$Path, [string]$Name)
    try {
        return (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue).$Name
    }
    catch { return $null }
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
    $culture = $null
    try { $culture = Get-Culture } catch { }
    $homeLocation = $null
    try { $homeLocation = Get-WinHomeLocation } catch { }
    $autoTimeZoneService = Get-AuditServiceStatus -Name 'tzautoupdate'
    $locationService = Get-AuditServiceStatus -Name 'lfsvc'
    $autoTimeZoneStart = $null
    try {
        $autoTimeZoneStart = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate' -Name Start -ErrorAction SilentlyContinue).Start
    } catch { }
    $restoreLocationServices = [bool](Get-AuditNestedProfileValue -Profile $SetupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'restoreLocationServices' -Default $true)

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
            culture = if ($culture) { [string]$culture.Name } else { '' }
            homeLocationGeoId = if ($homeLocation) { [int]$homeLocation.GeoId } else { 0 }
            homeLocation = if ($homeLocation) { [string]$homeLocation.HomeLocation } else { '' }
        }
        locationServices = [ordered]@{
            expectedEnabled = $restoreLocationServices
            service = $locationService
            disableLocationPolicy = Get-AuditRegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' -Name 'DisableLocation'
            disableProviderPolicy = Get-AuditRegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' -Name 'DisableWindowsLocationProvider'
        }
        autoTimeZone = [ordered]@{
            service = $autoTimeZoneService
            registryStart = $autoTimeZoneStart
            disabled = ($autoTimeZoneService.present -and [string]$autoTimeZoneService.startType -eq 'Disabled' -and $null -ne $autoTimeZoneStart -and [int]$autoTimeZoneStart -eq 4)
            policy = if ($restoreLocationServices) {
                'Location services are expected on; Auto Time Zone Updater should not be disabled by WinMint.'
            } else {
                'Location services are expected off; Auto Time Zone Updater should be disabled.'
            }
        }
    }
}

function Get-AuditPolicyProbe {
    param([object]$SetupProfile)

    $privacyLocation = [bool](Get-AuditProfileValue -Profile $SetupProfile -Section 'privacy' -Name 'location' -Default $true)
    $dualBoot = [bool](Get-AuditProfileValue -Profile $SetupProfile -Section 'windowsPolicy' -Name 'dualBoot' -Default $false)
    $storageRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'
    $modernStandbyRoot = 'HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9'

    [ordered]@{
        location = [ordered]@{
            expectedEnabled = $privacyLocation
            disableLocation = Get-AuditRegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' -Name 'DisableLocation'
            disableWindowsLocationProvider = Get-AuditRegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' -Name 'DisableWindowsLocationProvider'
            allowFindMyDevice = Get-AuditRegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice' -Name 'AllowFindMyDevice'
        }
        storageSense = [ordered]@{
            '01' = Get-AuditRegistryValue -Path $storageRoot -Name '01'
            '04' = Get-AuditRegistryValue -Path $storageRoot -Name '04'
            '08' = Get-AuditRegistryValue -Path $storageRoot -Name '08'
            '32' = Get-AuditRegistryValue -Path $storageRoot -Name '32'
        }
        modernStandby = [ordered]@{
            ac = Get-AuditRegistryValue -Path $modernStandbyRoot -Name 'ACSettingIndex'
            dc = Get-AuditRegistryValue -Path $modernStandbyRoot -Name 'DCSettingIndex'
        }
        wpbt = [ordered]@{
            disableWpbtExecution = Get-AuditRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'DisableWpbtExecution'
        }
        dualBootClock = [ordered]@{
            expected = $dualBoot
            realTimeIsUniversal = Get-AuditRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -Name 'RealTimeIsUniversal'
        }
        oobeRehydration = [ordered]@{
            devHomeOobe = Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate'
            outlookOobe = Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate'
            chatOobe = Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\ChatAutoInstall'
            devHomeWorkCompleted = Get-AuditRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate' -Name 'workCompleted'
            outlookWorkCompleted = Get-AuditRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate' -Name 'workCompleted'
            chatWorkCompleted = Get-AuditRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\ChatAutoInstall' -Name 'workCompleted'
        }
        uac = [ordered]@{
            enableLua = Get-AuditRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA'
            consentPromptBehaviorAdmin = Get-AuditRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'ConsentPromptBehaviorAdmin'
            promptOnSecureDesktop = Get-AuditRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'PromptOnSecureDesktop'
        }
        homePrivacy = [ordered]@{
            allowTelemetry = Get-AuditRegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry'
            doNotShowFeedbackNotifications = Get-AuditRegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'DoNotShowFeedbackNotifications'
        }
        gaming = [ordered]@{
            allowAutoGameMode = Get-AuditRegistryValue -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AllowAutoGameMode'
            hwSchMode = Get-AuditRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode'
        }
        desktopUi = [ordered]@{
            lastActiveClick = Get-AuditRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'LastActiveClick'
            snapAssist = Get-AuditRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'SnapAssist'
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
$policy = Get-AuditPolicyProbe -SetupProfile $setupProfile
$debugInventory = $null
if ($IncludeInventory) {
    $debugInventory = [ordered]@{
        note = 'Debug-only inventory captured because live install audit was explicitly selected. WinMint does not capture this on normal builds.'
        services = @(Get-AuditServiceInventory)
        scheduledTasks = @(Get-AuditScheduledTaskInventory)
        startupEntries = @(Get-AuditStartupInventory)
    }
}
$aiRemoval = if ($setupProfile -and $setupProfile.PSObject.Properties['aiRemoval']) { $setupProfile.aiRemoval } else { $null }
$aiPrefixes = @()
$aiFeatureNames = @()
$aiServices = @()
$aiTaskPatterns = @()
if ($aiRemoval) {
    $aiPrefixes = @(ConvertTo-AuditStringArray $aiRemoval.appxPrefixes)
    $aiFeatureNames = @(ConvertTo-AuditStringArray (@($aiRemoval.optionalFeatures) + @(if ($aiRemoval.removeRecall) { 'Recall' })))
    if ($aiFeatureNames.Count -eq 0 -and [bool]$aiRemoval.removeRecall) { $aiFeatureNames = @('Recall') }
    $aiServices = @(ConvertTo-AuditStringArray $aiRemoval.servicesToDisable)
    if ($aiServices.Count -eq 0 -and [bool]$aiRemoval.disableAiServices) { $aiServices = @('WSAIFabricSvc') }
    $aiTaskPatterns = @(ConvertTo-AuditStringArray $aiRemoval.scheduledTaskPatternsToDisable)
    if ($aiTaskPatterns.Count -eq 0 -and [bool]$aiRemoval.disableAiTasks) { $aiTaskPatterns = @('Recall', 'WindowsAI', 'Copilot') }
}

# Components Microsoft rehydrates after logon and provides NO supported way to durably
# remove or prevent. Verified for Edge Game Assist: it is not provisioned (so offline
# removal cannot catch it), Edge re-stages it even on a DMA-locked machine, a supported
# appx uninstall does not make it stay gone, and there is no official Edge policy to
# block it (GameAssistEnabled is folklore). WinMint disables its user-facing surfaces
# instead (HubsSidebarEnabled / AllowGamesMenu). Report reappearance as Info, not drift,
# so a clean build is not perpetually flagged for something no supported mechanism fixes.
$rehydratedNoPreventionPrefixes = @('Microsoft.Edge.GameAssist')
$rehydratedNote = 'Edge re-stages this after logon; Microsoft documents no supported prevention (DMA-verified). Its surfaces are disabled via Edge policy. Tracked as Info, not drift.'

foreach ($prefix in $expectedRemovalPrefixes) {
    $rehydrated = $rehydratedNoPreventionPrefixes -contains $prefix
    $sev = if ($rehydrated) { 'Info' } else { 'Warning' }
    foreach ($pkg in @($provisionedAppx | Where-Object { [string]$_.packageName -like "*$prefix*" -or [string]$_.displayName -like "*$prefix*" })) {
        $msg = if ($rehydrated) { "Provisioned AppX matches '$prefix'. $rehydratedNote" } else { "Provisioned AppX still matches expected removal prefix '$prefix'." }
        Add-AuditFinding -Findings $findings -Severity $sev -Id 'appx-provisioned-drift' -Category 'appx' -Name ([string]$pkg.packageName) -Message $msg
    }
    foreach ($pkg in @($installedAppx | Where-Object { ([string]$_.packageFullName -like "*$prefix*" -or [string]$_.name -like "*$prefix*") -and -not ([bool]$_.nonRemovable -or [string]$_.signatureKind -eq 'System') })) {
        $msg = if ($rehydrated) { "Installed AppX matches '$prefix'. $rehydratedNote" } else { "Installed AppX still matches expected removal prefix '$prefix'." }
        Add-AuditFinding -Findings $findings -Severity $sev -Id 'appx-installed-drift' -Category 'appx' -Name ([string]$pkg.packageFullName) -Message $msg
    }
}

foreach ($prefix in $aiPrefixes) {
    $rehydrated = $rehydratedNoPreventionPrefixes -contains $prefix
    $sev = if ($rehydrated) { 'Info' } else { 'Warning' }
    foreach ($pkg in @($provisionedAppx | Where-Object { [string]$_.packageName -like "*$prefix*" -or [string]$_.displayName -like "*$prefix*" })) {
        $msg = if ($rehydrated) { "Provisioned AI AppX matches '$prefix'. $rehydratedNote" } else { "Provisioned AI AppX still matches expected removal prefix '$prefix'." }
        Add-AuditFinding -Findings $findings -Severity $sev -Id 'ai-appx-provisioned-drift' -Category 'ai' -Name ([string]$pkg.packageName) -Message $msg
    }
    foreach ($pkg in @($installedAppx | Where-Object { ([string]$_.packageFullName -like "*$prefix*" -or [string]$_.name -like "*$prefix*") -and -not ([bool]$_.nonRemovable -or [string]$_.signatureKind -eq 'System') })) {
        $msg = if ($rehydrated) { "Installed AI AppX matches '$prefix'. $rehydratedNote" } else { "Installed AI AppX still matches expected removal prefix '$prefix'." }
        Add-AuditFinding -Findings $findings -Severity $sev -Id 'ai-appx-installed-drift' -Category 'ai' -Name ([string]$pkg.packageFullName) -Message $msg
    }
}

$aiFeatureStatus = @($aiFeatureNames | ForEach-Object { Get-AuditWindowsOptionalFeatureStatus -Name ([string]$_) })
foreach ($feature in $aiFeatureStatus) {
    if ($feature.present -and [string]$feature.state -match 'Enabled') {
        Add-AuditFinding -Findings $findings -Severity Error -Id 'ai-optional-feature-enabled' -Category 'ai' -Name ([string]$feature.name) -Message "AI optional feature '$($feature.name)' is still enabled."
    }
}

$aiServiceStatus = @($aiServices | ForEach-Object { Get-AuditServiceStatus -Name ([string]$_) })
foreach ($svc in $aiServiceStatus) {
    if ($svc.present -and [string]$svc.startType -ne 'Disabled' -and [string]$svc.status -ne 'Stopped') {
        Add-AuditFinding -Findings $findings -Severity Warning -Id 'ai-service-active' -Category 'ai' -Name ([string]$svc.name) -Message "AI service '$($svc.name)' is present and not disabled/stopped."
    }
}

$aiTasks = @(Get-AuditScheduledTaskMatches -Patterns $aiTaskPatterns)
foreach ($task in $aiTasks) {
    if ([string]$task.state -ne 'Disabled') {
        Add-AuditFinding -Findings $findings -Severity Warning -Id 'ai-task-enabled' -Category 'ai' -Name "$($task.path)$($task.name)" -Message 'AI-related scheduled task is not disabled.'
    }
}

if ($aiRemoval -and [string]$aiRemoval.policy -ne 'Core') {
    foreach ($expected in @(
            @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI', 'AllowRecallEnablement'),
            @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI', 'TurnOffSavingSnapshots'),
            @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI', 'DisableSettingsAgent'),
            @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'EdgeEntraCopilotPageContext'),
            @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'GenAILocalFoundationalModelSettings'),
            @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'NewTabPageBingChatEnabled'),
            @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\generativeAI', 'Value'),
            @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\systemAIModels', 'Value'),
            @('HKCU:\Software\Microsoft\Windows\Shell\ClickToDo', 'DisableClickToDo'),
            @('HKCU:\Software\Microsoft\Office\16.0\Word\Options', 'EnableCopilot'),
            @('HKCU:\Software\Microsoft\Office\16.0\Excel\Options', 'EnableCopilot')
        )) {
        if (-not (Test-AuditRegistryValue -Path $expected[0] -Name $expected[1])) {
            Add-AuditFinding -Findings $findings -Severity Warning -Id 'ai-policy-missing' -Category 'ai' -Name "$($expected[0])\$($expected[1])" -Message 'Expected serviceable full AI registry policy was not found.'
        }
    }
}

foreach ($required in @(
        @('store', 'Store AppX', $platform.appx.store),
        @('desktop-app-installer', 'Desktop App Installer AppX', $platform.appx.desktopAppInstaller),
        # winget.exe ships as the DesktopAppInstaller execution alias; that per-user PATH
        # alias registers a moment AFTER first logon, so a PATH probe run that early (as the
        # FirstLogon agent does) can miss it even though winget is installed and provisioned.
        # Treat winget as present when the App Installer package is present (it provides
        # winget) OR the command already resolves - avoids a benign first-logon false error.
        @('winget', 'winget command', ($platform.commands.winget -or $platform.appx.desktopAppInstaller)),
        @('webview2-runtime', 'Microsoft Edge WebView2 Runtime', $platform.runtime.webView2Runtime),
        @('defender-service', 'Defender service', $platform.services.defender.present),
        @('firewall-service', 'Firewall service', $platform.services.firewall.present),
        @('windows-update-service', 'Windows Update service', $platform.services.windowsUpdate.present),
        @('bits-service', 'BITS service', $platform.services.bits.present),
        @('waasmedic-service', 'WaaSMedic service', $platform.services.waaSMedic.present)
        # NOTE: HNS (Host Network Service) is intentionally NOT required here. It is an
        # on-demand service that ships/starts with WSL2 / containers / Hyper-V networking, so
        # it is legitimately absent on a base install and must not be flagged as an error.
    )) {
    if (-not [bool]$required[2]) {
        Add-AuditFinding -Findings $findings -Severity Error -Id $required[0] -Category 'platform' -Name $required[1] -Message "$($required[1]) is missing."
    }
}

# Microsoft Edge: on DMA builds, WinMint removes the browser through the normal
# supported app uninstaller. If the removal request leaves Edge present, report it as
# an incomplete normal uninstall. WebView2 is required either way (checked above).
$edgeRemovalRequested = [bool](Get-AuditProfileValue -Profile $setupProfile -Section 'edge' -Name 'removeEdge' -Default $false)
if ($edgeRemovalRequested) {
    if ([bool]$platform.runtime.edgeRuntime) {
        Add-AuditFinding -Findings $findings -Severity Warning -Id 'edge-removal-incomplete' -Category 'platform' -Name 'Microsoft Edge' -Message 'Edge removal was requested, but the supported app uninstaller left the Edge browser present. WebView2 preserved.'
    }
    else {
        Add-AuditFinding -Findings $findings -Severity Info -Id 'edge-removed' -Category 'platform' -Name 'Microsoft Edge' -Message 'Edge browser absent; WebView2 runtime preserved.'
    }
}
elseif (-not [bool]$platform.runtime.edgeRuntime) {
    Add-AuditFinding -Findings $findings -Severity Error -Id 'edge-runtime' -Category 'platform' -Name 'Microsoft Edge runtime' -Message 'Microsoft Edge runtime is missing.'
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
    if (-not [string]::IsNullOrWhiteSpace([string]$dmaInterop.restore.userLocale) -and [string]$dmaInterop.current.culture -ne [string]$dmaInterop.restore.userLocale) {
        Add-AuditFinding -Findings $findings -Severity Error -Id 'dma-culture-restore' -Category 'dmaInterop' -Name 'Culture restore' -Message "Current culture '$($dmaInterop.current.culture)' does not match configured restore culture '$($dmaInterop.restore.userLocale)'."
    }
    if ([int]$dmaInterop.restore.homeLocationGeoId -gt 0 -and [int]$dmaInterop.current.homeLocationGeoId -ne [int]$dmaInterop.restore.homeLocationGeoId) {
        Add-AuditFinding -Findings $findings -Severity Error -Id 'dma-home-location-restore' -Category 'dmaInterop' -Name 'Home location restore' -Message "Current home location GeoID '$($dmaInterop.current.homeLocationGeoId)' does not match configured restore GeoID '$($dmaInterop.restore.homeLocationGeoId)'."
    }
    if (-not [bool]$dmaInterop.locationServices.expectedEnabled -and -not [bool]$dmaInterop.autoTimeZone.disabled) {
        Add-AuditFinding -Findings $findings -Severity Error -Id 'dma-auto-time-zone-active' -Category 'dmaInterop' -Name 'Auto Time Zone Updater' -Message 'DMA interoperability is enabled, but Auto Time Zone Updater is not disabled. Windows may automatically change the time zone after the user sets it.'
    }
    if ([bool]$dmaInterop.locationServices.expectedEnabled -and [bool]$dmaInterop.autoTimeZone.disabled) {
        Add-AuditFinding -Findings $findings -Severity Error -Id 'dma-auto-time-zone-disabled' -Category 'dmaInterop' -Name 'Auto Time Zone Updater' -Message 'Location services are expected on, but Auto Time Zone Updater is disabled.'
    }
    if ($dmaInterop.locationServices.expectedEnabled) {
        if ($null -ne $dmaInterop.locationServices.disableLocationPolicy -and [int]$dmaInterop.locationServices.disableLocationPolicy -ne 0) {
            Add-AuditFinding -Findings $findings -Severity Error -Id 'location-services-blocked' -Category 'location' -Name 'Location services' -Message 'Location services are expected to be enabled, but DisableLocation policy is set.'
        }
    }
    else {
        if ($null -eq $dmaInterop.locationServices.disableLocationPolicy -or [int]$dmaInterop.locationServices.disableLocationPolicy -ne 1) {
            Add-AuditFinding -Findings $findings -Severity Warning -Id 'location-services-not-blocked' -Category 'location' -Name 'Location services' -Message 'Location services are expected to be disabled, but DisableLocation policy is not set.'
        }
    }
}

if ($policy.location.expectedEnabled) {
    if ($null -ne $policy.location.disableLocation -and [int]$policy.location.disableLocation -ne 0) {
        Add-AuditFinding -Findings $findings -Severity Error -Id 'location-disabled-policy-present' -Category 'location' -Name 'DisableLocation' -Message 'Location is expected on, but DisableLocation policy is present.'
    }
    if ($null -ne $policy.location.allowFindMyDevice -and [int]$policy.location.allowFindMyDevice -eq 0) {
        Add-AuditFinding -Findings $findings -Severity Error -Id 'find-my-device-blocked' -Category 'location' -Name 'Find My Device' -Message 'Location is expected on, but Find My Device is blocked.'
    }
}
else {
    if ($null -eq $policy.location.disableLocation -or [int]$policy.location.disableLocation -ne 1) {
        Add-AuditFinding -Findings $findings -Severity Warning -Id 'location-disabled-policy-missing' -Category 'location' -Name 'DisableLocation' -Message 'Location is expected off, but DisableLocation policy is not set.'
    }
    if ($null -eq $policy.location.allowFindMyDevice -or [int]$policy.location.allowFindMyDevice -ne 0) {
        Add-AuditFinding -Findings $findings -Severity Warning -Id 'find-my-device-not-blocked' -Category 'location' -Name 'Find My Device' -Message 'Location is expected off, but Find My Device is not blocked.'
    }
}

foreach ($pair in @(@('01', 1), @('04', 1), @('08', 1), @('32', 0))) {
    $actual = if ($policy.storageSense -is [System.Collections.IDictionary]) {
        $policy.storageSense[$pair[0]]
    } elseif ($policy.storageSense.PSObject.Properties[$pair[0]]) {
        $policy.storageSense.PSObject.Properties[$pair[0]].Value
    } else {
        $null
    }
    if ($null -eq $actual -or [int]$actual -ne [int]$pair[1]) {
        Add-AuditFinding -Findings $findings -Severity Warning -Id 'storage-sense-policy' -Category 'storageSense' -Name $pair[0] -Message "Storage Sense policy '$($pair[0])' expected '$($pair[1])' but found '$actual'."
    }
}
if ($null -eq $policy.modernStandby.ac -or [int]$policy.modernStandby.ac -ne 0 -or
    $null -eq $policy.modernStandby.dc -or [int]$policy.modernStandby.dc -ne 0) {
    Add-AuditFinding -Findings $findings -Severity Warning -Id 'modern-standby-network' -Category 'power' -Name 'Modern Standby network' -Message 'Modern Standby network policy should be disabled for AC and DC.'
}
if ($null -eq $policy.wpbt.disableWpbtExecution -or [int]$policy.wpbt.disableWpbtExecution -ne 1) {
    Add-AuditFinding -Findings $findings -Severity Warning -Id 'wpbt-policy' -Category 'platform' -Name 'DisableWpbtExecution' -Message 'WPBT execution should be disabled in WinMint Minimal.'
}
if ($policy.dualBootClock.expected) {
    if ($null -eq $policy.dualBootClock.realTimeIsUniversal -or [int]$policy.dualBootClock.realTimeIsUniversal -ne 1) {
        Add-AuditFinding -Findings $findings -Severity Warning -Id 'dual-boot-clock-policy' -Category 'dualBoot' -Name 'RealTimeIsUniversal' -Message 'Dual-boot builds should set RealTimeIsUniversal.'
    }
}
elseif ($null -ne $policy.dualBootClock.realTimeIsUniversal) {
    Add-AuditFinding -Findings $findings -Severity Error -Id 'dual-boot-clock-policy-unexpected' -Category 'dualBoot' -Name 'RealTimeIsUniversal' -Message 'RealTimeIsUniversal is present on a non-dual-boot build.'
}
foreach ($oobe in @(
        @('DevHomeUpdate', $policy.oobeRehydration.devHomeOobe, $policy.oobeRehydration.devHomeWorkCompleted),
        @('OutlookUpdate', $policy.oobeRehydration.outlookOobe, $policy.oobeRehydration.outlookWorkCompleted),
        @('ChatAutoInstall', $policy.oobeRehydration.chatOobe, $policy.oobeRehydration.chatWorkCompleted)
    )) {
    if ([bool]$oobe[1]) {
        Add-AuditFinding -Findings $findings -Severity Warning -Id 'oobe-rehydration-key-present' -Category 'oobe' -Name $oobe[0] -Message 'OOBE rehydration key is still present.'
    }
    if ($null -eq $oobe[2] -or [int]$oobe[2] -ne 1) {
        Add-AuditFinding -Findings $findings -Severity Warning -Id 'oobe-rehydration-work-not-complete' -Category 'oobe' -Name $oobe[0] -Message 'OOBE rehydration workCompleted marker is missing.'
    }
}
if ($null -ne $policy.uac.promptOnSecureDesktop -and [int]$policy.uac.promptOnSecureDesktop -eq 0) {
    Add-AuditFinding -Findings $findings -Severity Error -Id 'uac-secure-desktop-disabled' -Category 'security' -Name 'PromptOnSecureDesktop' -Message 'WinMint must not disable the UAC secure desktop.'
}
if ($null -ne $policy.uac.enableLua -and [int]$policy.uac.enableLua -eq 0) {
    Add-AuditFinding -Findings $findings -Severity Error -Id 'uac-disabled' -Category 'security' -Name 'EnableLUA' -Message 'WinMint must not disable UAC.'
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
        services        = if ($debugInventory) { @($debugInventory.services).Count } else { $null }
        scheduledTasks  = if ($debugInventory) { @($debugInventory.scheduledTasks).Count } else { $null }
        startupEntries  = if ($debugInventory) { @($debugInventory.startupEntries).Count } else { $null }
    }
}

$report = [ordered]@{
    schemaVersion           = 2
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
        policies        = $policy
        ai              = [ordered]@{
            policy = if ($aiRemoval) { [string]$aiRemoval.policy } else { 'Core' }
            appxPrefixes = @($aiPrefixes)
            optionalFeatures = @($aiFeatureStatus)
            services = @($aiServiceStatus)
            scheduledTasks = @($aiTasks)
        }
        recommended     = @($recommendedClassification)
        debugInventory  = $debugInventory
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
