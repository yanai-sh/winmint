#Requires -Version 7.3

function New-WinMintAgentProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$BuildConfig)

    New-WinMintInstallPlanAgentProfile -BuildConfig $BuildConfig
}

function New-WinMintSetupProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$BuildConfig)

    New-WinMintInstallPlanSetupProfile -BuildConfig $BuildConfig
}

function New-WinMintSetupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$BuildConfig,
        [Parameter(Mandatory)]$SetupProfile,
        [Parameter(Mandatory)]$AgentProfile
    )

    New-WinMintInstallPlanSetupPlan `
        -BuildConfig $BuildConfig `
        -SetupProfile $SetupProfile `
        -AgentProfile $AgentProfile
}
function Get-WinMintDualBootWindowsRatio {
    param([string]$Preset)

    switch ($Preset) {
        'WindowsHeavy' { 0.70; break }
        'Balanced'     { 0.60; break }
        'EvenSplit'    { 0.50; break }
        'LinuxHeavy'   { 0.40; break }
        default        { throw "Unsupported dual-boot preset: $Preset" }
    }
}

function New-WinMintWindowsOnlyDiskpartPowerShellCommand {
    param([Parameter(Mandatory)]$DiskLayout)

    $windowsMinimumGb = [int](Get-WinMintProfileSetting $DiskLayout 'windowsMinimumGb' 256)
    $efiMb = [int](Get-WinMintProfileSetting $DiskLayout 'efiMb' 1024)
    $msrMb = [int](Get-WinMintProfileSetting $DiskLayout 'msrMb' 16)
    $recoveryMb = [int](Get-WinMintProfileSetting $DiskLayout 'recoveryMb' 1024)

    $script = @"
`$ErrorActionPreference='Stop';
`$disk=Get-Disk -Number 0;
`$totalMb=[math]::Floor(`$disk.Size/1MB);
`$usableMb=[int](`$totalMb-$efiMb-$msrMb-$recoveryMb);
if (`$usableMb -lt ($windowsMinimumGb*1024)) { throw "Windows partition would be `$([math]::Floor(`$usableMb/1024)) GB; minimum is $windowsMinimumGb GB." }
@(
'select disk 0',
'clean',
'convert gpt',
'create partition efi size=$efiMb',
'format quick fs=fat32 label=ESP',
'create partition msr size=$msrMb',
'create partition primary',
'format quick fs=ntfs label=WINMINT',
'shrink minimum=$recoveryMb desired=$recoveryMb',
'create partition primary size=$recoveryMb',
'format quick fs=ntfs label=WinRE',
'set id=de94bba4-06d1-4d40-a16a-bfd50179d6ac',
'gpt attributes=0x8000000000000001'
) | Set-Content -LiteralPath 'X:\winmint_dp.txt' -Encoding ASCII;
diskpart.exe /s X:\winmint_dp.txt
"@
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script))
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
}

function New-WinMintDualBootDiskpartPowerShellCommand {
    param([Parameter(Mandatory)]$DiskLayout)

    $preset = [string](Get-WinMintProfileSetting $DiskLayout 'preset' '')
    $ratio = Get-WinMintDualBootWindowsRatio -Preset $preset
    $roundingGb = [int](Get-WinMintProfileSetting $DiskLayout 'roundingGb' 64)
    $windowsMinimumGb = [int](Get-WinMintProfileSetting $DiskLayout 'windowsMinimumGb' 256)
    $linuxMinimumGb = [int](Get-WinMintProfileSetting $DiskLayout 'linuxMinimumGb' 128)
    $efiMb = [int](Get-WinMintProfileSetting $DiskLayout 'efiMb' 1024)
    $msrMb = [int](Get-WinMintProfileSetting $DiskLayout 'msrMb' 16)
    $recoveryMb = [int](Get-WinMintProfileSetting $DiskLayout 'recoveryMb' 1024)

    $script = @"
`$ErrorActionPreference='Stop';
`$disk=Get-Disk -Number 0;
`$totalGb=[math]::Floor(`$disk.Size/1GB);
`$reservedGb=[math]::Ceiling(($efiMb+$msrMb+$recoveryMb)/1024);
`$usableGb=`$totalGb-`$reservedGb;
`$windowsGb=[math]::Round((`$usableGb*$ratio)/$roundingGb,0,[System.MidpointRounding]::AwayFromZero)*$roundingGb;
if (`$windowsGb -lt $windowsMinimumGb) { throw "Windows partition would be `$windowsGb GB; minimum is $windowsMinimumGb GB." }
`$linuxGb=`$usableGb-`$windowsGb;
if (`$linuxGb -lt $linuxMinimumGb) { throw "Linux reserved space would be `$linuxGb GB; minimum is $linuxMinimumGb GB." }
`$windowsMb=[int](`$windowsGb*1024);
@(
'select disk 0',
'clean',
'convert gpt',
'create partition efi size=$efiMb',
'format quick fs=fat32 label=ESP',
'create partition msr size=$msrMb',
"create partition primary size=`$windowsMb",
'format quick fs=ntfs label=WINMINT',
'create partition primary size=$recoveryMb',
'format quick fs=ntfs label=WinRE',
'set id=de94bba4-06d1-4d40-a16a-bfd50179d6ac',
'gpt attributes=0x8000000000000001'
) | Set-Content -LiteralPath 'X:\winmint_dp.txt' -Encoding ASCII;
diskpart.exe /s X:\winmint_dp.txt
"@
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script))
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
}

function Install-Autounattend {
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir, [ValidateNotNullOrEmpty()][string]$IsoContents,
        [ValidateNotNullOrEmpty()][string]$AutounattendTemplate, [ValidateNotNullOrEmpty()][string]$ImageArch,
        [string]$TimeZone, [string]$TargetPCName, [string]$TargetUser, [ValidateSet('Local', 'MicrosoftOobe')][string]$AccountMode = 'Local', [string]$TargetPass,
        [string]$EditionName, [ValidateSet('TargetLicense', 'Fixed')][string]$EditionMode = 'TargetLicense', [string]$ProductKey = '', [int]$InstallImageCount = 0, [bool]$AutoWipeDisk, [bool]$AutoLogon,
        [object]$DiskLayout,
        [bool]$HardwareBypass = $false,
        [string]$InputLocale, [string]$SystemLocale, [string]$UILanguage, [string]$UILanguageFallback, [string]$UserLocale,
        [ValidateNotNullOrEmpty()][string]$ScriptRoot,
        [object]$AgentProfile,
        [object]$SetupProfile,
        [object]$SetupPlan,
        [switch]$DryRun
    )
    Write-SectionHeader 'Unattended setup (autounattend.xml)'

    $xmlDoc = [xml]::new()
    try { $xmlDoc.LoadXml($AutounattendTemplate) } catch { throw "Autounattend XML is invalid: $_" }

    $nsMgr = [System.Xml.XmlNamespaceManager]::new($xmlDoc.NameTable)
    $nsMgr.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')

    Log 'Updating autounattend (PC name, account, edition mode, locales, disk behavior)...'

    Set-WinMintManifestSetupPlanFact -SetupPlan $SetupPlan

    $components = $xmlDoc.SelectNodes('//u:component', $nsMgr)
    foreach ($comp in $components) {
        if ($comp.HasAttribute('processorArchitecture')) { $comp.SetAttribute('processorArchitecture', $ImageArch) }
    }

    if ($HardwareBypass) {
        $wpSetupRunSync = $xmlDoc.SelectSingleNode(
            '//u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-Setup"]/u:RunSynchronous', $nsMgr)
        if ($wpSetupRunSync) {
            $xmlNs = 'urn:schemas-microsoft-com:unattend'
            $wcmNs = 'http://schemas.microsoft.com/WMIConfig/2002/State'
            $maxOrder = @($wpSetupRunSync.SelectNodes('u:RunSynchronousCommand/u:Order', $nsMgr) |
                ForEach-Object { [int]$_.InnerText } |
                Measure-Object -Maximum).Maximum
            $nextOrder = if ($null -ne $maxOrder) { [int]$maxOrder + 1 } else { 1 }
            foreach ($valueName in @(
                    'BypassTPMCheck',
                    'BypassSecureBootCheck',
                    'BypassCPUCheck',
                    'BypassRAMCheck',
                    'BypassStorageCheck'
                )) {
                $cmdEl = $xmlDoc.CreateElement('RunSynchronousCommand', $xmlNs)
                $null = $cmdEl.SetAttribute('action', $wcmNs, 'add')
                $orderEl = $xmlDoc.CreateElement('Order', $xmlNs); $orderEl.InnerText = "$nextOrder"
                $pathEl = $xmlDoc.CreateElement('Path', $xmlNs)
                $pathEl.InnerText = "reg.exe add `"HKLM\SYSTEM\Setup\LabConfig`" /v $valueName /t REG_DWORD /d 1 /f"
                $null = $cmdEl.AppendChild($orderEl)
                $null = $cmdEl.AppendChild($pathEl)
                $null = $wpSetupRunSync.AppendChild($cmdEl)
                $nextOrder++
            }
            LogWarn 'Hardware compatibility bypass enabled for Windows Setup checks.'
        }
        else {
            LogWarn 'Hardware compatibility bypass selected, but the windowsPE RunSynchronous block was not found.'
        }
    }

    $tzNode = $xmlDoc.SelectSingleNode('//u:TimeZone', $nsMgr)
    if ($tzNode -and $TimeZone) { $tzNode.InnerText = $TimeZone }

    Merge-UnattendInternationalXml -XmlDoc $xmlDoc -NsMgr $nsMgr -InputLocale $InputLocale -SystemLocale $SystemLocale -UILanguage $UILanguage -UILanguageFallback $UILanguageFallback -UserLocale $UserLocale

    $installFromNode = $xmlDoc.SelectSingleNode('//u:ImageInstall/u:OSImage/u:InstallFrom', $nsMgr)
    if (-not [string]::IsNullOrWhiteSpace($ProductKey)) {
        # Inject a generic edition key (VM/container ISO or keyless build host):
        # selects the edition and skips the Setup product-key page. This is NOT an
        # activating key — a real device still activates via its firmware license.
        $pkNode = $xmlDoc.SelectSingleNode('//u:UserData/u:ProductKey', $nsMgr)
        if ($pkNode) {
            $keyNode = $pkNode.SelectSingleNode('u:Key', $nsMgr)
            if (-not $keyNode) {
                $keyNode = $xmlDoc.CreateElement('Key', 'urn:schemas-microsoft-com:unattend')
                $null = $pkNode.PrependChild($keyNode)
            }
            $keyNode.InnerText = $ProductKey
            Log "Product key: injected generic key for '$EditionName' (skips the setup key page; does not activate)."
        }
    }
    else {
        # Keyless default: strip the product key so the device firmware/digital
        # license activates the matching edition on real hardware.
        foreach ($productKeyNode in @($xmlDoc.SelectNodes('//u:ProductKey', $nsMgr))) {
            $null = $productKeyNode.ParentNode.RemoveChild($productKeyNode)
        }
    }
    if ($EditionMode -eq 'Fixed') {
        $editionNode = $xmlDoc.SelectSingleNode('//u:MetaData[u:Key="/IMAGE/NAME"]/u:Value', $nsMgr)
        if ($editionNode) { $editionNode.InnerText = $EditionName }
        Log "Edition mode: fixed image selection ($EditionName) via ImageInstall metadata; activation remains the target device license."
    }
    elseif ($InstallImageCount -eq 1) {
        $xmlNs = 'urn:schemas-microsoft-com:unattend'
        if (-not $installFromNode) {
            $osImageNode = $xmlDoc.SelectSingleNode('//u:ImageInstall/u:OSImage', $nsMgr)
            if ($osImageNode) {
                $installFromNode = $xmlDoc.CreateElement('InstallFrom', $xmlNs)
                $null = $osImageNode.PrependChild($installFromNode)
            }
        }
        if ($installFromNode) {
            foreach ($metadata in @($installFromNode.SelectNodes('u:MetaData', $nsMgr))) {
                $null = $installFromNode.RemoveChild($metadata)
            }
            $metadataNode = $xmlDoc.CreateElement('MetaData', $xmlNs)
            $keyNode = $xmlDoc.CreateElement('Key', $xmlNs); $keyNode.InnerText = '/IMAGE/INDEX'
            $valueNode = $xmlDoc.CreateElement('Value', $xmlNs); $valueNode.InnerText = '1'
            $null = $metadataNode.AppendChild($keyNode)
            $null = $metadataNode.AppendChild($valueNode)
            $null = $installFromNode.AppendChild($metadataNode)
        }
        Log 'Edition mode: target license on single-image media - selecting install.wim index 1 without a product key.'
    }
    else {
        if ($installFromNode) { $null = $installFromNode.ParentNode.RemoveChild($installFromNode) }
        Log 'Edition mode: target license - Windows Setup will use the target device firmware key when available; no product key is written.'
    }

    foreach ($pcNode in @($xmlDoc.SelectNodes('//u:ComputerName', $nsMgr))) {
        if ($pcNode -and $TargetPCName) { $pcNode.InnerText = $TargetPCName }
    }

    $hideWirelessNode = $xmlDoc.SelectSingleNode('//u:OOBE/u:HideWirelessSetupInOOBE', $nsMgr)
    if ($hideWirelessNode) {
        $hideWirelessNode.InnerText = if ($AccountMode -eq 'Local') { 'true' } else { 'false' }
    }
    if ($AccountMode -eq 'Local') {
        Log 'OOBE network page is hidden for fully unattended local-account installs.'
    }
    else {
        Log 'OOBE network page remains visible for Microsoft OOBE account setup.'
    }

    if ($AccountMode -eq 'MicrosoftOobe') {
        $bypassNroNode = $xmlDoc.SelectSingleNode('//u:RunSynchronousCommand[contains(u:Path, "BypassNRO")]', $nsMgr)
        if ($bypassNroNode) { $null = $bypassNroNode.ParentNode.RemoveChild($bypassNroNode) }
        foreach ($path in @(
                '//u:OOBE/u:HideOnlineAccountScreens',
                '//u:OOBE/u:HideLocalAccountScreen',
                '//u:UserAccounts'
            )) {
            $node = $xmlDoc.SelectSingleNode($path, $nsMgr)
            if ($node) { $null = $node.ParentNode.RemoveChild($node) }
        }
        if ($AutoLogon) {
            LogWarn 'Autologon ignored because Microsoft account OOBE lets the user create/sign in to the account interactively.'
        }
        Log 'Account mode: official OOBE — Microsoft account/local-account choice is handled by Windows Setup.'
    }
    else {
        $bypassNroNode = $xmlDoc.SelectSingleNode('//u:RunSynchronousCommand[contains(u:Path, "BypassNRO")]', $nsMgr)
        if (-not $bypassNroNode) {
            LogWarn 'Local account mode selected, but BypassNRO is missing from the unattend template.'
        }
        $userNode = $xmlDoc.SelectSingleNode('//u:LocalAccount/u:Name', $nsMgr)
        if ($userNode -and $TargetUser) { $userNode.InnerText = $TargetUser }

        $accountPasswordNode = $xmlDoc.SelectSingleNode('//u:LocalAccount/u:Password', $nsMgr)
        $passNode = $xmlDoc.SelectSingleNode('//u:LocalAccount/u:Password/u:Value', $nsMgr)
        if ($TargetPass) {
            if ($passNode) {
                $passNode.InnerText = [Convert]::ToBase64String(
                    [System.Text.Encoding]::Unicode.GetBytes($TargetPass + 'Password'))
            }
        }
        elseif ($accountPasswordNode) {
            $null = $accountPasswordNode.ParentNode.RemoveChild($accountPasswordNode)
            Log 'Local account password omitted; Windows will create a passwordless local administrator.'
        }
    }

    if ($AccountMode -eq 'Local' -and $AutoLogon -and $TargetPass) {
        $shellNode = $xmlDoc.SelectSingleNode('//u:component[@name="Microsoft-Windows-Shell-Setup"]', $nsMgr)
        if ($shellNode) {
            $xmlNs = 'urn:schemas-microsoft-com:unattend'
            $autoLogonEl = $xmlDoc.CreateElement('AutoLogon', $xmlNs)
            $passEl  = $xmlDoc.CreateElement('Password',   $xmlNs)
            $passVal = $xmlDoc.CreateElement('Value',      $xmlNs)
            $passVal.InnerText = [Convert]::ToBase64String(
                [System.Text.Encoding]::Unicode.GetBytes($TargetPass + 'Password'))
            $passPlain = $xmlDoc.CreateElement('PlainText', $xmlNs); $passPlain.InnerText = 'false'
            $null = $passEl.AppendChild($passVal); $null = $passEl.AppendChild($passPlain)
            $null = $autoLogonEl.AppendChild($passEl)
            $enabledEl = $xmlDoc.CreateElement('Enabled', $xmlNs); $enabledEl.InnerText = 'true'
            $null = $autoLogonEl.AppendChild($enabledEl)
            # Auto sign-in must survive EVERY install reboot until the FirstLogon agent
            # completes (the agent can reboot mid-run). A generous count keeps the
            # password resident so the first runs do not prompt; FirstLogon.ps1 then
            # makes autologon persistent and only disables it + wipes the password once
            # the agent run succeeds.
            $countEl = $xmlDoc.CreateElement('LogonCount', $xmlNs); $countEl.InnerText = '5'
            $null = $autoLogonEl.AppendChild($countEl)
            $userEl = $xmlDoc.CreateElement('Username', $xmlNs); $userEl.InnerText = $TargetUser
            $null = $autoLogonEl.AppendChild($userEl)
            $null = $shellNode.AppendChild($autoLogonEl)
            LogOK "Autologon configured for $TargetUser."
        }
    }

    $diskLayoutMode = if ($DiskLayout) { [string](Get-WinMintProfileSetting $DiskLayout 'mode' '') } else { '' }
    if ([string]::IsNullOrWhiteSpace($diskLayoutMode)) {
        $diskLayoutMode = if ($AutoWipeDisk) { 'AutoWipeDisk0' } else { 'Manual' }
    }
    if ($AutoWipeDisk -and $null -eq $DiskLayout) {
        $DiskLayout = [ordered]@{
            mode = $diskLayoutMode
            preset = ''
            roundingGb = 64
            windowsMinimumGb = 256
            windowsRecommendedGb = 384
            linuxMinimumGb = 128
            linuxRecommendedGb = 256
            efiMb = 1024
            msrMb = 16
            recoveryMb = 1024
        }
    }

    $diskConfigNode = $xmlDoc.SelectSingleNode('//u:DiskConfiguration', $nsMgr)
    if (-not $AutoWipeDisk) {
        Log 'Disk layout: manual — standard Setup disk UI; autounattend does not clear the primary disk.'
        if ($diskConfigNode) { $null = $diskConfigNode.ParentNode.RemoveChild($diskConfigNode) }
        $installToNode = $xmlDoc.SelectSingleNode('//u:InstallTo', $nsMgr)
        if ($installToNode) { $null = $installToNode.ParentNode.RemoveChild($installToNode) }
    }
    elseif ($diskLayoutMode -eq 'AutoWipeDisk0') {
        Log 'Disk layout: native unattend wipe — EFI (1 GB) + MSR (16 MB) + Windows on the primary disk.'
    }
    else {
        if ($diskLayoutMode -eq 'DualBootReserved') {
            $preset = [string](Get-WinMintProfileSetting $DiskLayout 'preset' 'Balanced')
            Log "Disk layout: dual boot reserved ($preset) — EFI (1 GB) + MSR (16 MB) + rounded Windows + WinRE (1 GB), Linux space left unallocated."
        }
        else {
            Log 'Disk layout: automated diskpart — EFI (1 GB) + MSR (16 MB) + Windows + WinRE (1 GB) on the primary disk.'
        }
        if ($diskConfigNode) { $null = $diskConfigNode.ParentNode.RemoveChild($diskConfigNode) }
        # InstallTo (disk 0, partition 3) is retained: EFI=1, MSR=2, Windows=3, Recovery=4

        $wpSetupComp = $xmlDoc.SelectSingleNode(
            '//u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-Setup"]/u:RunSynchronous', $nsMgr)
        if ($wpSetupComp) {
            $xmlNs = 'urn:schemas-microsoft-com:unattend'
            $wcmNs = 'http://schemas.microsoft.com/WMIConfig/2002/State'
            $maxOrder = @($wpSetupComp.SelectNodes('u:RunSynchronousCommand/u:Order', $nsMgr) |
                ForEach-Object { [int]$_.InnerText } |
                Measure-Object -Maximum).Maximum
            $nextOrder = $maxOrder + 1

            $dpLines = if ($diskLayoutMode -eq 'DualBootReserved') {
                @(New-WinMintDualBootDiskpartPowerShellCommand -DiskLayout $DiskLayout)
            }
            else {
                @(New-WinMintWindowsOnlyDiskpartPowerShellCommand -DiskLayout $DiskLayout)
            }

            foreach ($line in $dpLines) {
                $cmdEl   = $xmlDoc.CreateElement('RunSynchronousCommand', $xmlNs)
                $null    = $cmdEl.SetAttribute('action', $wcmNs, 'add')
                $orderEl = $xmlDoc.CreateElement('Order', $xmlNs); $orderEl.InnerText = "$nextOrder"
                $pathEl  = $xmlDoc.CreateElement('Path',  $xmlNs); $pathEl.InnerText  = $line
                $null    = $cmdEl.AppendChild($orderEl)
                $null    = $cmdEl.AppendChild($pathEl)
                $null    = $wpSetupComp.AppendChild($cmdEl)
                $nextOrder++
            }
            LogOK 'Diskpart script (EFI + MSR + Windows + WinRE) injected into windowsPE RunSynchronous.'
        }
    }

    if ($DryRun) {
        $xmlWriterSettings = [System.Xml.XmlWriterSettings]::new()
        $xmlWriterSettings.Indent = $true
        $xmlWriterSettings.Encoding = [System.Text.UTF8Encoding]::new($false)
        $stringWriter = [System.IO.StringWriter]::new()
        $xmlWriter = [System.Xml.XmlWriter]::Create($stringWriter, $xmlWriterSettings)
        try { $xmlDoc.Save($xmlWriter) } finally { $xmlWriter.Close() }
        $autounattendXml = $stringWriter.ToString()
        LogOK 'Validated autounattend.xml generation in memory.'

        $setupProfileJson = ''
        if ($SetupProfile) {
            $setupProfileJson = $SetupProfile | ConvertTo-Json -Depth 12
            $null = $setupProfileJson | ConvertFrom-Json -ErrorAction Stop
            LogOK 'Validated setup profile JSON generation in memory.'
        }
        $agentProfileJson = ''
        if ($AgentProfile) {
            $agentProfileJson = $AgentProfile | ConvertTo-Json -Depth 12
            $null = $agentProfileJson | ConvertFrom-Json -ErrorAction Stop
            LogOK 'Validated WinMintAgent profile JSON generation in memory.'
        }
        $setupPlanJson = ''
        if ($SetupPlan) {
            $setupPlanJson = $SetupPlan | ConvertTo-Json -Depth 16
            $null = $setupPlanJson | ConvertFrom-Json -ErrorAction Stop
            LogOK 'Validated setup plan JSON generation in memory.'
        }

        Write-SectionHeader 'Autounattend summary (dry run)' -Accent Yellow -RuleColor Grey
        $autoWipeDisplay = if ($AutoWipeDisk) { '[red]Yes — repartition primary disk[/]' } else { '[green]No — manual Setup disk UI[/]' }
        $autoLogonDisplay = if ($AutoLogon) { '[green]Yes[/]' } else { '[silver]No[/]' }
        $hardwareBypassDisplay = if ($HardwareBypass) { '[yellow]Yes — unsupported hardware checks bypassed[/]' } else { '[green]No[/]' }
        Write-SpectreKeyValueTable -Title '[bold cyan3]Prepared XML (in memory only)[/]' -TableColor Grey -Rows @(
            [pscustomobject]@{ Item = 'Computer name'; Value = "[green]$TargetPCName[/]" }
            [pscustomobject]@{ Item = 'User name'; Value = "[green]$TargetUser[/]" }
            [pscustomobject]@{ Item = 'Account mode'; Value = $(if ($AccountMode -eq 'MicrosoftOobe') { '[green]Official OOBE[/]' } else { '[green]Local unattended[/]' }) }
            [pscustomobject]@{ Item = 'Edition'; Value = $(if ($EditionMode -eq 'Fixed') { "[green]$EditionName[/]" } else { '[green]Target license[/]' }) }
            [pscustomobject]@{ Item = 'Time zone'; Value = "[green]$TimeZone[/]" }
            [pscustomobject]@{ Item = 'Input locale'; Value = "[green]$InputLocale[/]" }
            [pscustomobject]@{ Item = 'System locale'; Value = "[green]$SystemLocale[/]" }
            [pscustomobject]@{ Item = 'UI language'; Value = "[green]$UILanguage[/]" }
            [pscustomobject]@{ Item = 'User locale'; Value = "[green]$UserLocale[/]" }
            [pscustomobject]@{ Item = 'Unattended clears primary disk'; Value = $autoWipeDisplay }
            [pscustomobject]@{ Item = 'Autologon'; Value = $autoLogonDisplay }
            [pscustomobject]@{ Item = 'Hardware bypass'; Value = $hardwareBypassDisplay }
        )
        return [pscustomobject]@{
            AutounattendXml = $autounattendXml
            SetupProfileJson = $setupProfileJson
            AgentProfileJson = $agentProfileJson
            SetupPlanJson = $setupPlanJson
        }
    }

    Invoke-Action 'Writing autounattend.xml and setup scripts onto the ISO' {
        LogVerbose "Mount: $MountDir | ISO staging: $IsoContents"

        $bundleDir = Join-Path $ScriptRoot 'src\runtime\setup'
        if (Test-Path -LiteralPath $bundleDir) {
            $destScripts = Join-Path $MountDir 'Windows\Setup\Scripts'
            $null = New-Item -ItemType Directory -Path $destScripts -Force -ErrorAction SilentlyContinue
            $wallpaperSrc = Join-Path $ScriptRoot 'assets\runtime\wallpaper\img0.jpg'
            $lockScreenSrc = Join-Path $ScriptRoot 'assets\runtime\wallpaper\img100.jpg'
            foreach ($requiredImage in @($wallpaperSrc, $lockScreenSrc)) {
                if (-not (Test-Path -LiteralPath $requiredImage)) {
                    throw "WinMint stock-slot wallpaper asset is missing: $requiredImage"
                }
            }
            $wallpaperDestDir = Join-Path $MountDir 'Windows\Web\Wallpaper\Windows'
            $lockScreenDestDir = Join-Path $MountDir 'Windows\Web\Screen'
            $null = New-Item -ItemType Directory -Path $wallpaperDestDir -Force -ErrorAction Stop
            $null = New-Item -ItemType Directory -Path $lockScreenDestDir -Force -ErrorAction Stop
            Copy-Item -LiteralPath $wallpaperSrc -Destination (Join-Path $wallpaperDestDir 'WinMint-Bloom.jpg') -Force
            Copy-Item -LiteralPath $lockScreenSrc -Destination (Join-Path $lockScreenDestDir 'WinMint-Lock.jpg') -Force
            LogOK 'Staged desktop and lock-screen images into stock Windows image slots.'

            # Default account picture = the WinMint mark. Overwrite the stock blank-silhouette
            # defaults at ProgramData\Microsoft\User Account Pictures so any local account
            # without a custom picture shows the WinMint logo (rendered in the circular avatar).
            $accountPicSrc = Join-Path $ScriptRoot 'assets\runtime\accountpicture'
            if (Test-Path -LiteralPath $accountPicSrc) {
                $accountPicDest = Join-Path $MountDir 'ProgramData\Microsoft\User Account Pictures'
                $null = New-Item -ItemType Directory -Path $accountPicDest -Force -ErrorAction SilentlyContinue
                foreach ($pic in @('user.bmp', 'user.png', 'user-32.png', 'user-40.png', 'user-48.png', 'user-192.png')) {
                    $picSrc = Join-Path $accountPicSrc $pic
                    if (Test-Path -LiteralPath $picSrc) {
                        Copy-Item -LiteralPath $picSrc -Destination (Join-Path $accountPicDest $pic) -Force
                    }
                }
                LogOK 'Staged WinMint account picture into the offline image.'
            }
            Invoke-WinMintSetupPayloadStaging `
                -MountDir $MountDir `
                -ScriptRoot $ScriptRoot `
                -AgentProfile $AgentProfile `
                -SetupProfile $SetupProfile `
                -SetupPlan $SetupPlan | Out-Null
        }
        else {
            throw "WinMint setup script directory is missing: $bundleDir"
        }

        $outputPath = Join-Path $IsoContents 'autounattend.xml'
        $xmlWriterSettings = [System.Xml.XmlWriterSettings]::new()
        $xmlWriterSettings.Indent = $true
        $xmlWriterSettings.Encoding = [System.Text.UTF8Encoding]::new($false)
        $xmlWriter = [System.Xml.XmlWriter]::Create($outputPath, $xmlWriterSettings)
        try { $xmlDoc.Save($xmlWriter) } finally { $xmlWriter.Close() }
        LogOK 'autounattend.xml written next to the staged ISO (ready for oscdimg).'
    }
}

function Install-WinPEUtility {
    param([ValidateNotNullOrEmpty()][string]$IsoContents, [bool]$AutoWipeDisk)
    Write-SectionHeader 'WinPE: optional disk tools'

    if ($AutoWipeDisk) {
        Log 'Skipping WinPE FormatDisk helper (automated disk layout is already enabled).'
        return
    }

    Invoke-Action 'Patching WinPE with dark theme and optional FormatDisk helper' {
        LogVerbose "ISO tree: $IsoContents"
        $bootWim = Join-Path $IsoContents 'sources\boot.wim'
        if (-not (Test-Path $bootWim)) { return }

        $null = Set-ItemProperty -Path $bootWim -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        $bootMount = Join-Path (Get-Win11IsoProcessTempPath) "Win11ISO_BootMount_$(Get-Random)"
        $null = New-Item -Path $bootMount -ItemType Directory -Force

        try {
            Mount-WinMintImage -ImagePath $bootWim -Index $script:BootWimWinPEUtilityMountIndex -MountDir $bootMount
            Log 'Applying dark theme and FormatDisk.cmd to WinPE…'
            $peSystem = Join-Path $bootMount 'Windows\System32\config\SYSTEM'
            $peSoftware = Join-Path $bootMount 'Windows\System32\config\SOFTWARE'
            $null = & reg.exe load 'HKLM\peSYSTEM' $peSystem
            try {
                $null = & reg.exe load 'HKLM\peSOFTWARE' $peSoftware
                try {
                    $null = & reg.exe add 'HKLM\peSOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' /v AppsUseLightTheme /t REG_DWORD /d 0 /f
                    $null = & reg.exe add 'HKLM\peSOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' /v SystemUsesLightTheme /t REG_DWORD /d 0 /f
                }
                finally {
                    [GC]::Collect(); [GC]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds 500
                    $null = & reg.exe unload 'HKLM\peSOFTWARE'
                }
            }
            finally {
                [GC]::Collect(); [GC]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds 500
                $null = & reg.exe unload 'HKLM\peSYSTEM'
            }

            $cmdScript = @"
@echo off
setlocal EnableDelayedExpansion
color 0B
echo ===============================================================================
echo                DEV WORKSTATION DISK SETUP (Suggested Layout)
echo ===============================================================================
echo [ EFI Boot (1GB) ]  [ MSR (16MB) ]  [ Windows C: (Remaining) ]
echo ===============================================================================
list disk | diskpart | findstr /R /C:"Disk [0-9]"
echo ===============================================================================
set /p TARGET_DISK="Select Disk Number to format (or Q to quit): "
if /I "%TARGET_DISK%"=="Q" ( exit /b )
echo select disk %TARGET_DISK% > %TEMP%\dp.txt
echo clean >> %TEMP%\dp.txt
echo convert gpt >> %TEMP%\dp.txt
echo create partition efi size=1024 >> %TEMP%\dp.txt
echo format quick fs=fat32 label="System" >> %TEMP%\dp.txt
echo create partition msr size=16 >> %TEMP%\dp.txt
echo create partition primary >> %TEMP%\dp.txt
echo format quick fs=ntfs label="Windows" >> %TEMP%\dp.txt
diskpart.exe /s %TEMP%\dp.txt >nul
del %TEMP%\dp.txt
color 0A
echo SUCCESS: Disk %TARGET_DISK% is provisioned.
pause
"@
            Set-Content -Path (Join-Path $bootMount 'Windows\System32\FormatDisk.cmd') -Value $cmdScript -Encoding ASCII -Force
            Save-WinMintImageMount -MountDir $bootMount
        }
        catch {
            LogWarn "WinPE Utility injection failed: $_"
            Dismount-WinMintImageMount -MountDir $bootMount
        }
        finally {
            $null = Remove-Item $bootMount -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
