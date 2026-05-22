#Requires -Version 7.3

function New-WinMintBuildReport {
    param(
        [Parameter(Mandatory)]$Config,
        [string]$DetectedArchitecture,
        [string[]]$Warnings = @(),
        [string[]]$Failures = @()
    )

    [pscustomobject]@{
        generatedAt = [DateTimeOffset]::Now.ToString('o')
        sourceIso = $Config.SourceIso
        detectedArchitecture = $DetectedArchitecture
        editionMode = $Config.EditionMode
        selectedEdition = if ($Config.EditionMode -eq 'Fixed') { $Config.Edition } else { 'Target license' }
        targetDevice = $Config.TargetDevice
        profile = $Config.Profile
        profileGroups = @($Config.ProfileGroups)
        appxRemovalPrefixes = $Config.AppxPackages
        registryTweaks = $Config.RegistryTweaks
        windowsFeatures = $Config.Features
        tweaks = $Config.Tweaks
        drivers = $Config.Drivers
        regional = @{
            timeZoneId = $Config.TimeZoneId
            userLocale = $Config.UserLocale
            homeLocationGeoId = $Config.HomeLocationGeoId
            dmaInterop = $Config.DmaInterop
        }
        setupScripts = $Config.SetupScripts
        assets = $Config.Assets
        editors = $Config.Editors
        desktop = @{
            windhawk = $Config.InstallWindhawk
            yasb = $Config.InstallYasb
            komorebi = $Config.InstallKomorebi
        }
        wsl = @{
            distro = $Config.Wsl2Distro
            distros = @($Config.Wsl2Distros)
        }
        features = @{
            launcher = [string]$Config.Launcher
            flowEverything = [bool]$Config.InstallFlowEverything
            raycast = [bool]$Config.InstallRaycast
            liveInstallAudit = [bool]$Config.LiveInstallAudit
            phoneLink = [bool]$Config.PhoneLink
        }
        warnings = $Warnings
        failures = $Failures
    }
}

function Save-WinMintBuildReport {
    param([Parameter(Mandatory)]$Report)

    $out = Get-WinMintOutputDirectory
    $jsonPath = Join-Path $out 'WinMint-BuildReport.json'
    $mdPath = Join-Path $out 'WinMint-BuildReport.md'

    $Report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $desktopLayers = [System.Collections.Generic.List[string]]::new()
    if ([bool]$Report.desktop.windhawk) { $desktopLayers.Add('Windhawk') | Out-Null }
    if ([bool]$Report.desktop.yasb) { $desktopLayers.Add('YASB') | Out-Null }
    if ([bool]$Report.desktop.komorebi) { $desktopLayers.Add('Komorebi') | Out-Null }
    $desktopMarkdown = if ($desktopLayers.Count) {
        ($desktopLayers | ForEach-Object { "- $_" }) -join "`n"
    }
    else {
        '- Standard Windows'
    }
    $profileGroups = @($Report.profileGroups | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $profileGroupsText = if ($profileGroups.Count) { $profileGroups -join ', ' } else { $Report.profile }

    $md = @(
        '# WinMint Build Report'
        ''
        "| Item | Value |"
        "| --- | --- |"
        "| Generated | $($Report.generatedAt) |"
        "| Source ISO | $($Report.sourceIso) |"
        "| Detected architecture | $($Report.detectedArchitecture) |"
        "| Edition mode | $($Report.editionMode) |"
        "| Edition | $($Report.selectedEdition) |"
        "| Target device | $($Report.targetDevice) |"
        "| Profile | $($Report.profile) |"
        "| Profile groups | $profileGroupsText |"
        ''
        '## Selected Editors'
        (($Report.editors | ForEach-Object { "- $_" }) -join "`n")
        ''
        '## Desktop Layers'
        $desktopMarkdown
        ''
        '## Warnings'
        ($(if ($Report.warnings.Count) { ($Report.warnings | ForEach-Object { "- $_" }) -join "`n" } else { '- None' }))
        ''
        '## Failures'
        ($(if ($Report.failures.Count) { ($Report.failures | ForEach-Object { "- $_" }) -join "`n" } else { '- None' }))
    ) -join "`n"
    Set-Content -LiteralPath $mdPath -Value $md -Encoding UTF8

    [pscustomobject]@{ Json = $jsonPath; Markdown = $mdPath }
}

function Save-WinMintDryRunArtifacts {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$DetectedArchitecture,
        [Parameter(Mandatory)][object[]]$InstallImages,
        [Parameter(Mandatory)]$PreparedSetup,
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string]$IsoContents,
        [Parameter(Mandatory)][string]$InstallWim
    )

    $out = Get-WinMintOutputDirectory
    $artifactDir = Join-Path $out ('dry-run-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $null = New-Item -ItemType Directory -Path $artifactDir -Force
    # The dry-run autounattend.xml contains the base64-encoded password, so
    # restrict the artifact directory to Administrators + SYSTEM. output\ itself
    # may be world-readable on the developer's machine.
    try {
        $acl = [System.Security.AccessControl.DirectorySecurity]::new()
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
            'BUILTIN\Administrators', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
        $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
            'NT AUTHORITY\SYSTEM', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
        Set-Acl -Path $artifactDir -AclObject $acl
    } catch { Write-Verbose "Dry-run artifact ACL: $($_.Exception.Message)" }

    $autounattendPath = Join-Path $artifactDir 'autounattend.xml'
    $setupProfilePath = Join-Path $artifactDir 'WinMintSetupProfile.json'
    $agentProfilePath = Join-Path $artifactDir 'WinMintAgentProfile.json'
    $setupPlanPath = Join-Path $artifactDir 'WinMintSetupPlan.json'
    $editionsPath = Join-Path $artifactDir 'editions.json'
    $summaryPath = Join-Path $artifactDir 'summary.json'
    $readmePath = Join-Path $artifactDir 'README.md'

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($autounattendPath, [string]$PreparedSetup.AutounattendXml, $utf8NoBom)
    if (-not [string]::IsNullOrWhiteSpace([string]$PreparedSetup.SetupProfileJson)) {
        [System.IO.File]::WriteAllText($setupProfilePath, [string]$PreparedSetup.SetupProfileJson + [Environment]::NewLine, $utf8NoBom)
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$PreparedSetup.AgentProfileJson)) {
        [System.IO.File]::WriteAllText($agentProfilePath, [string]$PreparedSetup.AgentProfileJson + [Environment]::NewLine, $utf8NoBom)
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$PreparedSetup.SetupPlanJson)) {
        [System.IO.File]::WriteAllText($setupPlanPath, [string]$PreparedSetup.SetupPlanJson + [Environment]::NewLine, $utf8NoBom)
    }

    $editionRows = @(
        $InstallImages | ForEach-Object {
            [ordered]@{
                index = $_.ImageIndex
                name = $_.ImageName
                description = $_.ImageDescription
            }
        }
    )
    $editionRows | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $editionsPath -Encoding UTF8

    $summary = [ordered]@{
        generatedAt = [DateTimeOffset]::Now.ToString('o')
        mode = 'DryRun'
        sourceIso = $Config.SourceIso
        detectedArchitecture = $DetectedArchitecture
        editionMode = $Config.EditionMode
        selectedEdition = if ($Config.EditionMode -eq 'Fixed') { $Config.Edition } else { 'Target license' }
        servicedEditionCount = @($InstallImages).Count
        workDir = $WorkDir
        isoContents = $IsoContents
        installWim = $InstallWim
        diskMode = switch ([string]$Config.DiskMode) {
            'DualBootReserved' { 'Dual boot reserved space' }
            'AutoWipeDisk0'    { 'Auto-partition primary disk' }
            default            { 'Manual partition' }
        }
        diskLayout = $Config.DiskLayout
        drivers = $Config.Drivers
        desktop = [ordered]@{
            windhawk = [bool]$Config.InstallWindhawk
            yasb = [bool]$Config.InstallYasb
            komorebi = [bool]$Config.InstallKomorebi
        }
        wsl = [ordered]@{
            distros = @($Config.Wsl2Distros)
        }
        features = [ordered]@{
            launcher = [string]$Config.Launcher
            flowEverything = [bool]$Config.InstallFlowEverything
            raycast = [bool]$Config.InstallRaycast
            liveInstallAudit = [bool]$Config.LiveInstallAudit
            phoneLink = [bool]$Config.PhoneLink
        }
        artifacts = [ordered]@{
            autounattend = $autounattendPath
            setupProfile = if (Test-Path -LiteralPath $setupProfilePath) { $setupProfilePath } else { '' }
            agentProfile = if (Test-Path -LiteralPath $agentProfilePath) { $agentProfilePath } else { '' }
            setupPlan = if (Test-Path -LiteralPath $setupPlanPath) { $setupPlanPath } else { '' }
            editions = $editionsPath
            summary = $summaryPath
        }
        dryRunGuarantee = 'No WIM customization, output ISO creation, disk prep, or USB write was performed.'
    }
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

    $readme = @(
        '# WinMint Dry-Run Artifacts'
        ''
        'This folder contains generated setup artifacts from a read-only dry run.'
        ''
        '| File | Purpose |'
        '| --- | --- |'
        '| autounattend.xml | Generated Windows Setup answer file. |'
        '| WinMintSetupPlan.json | Backend setup-phase plan for CLI/UI inspection and audit. |'
        '| WinMintSetupProfile.json | SetupComplete, DefaultUser, FirstLogon, and maintenance profile. |'
        '| WinMintAgentProfile.json | FirstLogon agent profile generated from selected app/desktop/WSL choices. |'
        '| editions.json | Install images detected in the source ISO. |'
        '| summary.json | Dry-run summary and artifact paths. |'
        ''
        'Dry-run does not mount an install image, service WIMs, create an ISO, prepare disks, or write USB media.'
    ) -join "`n"
    Set-Content -LiteralPath $readmePath -Value $readme -Encoding UTF8

    [pscustomobject]@{
        Directory = $artifactDir
        Autounattend = $autounattendPath
        SetupProfile = if (Test-Path -LiteralPath $setupProfilePath) { $setupProfilePath } else { $null }
        AgentProfile = if (Test-Path -LiteralPath $agentProfilePath) { $agentProfilePath } else { $null }
        SetupPlan = if (Test-Path -LiteralPath $setupPlanPath) { $setupPlanPath } else { $null }
        Editions = $editionsPath
        Summary = $summaryPath
        Readme = $readmePath
    }
}

$script:WinMintBuildManifest = $null

function Get-WinMintRegistryTweakGroupValue {
    param(
        [Parameter(Mandatory)]$Group,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($Group -is [System.Collections.IDictionary]) {
        if ($Group.ContainsKey($Name)) { return $Group[$Name] }
        return $Default
    }

    $property = $Group.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function ConvertTo-WinMintRegistryAuditPath {
    param([Parameter(Mandatory)][string]$Path)

    switch -Regex ($Path) {
        '^zSOFTWARE\\(.+)$' { return "HKEY_LOCAL_MACHINE\SOFTWARE\$($Matches[1])" }
        '^zSYSTEM\\(.+)$' { return "HKEY_LOCAL_MACHINE\SYSTEM\$($Matches[1])" }
        '^zDEFAULT\\(.+)$' { return "HKEY_USERS\.DEFAULT\$($Matches[1])" }
        '^zNTUSER\\(.+)$' { return "HKEY_USERS\.DEFAULT\$($Matches[1])" }
        default { return $Path }
    }
}

function ConvertTo-WinMintRegDwordText {
    param([Parameter(Mandatory)][string]$Value)

    $number = 0
    if ([int64]::TryParse($Value, [ref]$number)) {
        return ('dword:{0:x8}' -f $number)
    }
    return ('dword:{0:x8}' -f 0)
}

function ConvertTo-WinMintRegStringText {
    param([AllowNull()][string]$Value)

    $escaped = ([string]$Value) -replace '"', '\"'
    return '"' + $escaped + '"'
}

function ConvertTo-WinMintRegValueLine {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Type,
        [AllowNull()][string]$Value
    )

    $regName = if ([string]::IsNullOrWhiteSpace($Name)) { '@' } else { ConvertTo-WinMintRegStringText -Value $Name }
    $regValue = switch ($Type) {
        'REG_DWORD' { ConvertTo-WinMintRegDwordText -Value ([string]$Value) }
        default { ConvertTo-WinMintRegStringText -Value ([string]$Value) }
    }
    return "$regName=$regValue"
}

function New-WinMintRegistryTweakDetail {
    param(
        [Parameter(Mandatory)]$Group,
        [string]$Status = 'pending',
        [string]$ErrorMessage = ''
    )

    $setOps = @(Get-WinMintRegistryTweakGroupValue -Group $Group -Name 'set' -Default @())
    $removeOps = @(Get-WinMintRegistryTweakGroupValue -Group $Group -Name 'remove' -Default @())
    $rollbackCount = @(
        foreach ($entry in $setOps) {
            if ($null -ne (Get-WinMintRegistryTweakGroupValue -Group $entry -Name 'undo')) { $entry }
        }
        foreach ($entry in $removeOps) {
            if ($null -ne (Get-WinMintRegistryTweakGroupValue -Group $entry -Name 'restore')) { $entry }
        }
    ).Count

    [ordered]@{
        id = [string](Get-WinMintRegistryTweakGroupValue -Group $Group -Name 'id')
        description = [string](Get-WinMintRegistryTweakGroupValue -Group $Group -Name 'description')
        scope = [string](Get-WinMintRegistryTweakGroupValue -Group $Group -Name 'scope' -Default 'offline registry')
        risk = [string](Get-WinMintRegistryTweakGroupValue -Group $Group -Name 'risk' -Default 'low')
        reversible = [bool](Get-WinMintRegistryTweakGroupValue -Group $Group -Name 'reversible' -Default $false)
        phase = [string](Get-WinMintRegistryTweakGroupValue -Group $Group -Name 'phase' -Default 'offline-image')
        intent = [string](Get-WinMintRegistryTweakGroupValue -Group $Group -Name 'intent' -Default '')
        status = $Status
        setOperations = $setOps.Count
        removeOperations = $removeOps.Count
        rollbackOperations = $rollbackCount
        rollbackCoverage = if (($setOps.Count + $removeOps.Count) -eq 0) {
            'none'
        } elseif ($rollbackCount -eq 0) {
            'none'
        } elseif ($rollbackCount -eq ($setOps.Count + $removeOps.Count)) {
            'full'
        } else {
            'partial'
        }
        error = $ErrorMessage
    }
}

function Initialize-WinMintBuildManifest {
    param([Parameter(Mandatory)]$Config)

    $layers = [System.Collections.Generic.List[string]]::new()
    if ($Config.InstallWindhawk) { $layers.Add('windhawk') }
    if ($Config.InstallYasb)     { $layers.Add('yasb') }
    if ($Config.InstallKomorebi) { $layers.Add('komorebi') }

    $script:WinMintBuildManifest = [ordered]@{
        schemaVersion       = 1
        builtAt             = [DateTimeOffset]::Now.ToString('o')
        buildDurationSeconds = $null
        buildResult         = 'pending'
        source              = [ordered]@{
            isoPath      = [string]$Config.SourceIso
            architecture = [string]$Config.Architecture
            editions     = @()
        }
        target              = [ordered]@{
            diskMode   = [string]$Config.DiskMode
            diskLayout = $Config.DiskLayout
        }
        regional            = [ordered]@{
            timeZoneId = [string]$Config.TimeZoneId
            uiLanguage = [string]$Config.UILanguage
            systemLocale = [string]$Config.SystemLocale
            userLocale = [string]$Config.UserLocale
            inputLocale = [string]$Config.InputLocale
            homeLocationGeoId = [int]$Config.HomeLocationGeoId
            dmaInterop = [ordered]@{
                enabled = [bool]$Config.DmaInterop.Enabled
                setupCountry = [string]$Config.DmaInterop.SetupCountry
                setupUserLocale = [string]$Config.SetupUserLocale
                setupHomeLocationGeoId = [int]$Config.SetupHomeLocationGeoId
                restoreUserLocale = [string]$Config.UserLocale
                restoreHomeLocationGeoId = [int]$Config.HomeLocationGeoId
            }
        }
        removals            = [ordered]@{
            appxPrefixes        = @($Config.AppxPackages)
            appxRemoved         = @()
            appxRemovedCount    = 0
            capabilitiesRemoved = @()
            languagePackagesRemoved = @()
            languagePackagesRemovedCount = 0
            featuresEnabled     = @($Config.Features)
        }
        sizeDelta           = [ordered]@{
            sourceIsoBytes = 0
            installWimBeforeServicingBytes = 0
            installWimAfterServicingBytes = 0
            installWimAfterExportBytes = 0
            outputIsoBytes = 0
            outputMinusSourceBytes = 0
            outputToSourceRatio = 0
        }
        servicing           = [ordered]@{
            componentCleanup = 'StartComponentCleanup'
            resetBase = $false
            serviceabilityPolicy = 'Preserve component-store uninstall/repair metadata; do not run ResetBase by default.'
        }
        tweaks              = [ordered]@{
            registryGroupsApplied = @($Config.RegistryTweaks)
            registryGroups        = @(
                foreach ($group in @($script:RegistryTweaks)) {
                    $status = if (@($Config.RegistryTweaks) -contains [string]$group.id) { 'pending' } else { 'skipped-not-selected' }
                    New-WinMintRegistryTweakDetail -Group $group -Status $status
                }
            )
        }
        drivers             = [ordered]@{
            source        = [string]$Config.Drivers.Source
            path          = [string]$Config.Drivers.Path
            injectedCount = 0
            infNames      = @()
        }
        payloads            = [System.Collections.Generic.List[object]]::new()
        firstLogon          = [ordered]@{
            editors      = @($Config.Editors)
            wslDistros   = @($Config.Wsl2Distros)
            desktopLayers = $layers.ToArray()
        }
        riskFlags           = @(if ($Config.RegistryTweaks -contains 'hardware-bypass') { 'hardware-bypass' })
    }
}

function Add-WinMintManifestRegistryTweakEvent {
    param(
        [Parameter(Mandatory)]$Group,
        [Parameter(Mandatory)][ValidateSet('applied', 'skipped-not-selected', 'skipped-conditional', 'failed')] [string]$Status,
        [string]$ErrorMessage = ''
    )

    if ($null -eq $script:WinMintBuildManifest) { return }
    if (-not $script:WinMintBuildManifest.tweaks.Contains('registryGroups')) {
        $script:WinMintBuildManifest.tweaks['registryGroups'] = @()
    }

    $detail = New-WinMintRegistryTweakDetail -Group $Group -Status $Status -ErrorMessage $ErrorMessage
    $groups = [System.Collections.Generic.List[object]]::new()
    $replaced = $false
    foreach ($existing in @($script:WinMintBuildManifest.tweaks.registryGroups)) {
        if ([string]$existing.id -eq [string]$detail.id) {
            $groups.Add($detail) | Out-Null
            $replaced = $true
        }
        else {
            $groups.Add($existing) | Out-Null
        }
    }
    if (-not $replaced) { $groups.Add($detail) | Out-Null }
    $script:WinMintBuildManifest.tweaks.registryGroups = $groups.ToArray()
}

function New-WinMintTweakRollbackRegContent {
    param([object[]]$Groups)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('Windows Registry Editor Version 5.00') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('; WinMint best-effort tweak rollback. Review before importing.') | Out-Null
    foreach ($group in @($Groups)) {
        $setOps = @(Get-WinMintRegistryTweakGroupValue -Group $group -Name 'set' -Default @())
        $removeOps = @(Get-WinMintRegistryTweakGroupValue -Group $group -Name 'remove' -Default @())
        $wroteHeader = $false
        foreach ($entry in $setOps) {
            $undo = Get-WinMintRegistryTweakGroupValue -Group $entry -Name 'undo'
            if ($null -eq $undo) { continue }
            if (-not $wroteHeader) {
                $lines.Add('') | Out-Null
                $lines.Add("; $([string](Get-WinMintRegistryTweakGroupValue -Group $group -Name 'id'))") | Out-Null
                $wroteHeader = $true
            }
            $path = ConvertTo-WinMintRegistryAuditPath -Path ([string](Get-WinMintRegistryTweakGroupValue -Group $entry -Name 'path'))
            $name = [string](Get-WinMintRegistryTweakGroupValue -Group $entry -Name 'name')
            $action = [string](Get-WinMintRegistryTweakGroupValue -Group $undo -Name 'action' -Default 'set')
            $lines.Add("[$path]") | Out-Null
            if ($action -eq 'delete') {
                $regName = if ([string]::IsNullOrWhiteSpace($name)) { '@' } else { ConvertTo-WinMintRegStringText -Value $name }
                $lines.Add("$regName=-") | Out-Null
            }
            else {
                $type = [string](Get-WinMintRegistryTweakGroupValue -Group $undo -Name 'type' -Default ([string](Get-WinMintRegistryTweakGroupValue -Group $entry -Name 'type')))
                $value = [string](Get-WinMintRegistryTweakGroupValue -Group $undo -Name 'value' -Default '')
                $lines.Add((ConvertTo-WinMintRegValueLine -Name $name -Type $type -Value $value)) | Out-Null
            }
            $lines.Add('') | Out-Null
        }
        foreach ($entry in $removeOps) {
            $restore = Get-WinMintRegistryTweakGroupValue -Group $entry -Name 'restore'
            if ($null -eq $restore) { continue }
            if (-not $wroteHeader) {
                $lines.Add('') | Out-Null
                $lines.Add("; $([string](Get-WinMintRegistryTweakGroupValue -Group $group -Name 'id'))") | Out-Null
                $wroteHeader = $true
            }
            $path = ConvertTo-WinMintRegistryAuditPath -Path ([string](Get-WinMintRegistryTweakGroupValue -Group $entry -Name 'path'))
            $lines.Add("[$path]") | Out-Null
            foreach ($value in @(Get-WinMintRegistryTweakGroupValue -Group $restore -Name 'values' -Default @())) {
                $lines.Add((ConvertTo-WinMintRegValueLine `
                    -Name ([string](Get-WinMintRegistryTweakGroupValue -Group $value -Name 'name')) `
                    -Type ([string](Get-WinMintRegistryTweakGroupValue -Group $value -Name 'type')) `
                    -Value ([string](Get-WinMintRegistryTweakGroupValue -Group $value -Name 'value')))) | Out-Null
            }
            $lines.Add('') | Out-Null
        }
    }

    return ($lines.ToArray() -join "`r`n") + "`r`n"
}

function Save-WinMintTweakAuditArtifacts {
    param([Parameter(Mandatory)][string]$OutputDir)

    if ($null -eq $script:WinMintBuildManifest) { return $null }
    $groups = @($script:WinMintBuildManifest.tweaks.registryGroups)
    $audit = [ordered]@{
        generatedAt = [DateTimeOffset]::Now.ToString('o')
        selected = @($script:WinMintBuildManifest.tweaks.registryGroupsApplied)
        groups = $groups
        summary = [ordered]@{
            applied = @($groups | Where-Object status -eq 'applied').Count
            skippedNotSelected = @($groups | Where-Object status -eq 'skipped-not-selected').Count
            skippedConditional = @($groups | Where-Object status -eq 'skipped-conditional').Count
            failed = @($groups | Where-Object status -eq 'failed').Count
        }
    }

    $jsonPath = Join-Path $OutputDir 'WinMint-TweakAudit.json'
    $mdPath = Join-Path $OutputDir 'WinMint-TweakAudit.md'
    $regPath = Join-Path $OutputDir 'WinMint-TweakRollback.reg'
    $audit | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    Set-Content -LiteralPath $regPath -Value (New-WinMintTweakRollbackRegContent -Groups $script:RegistryTweaks) -Encoding Unicode

    $rows = @(
        '# WinMint Tweak Audit'
        ''
        "| Status | Count |"
        "| --- | ---: |"
        "| Applied | $($audit.summary.applied) |"
        "| Skipped (not selected) | $($audit.summary.skippedNotSelected) |"
        "| Skipped (conditional) | $($audit.summary.skippedConditional) |"
        "| Failed | $($audit.summary.failed) |"
        ''
        '## Registry Groups'
        ''
        '| ID | Status | Risk | Rollback | Intent |'
        '| --- | --- | --- | --- | --- |'
    )
    foreach ($group in $groups) {
        $rows += "| $($group.id) | $($group.status) | $($group.risk) | $($group.rollbackCoverage) | $($group.intent) |"
    }
    Set-Content -LiteralPath $mdPath -Value ($rows -join "`n") -Encoding UTF8

    return [pscustomobject]@{ Json = $jsonPath; Markdown = $mdPath; Rollback = $regPath }
}

function Add-WinMintManifestPayload {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$SourceUrl,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Sha256,
        [Parameter(Mandatory)][long]$SizeBytes
    )
    if ($null -eq $script:WinMintBuildManifest) { return }
    $key = '{0}|{1}|{2}|{3}|{4}' -f $Name, $SourceUrl, $Version, $Sha256, $SizeBytes
    foreach ($payload in @($script:WinMintBuildManifest.payloads)) {
        $existingKey = '{0}|{1}|{2}|{3}|{4}' -f `
            ([string]$payload.name),
            ([string]$payload.sourceUrl),
            ([string]$payload.version),
            ([string]$payload.sha256),
            ([long]$payload.sizeBytes)
        if ($existingKey -eq $key) { return }
    }

    $script:WinMintBuildManifest.payloads.Add([ordered]@{
        name      = $Name
        sourceUrl = $SourceUrl
        version   = $Version
        sha256    = $Sha256
        sizeBytes = $SizeBytes
    })
}

function Get-WinMintDeduplicatedManifestPayload {
    param([object[]]$Payloads)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $deduped = [System.Collections.Generic.List[object]]::new()
    foreach ($payload in @($Payloads)) {
        if ($null -eq $payload) { continue }
        $key = '{0}|{1}|{2}|{3}|{4}' -f `
            ([string]$payload.name),
            ([string]$payload.sourceUrl),
            ([string]$payload.version),
            ([string]$payload.sha256),
            ([long]$payload.sizeBytes)
        if ($seen.Add($key)) {
            $deduped.Add($payload) | Out-Null
        }
    }

    return $deduped.ToArray()
}

function Save-WinMintBuildManifest {
    param(
        [Parameter(Mandatory)][string]$OutputDir,
        [string]$OutputIsoPath = '',
        [switch]$DryRun,
        [switch]$Failed
    )
    if ($null -eq $script:WinMintBuildManifest) { return }

    $started = [DateTimeOffset]::Parse($script:WinMintBuildManifest.builtAt)
    $script:WinMintBuildManifest.buildDurationSeconds = [math]::Round(([DateTimeOffset]::Now - $started).TotalSeconds, 1)
    $script:WinMintBuildManifest.buildResult = if ($Failed) { 'failed' } elseif ($DryRun) { 'dry-run' } else { 'success' }

    if (-not [string]::IsNullOrWhiteSpace($OutputIsoPath) -and (Test-Path -LiteralPath $OutputIsoPath)) {
        $isoHash = (Get-FileHash -LiteralPath $OutputIsoPath -Algorithm SHA256).Hash
        $isoSize = (Get-Item -LiteralPath $OutputIsoPath).Length
        $script:WinMintBuildManifest['output'] = [ordered]@{
            isoPath   = $OutputIsoPath
            sha256    = $isoHash
            sizeBytes = $isoSize
        }
    }

    $script:WinMintBuildManifest.payloads = @(Get-WinMintDeduplicatedManifestPayload -Payloads @($script:WinMintBuildManifest.payloads))
    $null = Save-WinMintTweakAuditArtifacts -OutputDir $OutputDir

    $path = Join-Path $OutputDir 'WinMint-BuildManifest.json'
    $script:WinMintBuildManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Write-WinMintDryRunArtifactSummary {
    param([Parameter(Mandatory)]$Artifacts)

    if (Get-Command Write-SpectreKeyValueTable -ErrorAction SilentlyContinue) {
        try {
            Write-SectionHeader 'Dry run artifacts' -Accent Green -RuleColor Green -DimLine 'Generated files are safe to inspect; the Windows image was not modified.'
            Write-SpectreKeyValueTable -Title '[bold green]Saved report[/]' -TableColor Green -Rows @(
                [pscustomobject]@{ Item = 'Folder'; Value = "[white]$([Spectre.Console.Markup]::Escape($Artifacts.Directory))[/]" }
                [pscustomobject]@{ Item = 'Answer file'; Value = "[silver]$([Spectre.Console.Markup]::Escape($Artifacts.Autounattend))[/]" }
                [pscustomobject]@{ Item = 'Setup profile'; Value = "[silver]$([Spectre.Console.Markup]::Escape([string]$Artifacts.SetupProfile))[/]" }
                [pscustomobject]@{ Item = 'Agent profile'; Value = "[silver]$([Spectre.Console.Markup]::Escape([string]$Artifacts.AgentProfile))[/]" }
                [pscustomobject]@{ Item = 'Setup plan'; Value = "[silver]$([Spectre.Console.Markup]::Escape([string]$Artifacts.SetupPlan))[/]" }
                [pscustomobject]@{ Item = 'Detected editions'; Value = "[silver]$([Spectre.Console.Markup]::Escape($Artifacts.Editions))[/]" }
                [pscustomobject]@{ Item = 'Summary'; Value = "[silver]$([Spectre.Console.Markup]::Escape($Artifacts.Summary))[/]" }
            )
            return
        } catch {
            # Spectre rendering failed (no console / WPF UI ThreadJob) — fall through to plain summary.
        }
    }

    Write-Host "Dry-run artifacts: $($Artifacts.Directory)"
    Write-Host "  Answer file:       $($Artifacts.Autounattend)"
    Write-Host "  Setup profile:     $([string]$Artifacts.SetupProfile)"
    Write-Host "  Agent profile:     $([string]$Artifacts.AgentProfile)"
    Write-Host "  Setup plan:        $([string]$Artifacts.SetupPlan)"
    Write-Host "  Detected editions: $($Artifacts.Editions)"
    Write-Host "  Summary:           $($Artifacts.Summary)"
}
