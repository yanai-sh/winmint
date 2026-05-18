# Runs as SYSTEM via SetupComplete.cmd after Windows is installed, before first interactive logon.
# One-shot — Windows runs this exactly once during the very first boot of the installed image.
# Cleanup of C:\Windows\Panther\unattend*.xml is the priority security task here: the answer
# file embeds the user's local-admin password in base64 in the AutoLogon block and must be
# wiped before any interactive user can read it.
#Requires -Version 5.1
$ErrorActionPreference = 'Continue'
# Logs go to ProgramData (Administrators-readable). C:\Windows\Setup\Scripts is the staged
# payload directory and is readable by Users by default — transcripts can capture command
# lines and shouldn't land there.
$logDir = Join-Path $env:ProgramData 'WinMint\Logs'
$null = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue
$payloadDir = 'C:\Windows\Setup\Scripts'

$transcriptPath = Join-Path $logDir 'SetupComplete_transcript.log'
try { Stop-Transcript -ErrorAction SilentlyContinue } catch { }
Start-Transcript -Path $transcriptPath -Force -ErrorAction SilentlyContinue | Out-Null

function Write-ScLog {
    param([string]$Message)
    "$(Get-Date -Format 'o') $Message" | Out-File (Join-Path $logDir 'SetupComplete.log') -Append
}

function Test-ScInternet443 {
    try {
        $connectivityHost = 'www.microsoft.com'
        return [bool](Test-NetConnection -ComputerName $connectivityHost -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction Stop)
    }
    catch {
        return $false
    }
}

function Get-ScProcessorArchitecture {
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch -Regex ([string]$arch) {
        '^ARM64$' { return 'arm64' }
        '^(AMD64|IA64)$' { return 'amd64' }
        '^x86$' { return 'x86' }
        default { return ([string]$arch).ToLowerInvariant() }
    }
}

function ConvertTo-ScWingetArchitecture {
    param([Parameter(Mandatory)][string]$Architecture)
    switch ($Architecture) {
        'amd64' { return 'x64' }
        'arm64' { return 'arm64' }
        'x86' { return 'x86' }
        default { return $null }
    }
}

function New-ScWingetInstallArgs {
    param([Parameter(Mandatory)][string]$Id)

    $wingetArgs = @(
        'install', '--exact', '--id', $Id, '--silent',
        '--accept-source-agreements', '--accept-package-agreements'
    )
    $wingetArchitecture = ConvertTo-ScWingetArchitecture -Architecture (Get-ScProcessorArchitecture)
    if ($wingetArchitecture) {
        $wingetArgs += @('--architecture', $wingetArchitecture)
    }
    return $wingetArgs
}

$setupProfilePath = Join-Path $payloadDir 'WinMintSetupProfile.json'
$setupProfile = $null
try {
    if (Test-Path -LiteralPath $setupProfilePath) {
        $setupProfile = Get-Content -LiteralPath $setupProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
}
catch {
    "SetupComplete profile read failed: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
}

function Get-ScSetupProfileBool {
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

$preserveWindowsUpdate = Get-ScSetupProfileBool -Section 'setupComplete' -Name 'preserveWindowsUpdate' -Default $true
$disableVirtualDesktopFlyout = Get-ScSetupProfileBool -Section 'setupComplete' -Name 'disableVirtualDesktopFlyout' -Default $false
$removeRecall = Get-ScSetupProfileBool -Section 'setupComplete' -Name 'removeRecall' -Default $true

function Invoke-ScOneDriveRemoval {
    Write-ScLog 'Removing OneDrive machine integration.'
    foreach ($name in @('OneDrive', 'OneDriveSetup')) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    foreach ($setup in @(
            "$env:SystemRoot\System32\OneDriveSetup.exe",
            "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
        )) {
        if (Test-Path -LiteralPath $setup) {
            try {
                $p = Start-Process -FilePath $setup -ArgumentList '/uninstall' -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
                Write-ScLog "OneDriveSetup uninstall returned $($p.ExitCode): $setup"
            }
            catch {
                "OneDrive uninstall failed for ${setup}: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
            }
        }
    }

    foreach ($setupFile in @(
            "$env:SystemRoot\System32\OneDriveSetup.exe",
            "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
            "$env:SystemRoot\System32\OneDriveSetup.exe.bak",
            "$env:SystemRoot\SysWOW64\OneDriveSetup.exe.bak"
        )) {
        if (-not (Test-Path -LiteralPath $setupFile)) { continue }
        try {
            takeown.exe /f $setupFile | Out-Null
            icacls.exe $setupFile /grant '*S-1-5-32-544:F' | Out-Null
            Remove-Item -LiteralPath $setupFile -Force -ErrorAction Stop
            Write-ScLog "Removed OneDrive installer file: $setupFile"
        }
        catch {
            "OneDrive installer file removal failed for ${setupFile}: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
        }
    }

    foreach ($regArgs in @(
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableFileSync', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableFileSyncNGSC', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisablePersonalSync', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableLibrariesDefaultSaveToOneDrive', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableFileSync', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableFileSyncNGSC', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKCR\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}', '/v', 'System.IsPinnedToNameSpaceTree', '/t', 'REG_DWORD', '/d', '0', '/f'),
            @('add', 'HKCR\WOW6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}', '/v', 'System.IsPinnedToNameSpaceTree', '/t', 'REG_DWORD', '/d', '0', '/f')
        )) {
        & reg.exe @regArgs 2>$null
    }

    foreach ($runKey in @(
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run',
            'HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            'HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
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
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\App Paths',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
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
                    Write-ScLog "Removed OneDrive registry residue: $($key.Name)"
                }
                catch {
                    "OneDrive registry residue removal failed for $($key.Name): $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
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
        "$env:ProgramData\Microsoft OneDrive",
        "$env:SystemDrive\OneDriveTemp"
    ) -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\OneDrive*.lnk" -Force -ErrorAction SilentlyContinue
}

Write-ScLog 'SetupComplete.ps1 start'

$scripts = @(
    {
        try {
            Start-Service w32time -ErrorAction SilentlyContinue
            w32tm.exe /config /update | Out-Null
            w32tm.exe /resync /force | Out-Null
        }
        catch {
            "Time sync failed: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
        }
    }
    {
        Invoke-ScOneDriveRemoval
    }
    {
        try {
            Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction Stop
            Checkpoint-Computer -Description 'Post-install (SetupComplete)' -RestorePointType 'APPLICATION_INSTALL' -ErrorAction Stop
        }
        catch {
            "Restore point failed: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
        }
    }
    {
        # Wildcard sweep — Setup keeps multiple phase copies of the answer file
        # under Panther (unattend.xml, unattend-original.xml, sometimes per-pass
        # copies). All of them embed the base64 password and must go.
        Remove-Item -Path @(
            'C:\Windows\Panther\unattend*.xml'
            'C:\Windows\Panther\unattend\*.xml'
        ) -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath @(
            'C:\Windows\Setup\Scripts\Wifi.xml'
            'C:\Windows.old'
        ) -Recurse -Force -ErrorAction SilentlyContinue
    }
    {
        foreach ($p in @('C:\Users\Default\Desktop\*.lnk', 'C:\Users\Public\Desktop\*.lnk')) {
            Remove-Item -Path $p -Force -ErrorAction SilentlyContinue
        }
    }
    {
        if (-not $preserveWindowsUpdate) {
            Write-ScLog 'Skipping Windows Update policy restoration by setup profile.'
            return
        }
        $regs = @(
            @('reg.exe', 'delete', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', '/v', 'NoAutoUpdate', '/f')
            @('reg.exe', 'delete', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', '/v', 'AUOptions', '/f')
            @('reg.exe', 'delete', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', '/v', 'UseWUServer', '/f')
            @('reg.exe', 'delete', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', '/v', 'DisableWindowsUpdateAccess', '/f')
            @('reg.exe', 'delete', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', '/v', 'WUServer', '/f')
            @('reg.exe', 'delete', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', '/v', 'WUStatusServer', '/f')
            @('reg.exe', 'delete', 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config', '/v', 'DODownloadMode', '/f')
            @('reg.exe', 'add', 'HKLM\SYSTEM\CurrentControlSet\Services\BITS', '/v', 'Start', '/t', 'REG_DWORD', '/d', '3', '/f')
            @('reg.exe', 'add', 'HKLM\SYSTEM\CurrentControlSet\Services\wuauserv', '/v', 'Start', '/t', 'REG_DWORD', '/d', '3', '/f')
            @('reg.exe', 'add', 'HKLM\SYSTEM\CurrentControlSet\Services\UsoSvc', '/v', 'Start', '/t', 'REG_DWORD', '/d', '2', '/f')
            @('reg.exe', 'add', 'HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc', '/v', 'Start', '/t', 'REG_DWORD', '/d', '3', '/f')
        )
        foreach ($a in $regs) {
            & $a[0] $a[1..($a.Count - 1)] 2>$null
        }
    }
    {
        if (-not $removeRecall) {
            Write-ScLog 'Skipping Recall removal by setup profile.'
            return
        }
        $r = Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Enabled' -and $_.FeatureName -like 'Recall' }
        if ($r) {
            Disable-WindowsOptionalFeature -Online -FeatureName 'Recall' -Remove -ErrorAction SilentlyContinue
        }
    }
    {
        if (-not $disableVirtualDesktopFlyout) {
            Write-ScLog 'Skipping virtual desktop flyout override by setup profile.'
            return
        }
        $vive = Join-Path $payloadDir 'ViVeTool\ViVeTool.exe'
        $viveLog = Join-Path $logDir 'ViVeTool.log'
        if (-not (Test-Path -LiteralPath $vive)) {
            Write-ScLog 'Skipping ViVeTool feature overrides; ViVeTool.exe was not staged.'
            return
        }
        "$(Get-Date -Format 'o') Disable virtual desktop switch flyout: .\ViVeTool.exe /disable /id:34508225" |
            Out-File $viveLog -Append
        $out = & $vive /disable /id:34508225 2>&1
        $code = $LASTEXITCODE
        $out | Out-File $viveLog -Append
        if ($code -ne 0) {
            "ViVeTool virtual desktop flyout override failed with exit code $code." |
                Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
        }
        else {
            Write-ScLog 'ViVeTool disabled virtual desktop switch flyout feature id 34508225 before first logon.'
        }
    }
    {
        try {
            $bitLockerVolume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
            if ($bitLockerVolume -and $bitLockerVolume.ProtectionStatus -eq 'On') {
                Write-ScLog 'Leaving active BitLocker protection enabled; WinMint only prevents automatic device encryption.'
            }
        }
        catch { }
    }
    {
        if ((bcdedit.exe | Select-String 'path').Count -eq 2) {
            $null = & bcdedit.exe /set '{bootmgr}' timeout 2
        }
    }
    {
        if (-not (Test-ScInternet443)) {
            Write-ScLog 'Skipping winget toolchain (no outbound HTTPS to www.microsoft.com:443).'
            return
        }
        try {
            $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
            $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
            $env:PATH = "$machinePath;$userPath"
            $pwsh = "$env:ProgramFiles\PowerShell\7\pwsh.exe"
            if (-not (Test-Path -LiteralPath $pwsh)) {
                Start-Process -FilePath 'winget.exe' -ArgumentList (New-ScWingetInstallArgs -Id 'Microsoft.PowerShell') -Wait -NoNewWindow -ErrorAction Stop
            }
            Start-Process -FilePath 'winget.exe' -ArgumentList (New-ScWingetInstallArgs -Id 'Microsoft.WindowsTerminal') -Wait -NoNewWindow -ErrorAction SilentlyContinue
        }
        catch {
            "Toolchain install failed: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
        }
    }
    {
        Start-Sleep -Seconds 15
        $log = Join-Path $logDir 'Activation.log'
        "$(Get-Date -Format s) Activation check" | Out-File $log
        $r = & cscript.exe //nologo "$env:SystemRoot\System32\slmgr.vbs" /xpr 2>&1
        $r | Out-File $log -Append
        if ($r -notmatch 'permanently activated|will expire') {
            'WARN: not activated.' | Out-File $log -Append
        }
    }
    {
        try {
            $log = Join-Path $logDir 'NPU.log'
            "$(Get-Date -Format s) NPU detection" | Out-File $log
            $npu = Get-PnpDevice -ErrorAction Stop |
                Where-Object { $_.FriendlyName -match 'Hexagon|Qualcomm.*NPU|Qualcomm.*Compute|Neural' }
            if ($npu) {
                'OK: NPU device(s) found:' | Out-File $log -Append
                $npu | ForEach-Object { "  $($_.Status) - $($_.FriendlyName)" | Out-File $log -Append }
            }
            else {
                'WARN: No NPU device detected.' | Out-File $log -Append
            }
        }
        catch { }
    }
    {
        # Split svchost per-service so Task Manager shows accurate per-process resource use.
        # Default threshold (3.5 GB) groups services on low-RAM machines; modern hardware always splits.
        try {
            $ramKB = [long]([math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1024))
            Set-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control' `
                -Name 'SvcHostSplitThresholdInKB' -Value $ramKB -Type DWord -Force
            Write-ScLog "SvcHostSplitThresholdInKB set to $ramKB KB (total physical RAM)."
        }
        catch {
            "SvcHostSplitThreshold failed: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
        }
    }
)

$errors = @()
foreach ($s in $scripts) {
    try { & $s } catch { $errors += "SetupComplete: $_" }
}
if ($errors.Count -gt 0) {
    ($errors -join "`n") | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Force
}

Write-ScLog 'SetupComplete.ps1 end'
try { Stop-Transcript -ErrorAction SilentlyContinue } catch { }
