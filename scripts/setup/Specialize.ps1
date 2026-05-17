# Machine-wide policy and service tweaks during specialize (SYSTEM).
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
}
catch {
    "Specialize profile read failed: $_" | Out-File (Join-Path $logDir 'Specialize_errors.log') -Append
}

function Get-SpecializeSetupProfileBool {
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

function Get-SpecializeNestedSetupProfileBool {
    param(
        [string]$Section,
        [string]$Nested,
        [string]$Name,
        [bool]$Default
    )
    if (-not $setupProfile) { return $Default }
    $sectionProp = $setupProfile.PSObject.Properties[$Section]
    if (-not $sectionProp) { return $Default }
    $nestedProp = $sectionProp.Value.PSObject.Properties[$Nested]
    if (-not $nestedProp) { return $Default }
    $valueProp = $nestedProp.Value.PSObject.Properties[$Name]
    if (-not $valueProp) { return $Default }
    return [bool]$valueProp.Value
}

function Get-SpecializeNestedSetupProfileInt {
    param(
        [string]$Section,
        [string]$Nested,
        [string]$Name,
        [int]$Default
    )
    if (-not $setupProfile) { return $Default }
    $sectionProp = $setupProfile.PSObject.Properties[$Section]
    if (-not $sectionProp) { return $Default }
    $nestedProp = $sectionProp.Value.PSObject.Properties[$Nested]
    if (-not $nestedProp) { return $Default }
    $valueProp = $nestedProp.Value.PSObject.Properties[$Name]
    if (-not $valueProp) { return $Default }
    try { return [int]$valueProp.Value } catch { return $Default }
}

function Set-SpecializeRegistryValue {
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

function Invoke-SpecializeRegistrySet {
    param(
        [Parameter(Mandatory)]
        [object[]]$Entries
    )
    foreach ($entry in $Entries) {
        Set-SpecializeRegistryValue -Path $entry.Path -Name $entry.Name -Type $entry.Type -Data $entry.Data
    }
}

$disableFastStartup = Get-SpecializeSetupProfileBool -Section 'windowsPolicy' -Name 'disableFastStartup' -Default $false
$preventDeviceEncryption = Get-SpecializeSetupProfileBool -Section 'windowsPolicy' -Name 'preventDeviceEncryption' -Default $false
$dmaInterop = Get-SpecializeNestedSetupProfileBool -Section 'regional' -Nested 'dmaInterop' -Name 'enabled' -Default $true
$dmaSetupGeoId = Get-SpecializeNestedSetupProfileInt -Section 'regional' -Nested 'dmaInterop' -Name 'setupHomeLocationGeoId' -Default 94

$scripts = @(
    {
        if (-not $dmaInterop) { return }
        try {
            Set-WinHomeLocation -GeoId $dmaSetupGeoId -ErrorAction Stop
        }
        catch {
            "DMA setup region stamp failed for GeoID ${dmaSetupGeoId}: $_" | Out-File (Join-Path $logDir 'Specialize_errors.log') -Append
        }
    }
    { Set-SpecializeRegistryValue -Path 'HKLM\SYSTEM\Setup\MoSetup' -Name AllowUpgradesWithUnsupportedTPMOrCPU -Type REG_DWORD -Data 1 }
    { net.exe accounts /maxpwage:UNLIMITED }
    {
        Invoke-SpecializeRegistrySet -Entries @(
            @{ Path = 'HKLM\Software\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableCloudOptimizedContent'; Type = 'REG_DWORD'; Data = '1' },
            @{ Path = 'HKLM\Software\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableSoftLanding'; Type = 'REG_DWORD'; Data = '1' },
            @{ Path = 'HKLM\SOFTWARE\Policies\Microsoft\SQMClient\Windows'; Name = 'CEIPEnable'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'AITEnable'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'DisableInventory'; Type = 'REG_DWORD'; Data = '1' },
            @{ Path = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'SettingsPageVisibility'; Type = 'REG_SZ'; Data = 'hide:home' }
        )
    }
    {
        Invoke-SpecializeRegistrySet -Entries @(
            @{ Path = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'AppsUseLightTheme'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'SystemUsesLightTheme'; Type = 'REG_DWORD'; Data = '0' }
        )
    }
    { Set-SpecializeRegistryValue -Path 'HKLM\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -Type REG_DWORD -Data 1 }
    { Set-SpecializeRegistryValue -Path 'HKLM\SOFTWARE\Policies\Microsoft\Dsh' -Name AllowNewsAndInterests -Type REG_DWORD -Data 0 }
    { Set-SpecializeRegistryValue -Path 'HKLM\Software\Policies\Microsoft\Edge' -Name HideFirstRunExperience -Type REG_DWORD -Data 1 }
    {
        Invoke-SpecializeRegistrySet -Entries @(
            @{ Path = 'HKLM\Software\Policies\Microsoft\Edge\Recommended'; Name = 'BackgroundModeEnabled'; Type = 'REG_DWORD'; Data = '0' },
            @{ Path = 'HKLM\Software\Policies\Microsoft\Edge\Recommended'; Name = 'StartupBoostEnabled'; Type = 'REG_DWORD'; Data = '0' }
        )
    }

    # ── Diagnostics: show stop code on blue screens instead of generic face ───
    { Set-SpecializeRegistryValue -Path 'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl' -Name DisplayParameters -Type REG_DWORD -Data 1 }

    # ── Delivery Optimization: disable uploading updates to other PCs ─────────
    { Set-SpecializeRegistryValue -Path 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -Name DODownloadMode -Type REG_DWORD -Data 0 }

    # ── SSH agent: auto-start so SSH keys work with Git without manual setup ─
    { Set-SpecializeRegistryValue -Path 'HKLM\SYSTEM\CurrentControlSet\Services\ssh-agent' -Name Start -Type REG_DWORD -Data 2 }
)

if ($disableFastStartup) {
    $scripts += { Set-SpecializeRegistryValue -Path 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Type REG_DWORD -Data 0 }
}
if ($preventDeviceEncryption) {
    $scripts += { Set-SpecializeRegistryValue -Path 'HKLM\SYSTEM\CurrentControlSet\Control\BitLocker' -Name PreventDeviceEncryption -Type REG_DWORD -Data 1 }
}

$errors = @()
foreach ($s in $scripts) {
    try { & $s } catch { $errors += "Specialize: $_" }
}
if ($errors.Count -gt 0) {
    ($errors -join "`n") | Out-File (Join-Path $logDir 'Specialize_errors.log') -Append
}
