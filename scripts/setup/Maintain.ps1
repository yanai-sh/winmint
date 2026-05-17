#Requires -Version 5.1
# Post-update drift control (optional). When registered as a boot scheduled task from
# SetupComplete.ps1 ($RegisterWinWSMaintainScheduledTask = $true), this re-stamps registry
# tweaks and re-deprovision AppX when Windows re-provisions packages after feature updates.
# Default installs do NOT register that task — the script still ships for manual runs or revisit.
# Two on-disk artifacts must persist when using Maintain:
#   - C:\Windows\Setup\Scripts\Maintain.ps1
#   - C:\Windows\Setup\Scripts\WinWSSetupProfile.json
# FirstLogon.ps1 preserves both after agent success.
$ErrorActionPreference = 'Continue'
$payloadDir = 'C:\Windows\Setup\Scripts'                       # staged config (read-only here)
$logDir     = Join-Path $env:ProgramData 'WinWS\Logs'          # writable log + state
$null = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue
$logFile   = Join-Path $logDir 'Maintain.log'
$buildFile = Join-Path $logDir 'Maintain_last_build.txt'
$setupProfilePath = Join-Path $payloadDir 'WinWSSetupProfile.json'

function Write-MaintLog { param([string]$Msg) "$(Get-Date -Format 'o') $Msg" | Out-File $logFile -Append }

function Read-MaintSetupProfile {
    try {
        if (Test-Path -LiteralPath $setupProfilePath) {
            return Get-Content -LiteralPath $setupProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    }
    catch {
        Write-MaintLog "Setup profile read failed: $_"
    }
    return $null
}

function Get-MaintAppxRemovalPrefixes {
    param($SetupProfile)

    if ($SetupProfile -and $SetupProfile.PSObject.Properties['appxRemovalPrefixes']) {
        $fromProfile = @(
            @($SetupProfile.appxRemovalPrefixes) |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                ForEach-Object { [string]$_ }
        )
        if ($fromProfile.Count -gt 0) { return $fromProfile }
    }

    @(
        'Clipchamp.Clipchamp', 'Microsoft.BingNews', 'Microsoft.BingSearch', 'Microsoft.BingWeather',
        'Microsoft.GetHelp', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftSolitaireCollection',
        'Microsoft.Microsoft3DViewer', 'Microsoft.MixedReality.Portal',
        'Microsoft.WindowsCalculator', 'Microsoft.Whiteboard',
        'MicrosoftCorporationII.QuickAssist', 'Microsoft.WindowsMaps', 'Microsoft.Todos',
        'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'Microsoft.Office.OneNote',
        'Microsoft.RemoteDesktop', 'Microsoft.RemoteDesktopPreview',
        'McAfee', 'NortonLifeLock', 'NortonSecurity', 'ExpressVPN', 'Surfshark', 'SurfsharkVPN',
        'AVGTechnologies', 'AvastSoftware', 'KasperskyLab', 'DolbyLaboratories', 'Piriform.CCleaner',
        'Microsoft.OutlookForWindows', 'Microsoft.PowerAutomateDesktop', 'Microsoft.StartExperiencesApp',
        'Microsoft.Windows.DevHome', 'Microsoft.WindowsFeedbackHub',
        'MSTeams', 'Microsoft.GamingApp',
        'Microsoft.XboxApp', 'Microsoft.XboxGameOverlay', 'Microsoft.XboxGamingOverlay',
        'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.Xbox.TCUI',
        'Microsoft.People', 'Microsoft.549981C3F5F10',
        'MicrosoftCorporationII.MicrosoftFamily', 'MicrosoftWindows.Client.WebExperience'
    )
}

function Get-MaintSetupProfileBool {
    param(
        $SetupProfile,
        [string]$Section,
        [string]$Name,
        [bool]$Default
    )

    if (-not $SetupProfile) { return $Default }
    $sectionProp = $SetupProfile.PSObject.Properties[$Section]
    if (-not $sectionProp) { return $Default }
    $valueProp = $sectionProp.Value.PSObject.Properties[$Name]
    if (-not $valueProp) { return $Default }
    return [bool]$valueProp.Value
}

function Invoke-MaintOneDriveRemoval {
    Write-MaintLog 'OneDrive: removing post-update machine integration.'
    foreach ($name in @('OneDrive', 'OneDriveSetup')) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    foreach ($setup in @(
            "$env:SystemRoot\System32\OneDriveSetup.exe",
            "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
            "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
        )) {
        if (Test-Path -LiteralPath $setup) {
            try {
                Start-Process -FilePath $setup -ArgumentList '/uninstall' -WindowStyle Hidden -Wait -ErrorAction Stop | Out-Null
            }
            catch {
                Write-MaintLog "OneDrive uninstall failed for ${setup}: $_"
            }
        }
    }

    foreach ($setupFile in @(
            "$env:SystemRoot\System32\OneDriveSetup.exe",
            "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
            "$env:SystemRoot\System32\OneDriveSetup.exe.bak",
            "$env:SystemRoot\SysWOW64\OneDriveSetup.exe.bak",
            "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
        )) {
        if (-not (Test-Path -LiteralPath $setupFile)) { continue }
        try {
            takeown.exe /f $setupFile | Out-Null
            icacls.exe $setupFile /grant '*S-1-5-32-544:F' | Out-Null
            Remove-Item -LiteralPath $setupFile -Force -ErrorAction Stop
            Write-MaintLog "OneDrive: removed installer file $setupFile"
        }
        catch {
            Write-MaintLog "OneDrive installer file removal failed for ${setupFile}: $_"
        }
    }

    foreach ($args in @(
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableFileSync', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableFileSyncNGSC', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisablePersonalSync', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableLibrariesDefaultSaveToOneDrive', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableFileSync', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableFileSyncNGSC', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\OneDrive', '/v', 'DisablePersonalSync', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableLibrariesDefaultSaveToOneDrive', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKCR\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}', '/v', 'System.IsPinnedToNameSpaceTree', '/t', 'REG_DWORD', '/d', '0', '/f'),
            @('add', 'HKCR\WOW6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}', '/v', 'System.IsPinnedToNameSpaceTree', '/t', 'REG_DWORD', '/d', '0', '/f')
        )) {
        & reg.exe @args 2>$null
    }

    foreach ($runKey in @(
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run',
            'HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            'HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            'HKU\.DEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKU\.DEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKU\.DEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        )) {
        foreach ($value in @('OneDrive', 'OneDriveSetup')) {
            & reg.exe delete $runKey /v $value /f 2>$null
        }
    }

    foreach ($root in @(
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Active Setup\Installed Components',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Active Setup\Installed Components',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
            'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\App Paths',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
            'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SyncRootManager',
            'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
            'Registry::HKEY_USERS\.DEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SyncRootManager',
            'Registry::HKEY_USERS\.DEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace'
        )) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            $text = @(
                $key.PSChildName
                if ($props) { $props.PSObject.Properties | ForEach-Object { [string]$_.Value } }
            ) -join "`n"
            if ($text -match '(?i)OneDrive|OneDriveSetup\.exe') {
                try {
                    Remove-Item -LiteralPath $key.PSPath -Recurse -Force -ErrorAction Stop
                    Write-MaintLog "OneDrive: removed registry residue $($key.Name)"
                }
                catch {
                    Write-MaintLog "OneDrive registry residue removal failed for $($key.Name): $_"
                }
            }
        }
    }

    Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object {
            $_.TaskName -match '(?i)OneDrive' -or
            $_.TaskPath -match '(?i)OneDrive' -or
            @($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -match '(?i)OneDrive|OneDriveSetup\.exe'
        } |
        Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive",
        "$env:ProgramData\Microsoft OneDrive",
        "$env:SystemDrive\OneDriveTemp"
    ) -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\OneDrive*.lnk" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\OneDrive*.lnk" -Force -ErrorAction SilentlyContinue
}

$currentBuild = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuild -ErrorAction SilentlyContinue).CurrentBuild
$lastBuild    = if (Test-Path $buildFile) { (Get-Content $buildFile -Raw).Trim() } else { '' }
$setupProfile = Read-MaintSetupProfile
$bloat = @(Get-MaintAppxRemovalPrefixes -SetupProfile $setupProfile)
$privacyTelemetry = Get-MaintSetupProfileBool -SetupProfile $setupProfile -Section 'privacy' -Name 'telemetry' -Default $true
$privacyAdvertisingId = Get-MaintSetupProfileBool -SetupProfile $setupProfile -Section 'privacy' -Name 'advertisingId' -Default $true
$privacyLocation = Get-MaintSetupProfileBool -SetupProfile $setupProfile -Section 'privacy' -Name 'location' -Default $false
$privacyTimeline = Get-MaintSetupProfileBool -SetupProfile $setupProfile -Section 'privacy' -Name 'timeline' -Default $true
$preserveMicrosoftCopilot = Get-MaintSetupProfileBool -SetupProfile $setupProfile -Section 'setupComplete' -Name 'preserveMicrosoftCopilot' -Default $false

# --- Layer 1: Always re-stamp critical registry tweaks (~1 second) ---
$always = [System.Collections.Generic.List[scriptblock]]::new()
if ($privacyTelemetry) {
    if (-not $preserveMicrosoftCopilot) {
        $always.Add({ reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' /v DisableAIDataAnalysis /t REG_DWORD /d 1 /f 2>$null })
    }
    $always.Add({ reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' /v AllowTelemetry /t REG_DWORD /d 0 /f 2>$null })
}
if ($privacyAdvertisingId) {
    # Omit DisableWindowsConsumerFeatures — it can block or complicate Store consumer apps (e.g. Phone Link)
    # while WinWS AppX policy still provisions Phone Link / Cross Device by default.
    $always.Add({ reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent' /v DisableSoftLanding /t REG_DWORD /d 1 /f 2>$null })
    $always.Add({ reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v PersonalizationReportingEnabled /t REG_DWORD /d 0 /f 2>$null })
}
if ($privacyLocation) {
    $always.Add({ reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' /v DisableLocation /t REG_DWORD /d 1 /f 2>$null })
    $always.Add({ reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' /v DisableWindowsLocationProvider /t REG_DWORD /d 1 /f 2>$null })
}
if ($privacyTimeline) {
    $always.Add({ reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' /v EnableActivityFeed /t REG_DWORD /d 0 /f 2>$null })
    $always.Add({ reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' /v PublishUserActivities /t REG_DWORD /d 0 /f 2>$null })
    $always.Add({ reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' /v UploadUserActivities /t REG_DWORD /d 0 /f 2>$null })
}
$always.Add({ reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive' /v DisableFileSync /t REG_DWORD /d 1 /f 2>$null })
$always.Add({ reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive' /v DisableFileSyncNGSC /t REG_DWORD /d 1 /f 2>$null })
$always.Add({ reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive' /v DisablePersonalSync /t REG_DWORD /d 1 /f 2>$null })
$always.Add({ reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive' /v DisableLibrariesDefaultSaveToOneDrive /t REG_DWORD /d 1 /f 2>$null })
Write-MaintLog "Layer 1: re-stamping $($always.Count) registry tweaks (build: $currentBuild, last: $(if ($lastBuild) { $lastBuild } else { 'none' }))"
foreach ($s in $always) { try { & $s } catch { Write-MaintLog "Layer1 error: $_" } }

# --- Layers 2+3: Only on OS build change ---
if ($currentBuild -ne $lastBuild) {
    Write-MaintLog "Build changed $lastBuild → $currentBuild. Running full maintenance."
    Invoke-MaintOneDriveRemoval

    # Layer 2: Verify deprovisioned registry entries still present
    $deprovKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned'
    foreach ($pkg in $bloat) {
        $pkgKey = Join-Path $deprovKey $pkg
        if (-not (Test-Path $pkgKey)) {
            $null = New-Item -Path $pkgKey -Force -ErrorAction SilentlyContinue
            Write-MaintLog "Layer 2: re-wrote deprovisioned entry for $pkg"
        }
    }

    # Layer 3: Re-remove any provisioned packages that re-appeared
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PackageName)
    foreach ($pkg in $provisioned) {
        foreach ($prefix in $bloat) {
            if ($pkg -like "*$prefix*") {
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $pkg -ErrorAction Stop | Out-Null
                    Write-MaintLog "Layer 3: removed re-appeared package $pkg"
                } catch { Write-MaintLog "Layer 3: could not remove $pkg — $_" }
                break
            }
        }
    }

    $currentBuild | Out-File $buildFile -Force
    Write-MaintLog "Full maintenance complete."
} else {
    Write-MaintLog "Build unchanged ($currentBuild). Layer 1 only."
}
