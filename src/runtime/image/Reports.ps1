#Requires -Version 7.6

function Get-WinMintBuildDeltaSummary {
    param(
        [object]$BuildDelta = $null,
        [string]$BuildDeltaPath = ''
    )

    if ($null -eq $BuildDelta -and -not [string]::IsNullOrWhiteSpace($BuildDeltaPath) -and
        (Test-Path -LiteralPath $BuildDeltaPath -PathType Leaf)) {
        $BuildDelta = Get-Content -LiteralPath $BuildDeltaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    elseif ($null -eq $BuildDelta -and (Get-Command Get-WinMintBuildManifest -ErrorAction SilentlyContinue)) {
        $manifest = Get-WinMintBuildManifest
        if ($manifest -and $manifest.audit -and $manifest.audit.records) {
            $BuildDelta = [ordered]@{
                schemaVersion = 1
                generatedAt = [string]$manifest.audit.generatedAt
                records = @($manifest.audit.records)
            }
        }
    }
    elseif ($null -eq $BuildDelta -and (Get-Command Get-WinMintBuildDeltaCatalog -ErrorAction SilentlyContinue)) {
        $BuildDelta = Get-WinMintBuildDeltaCatalog
    }

    $records = @()
    if ($BuildDelta -and $BuildDelta.PSObject.Properties['records']) {
        $records = @($BuildDelta.records)
    }

    $phaseCounts = [ordered]@{}
    $kindCounts = [ordered]@{}
    $userControlledCount = 0
    foreach ($record in $records) {
        $phase = [string]$record.phase
        $kind = [string]$record.kind
        if (-not [string]::IsNullOrWhiteSpace($phase)) {
            $phaseCounts[$phase] = (0 + $phaseCounts[$phase]) + 1
        }
        if (-not [string]::IsNullOrWhiteSpace($kind)) {
            $kindCounts[$kind] = (0 + $kindCounts[$kind]) + 1
        }
        if ([bool]$record.userControlled) {
            $userControlledCount++
        }
    }

    $highlights = [System.Collections.Generic.List[object]]::new()
    foreach ($record in @($records | Select-Object -First 8)) {
        $highlights.Add([pscustomobject]@{
                id = [string]$record.id
                title = [string]$record.title
                phase = [string]$record.phase
                kind = [string]$record.kind
                changeCount = @($record.changes).Count
            }) | Out-Null
    }

    [pscustomobject]@{
        totalRecords = @($records).Count
        userControlledCount = $userControlledCount
        phaseCounts = [pscustomobject]$phaseCounts
        kindCounts = [pscustomobject]$kindCounts
        highlights = @($highlights.ToArray())
    }
}

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
            aiRemoval = $Config.AiRemoval
        }
        setupScripts = $Config.SetupScripts
        assets = $Config.Assets
        editors = $Config.Editors
        desktop = @{
            windhawk = $Config.InstallWindhawk
            yasb = $Config.InstallYasb
            thide = $Config.InstallThide
            komorebi = $Config.InstallKomorebi
            nilesoft = $Config.InstallNilesoft
        }
        wsl = @{
            distro = $Config.Wsl2Distro
            distros = @($Config.Wsl2Distros)
        }
        features = @{
            launcher = [string]$Config.Launcher
            liveInstallAudit = [bool]$Config.LiveInstallAudit
            phoneLink = [bool]$Config.PhoneLink
        }
        updates = @{
            mode = [string]$Config.Updates.Mode
            targetFeatureVersion = [string]$Config.Updates.TargetFeatureVersion
            releaseCadence = [string]$Config.Updates.ReleaseCadence
            includeOptionalPreviews = [bool]$Config.Updates.IncludeOptionalPreviews
            payloadRoot = [string]$Config.Updates.PayloadRoot
            provisionedApps = [bool]$Config.Updates.ProvisionedApps
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
    if ([bool]$Report.desktop.thide) { $desktopLayers.Add('thide') | Out-Null }
    if ([bool]$Report.desktop.komorebi) { $desktopLayers.Add('Komorebi') | Out-Null }
    $desktopMarkdown = if ($desktopLayers.Count) {
        ($desktopLayers | ForEach-Object { "- $_" }) -join "`n"
    }
    else {
        '- Standard Windows'
    }
    $deltaSummary = Get-WinMintBuildDeltaSummary
    $phaseSummaryMarkdown = if (@($deltaSummary.phaseCounts.PSObject.Properties).Count -gt 0) {
        (@($deltaSummary.phaseCounts.PSObject.Properties) | ForEach-Object {
                "- $($_.Name): $($_.Value)"
            }) -join "`n"
    }
    else {
        '- None'
    }
    $kindSummaryMarkdown = if (@($deltaSummary.kindCounts.PSObject.Properties).Count -gt 0) {
        (@($deltaSummary.kindCounts.PSObject.Properties) | ForEach-Object {
                "- $($_.Name): $($_.Value)"
            }) -join "`n"
    }
    else {
        '- None'
    }
    $highlightMarkdown = if (@($deltaSummary.highlights).Count -gt 0) {
        (@($deltaSummary.highlights) | ForEach-Object {
                "- $($_.title) [$($_.phase)]"
            }) -join "`n"
    }
    else {
        '- None'
    }
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
        "| Image updates | $($Report.updates.mode) ($($Report.updates.releaseCadence), $($Report.updates.targetFeatureVersion)) |"
        "| Update payload root | $($Report.updates.payloadRoot) |"
        ''
        '## Selected Editors'
        (($Report.editors | ForEach-Object { "- $_" }) -join "`n")
        ''
        '## Desktop Layers'
        $desktopMarkdown
        ''
        '## Build Delta Summary'
        "| Item | Value |"
        "| --- | --- |"
        "| Records | $($deltaSummary.totalRecords) |"
        "| User-controlled | $($deltaSummary.userControlledCount) |"
        ''
        '### By Phase'
        $phaseSummaryMarkdown
        ''
        '### By Kind'
        $kindSummaryMarkdown
        ''
        '### Highlights'
        $highlightMarkdown
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

function ConvertTo-WinMintYamlSingleQuoted {
    param([AllowNull()][string]$Value)

    $escaped = ([string]$Value) -replace "'", "''"
    return "'$escaped'"
}

function ConvertTo-WinMintWingetConfigureSource {
    param([AllowNull()][string]$Source)

    switch ([string]$Source) {
        'store' { return 'msstore' }
        'winget' { return 'winget' }
        default { return '' }
    }
}

function Get-WinMintWingetHandoffToolIds {
    param([Parameter(Mandatory)]$Config)

    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($id in @($Config.Browsers)) {
        if ([string]::IsNullOrWhiteSpace([string]$id) -or [string]$id -eq 'edge') { continue }
        $ids.Add([string]$id) | Out-Null
    }
    foreach ($id in @($Config.Editors)) {
        if ([string]::IsNullOrWhiteSpace([string]$id)) { continue }
        $ids.Add([string]$id) | Out-Null
    }
    if ([bool]$Config.InstallWindhawk) { $ids.Add('windhawk') | Out-Null }
    if ([bool]$Config.InstallYasb) { $ids.Add('yasb') | Out-Null }
    if ([bool]$Config.InstallYasb -or [bool]$Config.InstallWindhawk) {
        $ids.Add("vcredist-$([string]$Config.Architecture)") | Out-Null
    }
    if ([bool]$Config.InstallKomorebi) {
        $ids.Add('komorebi') | Out-Null
        $ids.Add('whkd') | Out-Null
    }
    if ([bool]$Config.InstallNilesoft) { $ids.Add('nilesoft') | Out-Null }

    return @($ids.ToArray() | Select-Object -Unique)
}

function Save-WinMintWingetConfigurationHandoff {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$OutputDir,
        [string]$PackagesPath = (Get-WinMintPath -Name ConfigRoot -ChildPath 'packages.json')
    )

    $null = New-Item -ItemType Directory -Path $OutputDir -Force
    $path = Join-Path $OutputDir 'WinMint-Toolchain.winget'
    $tools = @{}
    if (Test-Path -LiteralPath $PackagesPath -PathType Leaf) {
        $manifest = Get-Content -LiteralPath $PackagesPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($manifest.PSObject.Properties['tools']) {
            foreach ($toolProperty in @($manifest.tools.PSObject.Properties)) {
                $tools[[string]$toolProperty.Name] = $toolProperty.Value
            }
        }
    }

    $toolIds = @(Get-WinMintWingetHandoffToolIds -Config $Config)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# yaml-language-server: $schema=https://aka.ms/configuration-dsc-schema/0.2') | Out-Null
    $lines.Add('# Generated by WinMint as a reviewable handoff artifact. WinMint does not auto-run this file.') | Out-Null
    $lines.Add('properties:') | Out-Null
    $lines.Add('  assertions:') | Out-Null
    $lines.Add('    - resource: Microsoft.Windows.Developer/OsVersion') | Out-Null
    $lines.Add('      directives:') | Out-Null
    $lines.Add('        description: Verify Windows 11 or newer') | Out-Null
    $lines.Add('        allowPrerelease: true') | Out-Null
    $lines.Add('      settings:') | Out-Null
    $lines.Add("        MinVersion: '10.0.22000'") | Out-Null
    $lines.Add('  resources:') | Out-Null

    $written = 0
    foreach ($toolId in $toolIds) {
        if (-not $tools.ContainsKey($toolId)) { continue }
        $tool = $tools[$toolId]
        $packageId = [string]$tool.id
        $source = ConvertTo-WinMintWingetConfigureSource -Source ([string]$tool.source)
        if ([string]::IsNullOrWhiteSpace($packageId) -or [string]::IsNullOrWhiteSpace($source)) { continue }
        $resourceId = 'pkg_' + (([string]$toolId).ToLowerInvariant() -replace '[^a-z0-9]+', '_').Trim('_')
        $displayName = [string]$tool.displayName
        if ([string]::IsNullOrWhiteSpace($displayName)) { $displayName = $packageId }

        $description = ConvertTo-WinMintYamlSingleQuoted -Value "Install $displayName"
        $packageValue = ConvertTo-WinMintYamlSingleQuoted -Value $packageId
        $sourceValue = ConvertTo-WinMintYamlSingleQuoted -Value $source
        $lines.Add('    - resource: Microsoft.WinGet.DSC/WinGetPackage') | Out-Null
        $lines.Add("      id: $resourceId") | Out-Null
        $lines.Add('      directives:') | Out-Null
        $lines.Add("        description: $description") | Out-Null
        $lines.Add('        securityContext: elevated') | Out-Null
        $lines.Add('      settings:') | Out-Null
        $lines.Add("        id: $packageValue") | Out-Null
        $lines.Add("        source: $sourceValue") | Out-Null
        $written++
    }
    if ($written -eq 0) {
        $lines.Add('    []') | Out-Null
    }
    $lines.Add('  configurationVersion: 0.2.0') | Out-Null
    Set-Content -LiteralPath $path -Value ($lines.ToArray() -join "`n") -Encoding UTF8

    if (Get-Command Set-WinMintManifestWingetConfigurationFact -ErrorAction SilentlyContinue) {
        Set-WinMintManifestWingetConfigurationFact -Path $path -PackageCount $written
    }

    return [pscustomobject]@{
        Path = $path
        PackageCount = $written
    }
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
    $wingetConfig = Save-WinMintWingetConfigurationHandoff -Config $Config -OutputDir $artifactDir
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
            thide = [bool]$Config.InstallThide
            komorebi = [bool]$Config.InstallKomorebi
            nilesoft = [bool]$Config.InstallNilesoft
        }
        wsl = [ordered]@{
            distros = @($Config.Wsl2Distros)
        }
        features = [ordered]@{
            launcher = [string]$Config.Launcher
            liveInstallAudit = [bool]$Config.LiveInstallAudit
            phoneLink = [bool]$Config.PhoneLink
        }
        artifacts = [ordered]@{
            autounattend = $autounattendPath
            setupProfile = if (Test-Path -LiteralPath $setupProfilePath) { $setupProfilePath } else { '' }
            agentProfile = if (Test-Path -LiteralPath $agentProfilePath) { $agentProfilePath } else { '' }
            setupPlan = if (Test-Path -LiteralPath $setupPlanPath) { $setupPlanPath } else { '' }
            wingetConfiguration = if ($wingetConfig -and (Test-Path -LiteralPath $wingetConfig.Path)) { $wingetConfig.Path } else { '' }
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
        '| WinMint-Toolchain.winget | Reviewable WinGet Configuration handoff for selected packages; not auto-run by WinMint. |'
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
        WingetConfiguration = if ($wingetConfig -and (Test-Path -LiteralPath $wingetConfig.Path)) { $wingetConfig.Path } else { $null }
        Editions = $editionsPath
        Summary = $summaryPath
        Readme = $readmePath
    }
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
            # Spectre rendering failed, usually because no real console is attached.
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

