#Requires -Version 7.6

function Get-WinMintSetupShellRoot {
    $ctx = Get-WinMintFirstLogonContext
    Join-Path $ctx.PayloadDir 'setup-shell'
}

function Get-WinMintSetupShellLocalPaths {
    $winMintDir = Join-Path $env:LOCALAPPDATA 'WinMint'
    [ordered]@{
        WinMintDir = $winMintDir
        ControlPath = Join-Path $winMintDir 'setup-shell-control.json'
        StatusPath = Join-Path $winMintDir 'setup-shell-status.json'
        AgentStatePath = Join-Path $winMintDir 'state.json'
        LogDir = (Get-WinMintFirstLogonContext).LogDir
    }
}

function Read-WinMintSetupShellJson {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch { return $null }
}

function Save-WinMintSetupShellJson {
    param(
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][string]$Path
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 12 -Compress:$false), $utf8)
}

function Set-WinMintSetupShellControl {
    param(
        [ValidateSet('running', 'finishing', 'complete', 'failed', 'reboot')]
        [string]$Phase,
        [string]$ProfileName = '',
        [string]$Message = '',
        [ValidateSet('', 'locked', 'region', 'defaults', 'agent')]
        [string]$PreAgentStage = ''
    )

    $paths = Get-WinMintSetupShellLocalPaths
    $existing = Read-WinMintSetupShellJson -Path $paths.ControlPath
    $startedAt = if ($existing -and $existing.PSObject.Properties['startedAt']) {
        [string]$existing.startedAt
    }
    else {
        (Get-Date -Format o)
    }
    $existingStage = if ($existing -and $existing.PSObject.Properties['preAgentStage']) {
        [string]$existing.preAgentStage
    }
    else { '' }

    $controlPayload = [ordered]@{
        phase = $Phase
        startedAt = $startedAt
        updatedAt = (Get-Date -Format o)
        profileName = if ($ProfileName) { $ProfileName } elseif ($existing -and $existing.profileName) { [string]$existing.profileName } else { '' }
        message = $Message
        preAgentStage = if ($PreAgentStage) { $PreAgentStage } else { $existingStage }
    }
    Save-WinMintSetupShellJson -Path $paths.ControlPath -Value $controlPayload
    if (Get-Command Write-WinMintRuntimeState -ErrorAction SilentlyContinue) {
        Write-WinMintRuntimeState -Control $controlPayload
    }
}

function Resolve-WinMintSetupShellPreAgentStage {
    param(
        [string]$PreAgentStage,
        $Control
    )

    if (-not [string]::IsNullOrWhiteSpace($PreAgentStage)) { return $PreAgentStage }
    if ($Control -and $Control.PSObject.Properties['preAgentStage']) {
        $fromControl = [string]$Control.preAgentStage
        if (-not [string]::IsNullOrWhiteSpace($fromControl)) { return $fromControl }
    }
    return ''
}

function Merge-WinMintSetupShellPreAgentStageControl {
    param([Parameter(Mandatory)][string]$PreAgentStage)

    if ([string]::IsNullOrWhiteSpace($PreAgentStage)) { return }
    $paths = Get-WinMintSetupShellLocalPaths
    $existing = Read-WinMintSetupShellJson -Path $paths.ControlPath
    if (-not $existing) { return }

    $payload = [ordered]@{
        phase = [string]$existing.phase
        startedAt = [string]$existing.startedAt
        updatedAt = (Get-Date -Format o)
        profileName = if ($existing.PSObject.Properties['profileName']) { [string]$existing.profileName } else { '' }
        message = if ($existing.PSObject.Properties['message']) { [string]$existing.message } else { '' }
        preAgentStage = $PreAgentStage
    }
    Save-WinMintSetupShellJson -Path $paths.ControlPath -Value $payload
}

function Get-WinMintSetupShellProfileName {
    $setupProfile = Read-WinMintFirstLogonSetupProfile
    if ($setupProfile) {
        foreach ($key in @('profileName', 'profile')) {
            if (-not $setupProfile.PSObject.Properties[$key]) { continue }
            $name = [string]$setupProfile.$key
            if (-not [string]::IsNullOrWhiteSpace($name)) { return $name }
        }
    }
    return 'WinMint preset'
}

function Get-WinMintSetupShellGroupLabel {
    param([string]$GroupId)

    foreach ($group in @(Get-WinMintSetupShellGroupDefinitions)) {
        if ([string]$group.Id -eq $GroupId) { return [string]$group.Label }
    }
    return 'Setting up'
}

function Get-WinMintSetupShellGroupDefinition {
    param([string]$GroupId)

    foreach ($group in @(Get-WinMintSetupShellGroupDefinitions)) {
        if ([string]$group.Id -eq $GroupId) { return $group }
    }
    return $null
}

function Get-WinMintSetupShellGroupShellTitle {
    param([string]$GroupId)

    $group = Get-WinMintSetupShellGroupDefinition -GroupId $GroupId
    if ($group -and $group.ShellTitle) { return [string]$group.ShellTitle }
    return Get-WinMintSetupShellGroupLabel -GroupId $GroupId
}

function Get-WinMintSetupShellModuleCatalog {
    $catalogPath = Get-WinMintSetupShellCatalogPath
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) { return @() }
    return @(Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-WinMintSetupShellCatalogEntry {
    param([string]$RuntimeStepName)

    if ([string]::IsNullOrWhiteSpace($RuntimeStepName)) { return $null }
    foreach ($entry in @(Get-WinMintSetupShellModuleCatalog)) {
        if ([string]$entry.RuntimeStepName -eq $RuntimeStepName) { return $entry }
    }
    return $null
}

function Resolve-WinMintSetupShellProfileSelectionSuffix {
    param(
        [Parameter(Mandatory)][string[]]$Items
    )

    if (@($Items).Count -eq 0) { return '' }
    return ' (' + (@($Items | ForEach-Object { [string]$_ }) -join ', ') + ')'
}

function Resolve-WinMintSetupShellActionShellLabel {
    param(
        $Entry,
        $AgentProfile,
        [string]$ProfileDisplayName
    )

    if (-not $Entry) { return '' }
    $runtimeStep = [string]$Entry.RuntimeStepName
    $label = if ($Entry.PSObject.Properties['ShellLabel']) { [string]$Entry.ShellLabel } else { [string]$Entry.Title }
    if ([string]::IsNullOrWhiteSpace($label)) { return $runtimeStep }

    if ($runtimeStep -eq 'wsl' -and (Test-WinMintAgentWslRuntimeValidationSkipped -AgentProfile $AgentProfile)) {
        return 'Skip WSL runtime validation'
    }

    if (-not $AgentProfile) { return $label }

    switch ($runtimeStep) {
        'editors' {
            if ($AgentProfile.PSObject.Properties['editors']) {
                $suffix = Resolve-WinMintSetupShellProfileSelectionSuffix -Items @($AgentProfile.editors)
                if ($suffix) { return $label + $suffix }
            }
        }
        'browsers' {
            if ($AgentProfile.PSObject.Properties['browsers']) {
                $suffix = Resolve-WinMintSetupShellProfileSelectionSuffix -Items @($AgentProfile.browsers)
                if ($suffix) { return $label + $suffix }
            }
        }
        'wsl' {
            if ($AgentProfile.modules -and $AgentProfile.modules.PSObject.Properties['wsl']) {
                $wsl = $AgentProfile.modules.wsl
                if ($wsl.PSObject.Properties['distros']) {
                    $suffix = Resolve-WinMintSetupShellProfileSelectionSuffix -Items @($wsl.distros)
                    if ($suffix) { return $label + $suffix }
                }
            }
        }
        'desktop-environment' {
            $layers = [System.Collections.Generic.List[string]]::new()
            if ($AgentProfile.modules -and $AgentProfile.modules.PSObject.Properties['shell']) {
                $shell = $AgentProfile.modules.shell
                foreach ($prop in $shell.PSObject.Properties) {
                    if ($prop.Name -eq 'enabled') { continue }
                    if ($prop.Value -is [bool] -and $prop.Value) {
                        $layers.Add($prop.Name) | Out-Null
                    }
                }
            }
            if ($layers.Count -gt 0) {
                return $label + (Resolve-WinMintSetupShellProfileSelectionSuffix -Items @($layers))
            }
        }
    }

    return $label
}

function Get-WinMintSetupShellRuntimeTaskLabel {
    param(
        [string]$RuntimeStepName,
        $AgentProfile,
        [string]$ProfileDisplayName
    )

    $entry = Get-WinMintSetupShellCatalogEntry -RuntimeStepName $RuntimeStepName
    return Resolve-WinMintSetupShellActionShellLabel `
        -Entry $entry `
        -AgentProfile $AgentProfile `
        -ProfileDisplayName $ProfileDisplayName
}

function Get-WinMintSetupShellDevlogTask {
    param(
        [string]$RuntimeStepName,
        [string]$Phase,
        [string]$FallbackLabel,
        [string]$ProfileDisplayName,
        $AgentProfile
    )

    switch ($Phase) {
        'finishing' { return Get-WinMintSetupShellGroupShellTitle -GroupId 'finish' }
        'complete' { return 'Release desktop lock' }
        'reboot' { return 'Restart to continue setup' }
        'failed' {
            if (-not [string]::IsNullOrWhiteSpace($RuntimeStepName)) {
                $short = Get-WinMintSetupShellRuntimeTaskLabel `
                    -RuntimeStepName $RuntimeStepName `
                    -AgentProfile $AgentProfile `
                    -ProfileDisplayName $ProfileDisplayName
                if ([string]::IsNullOrWhiteSpace($short)) { $short = $FallbackLabel }
                return "Failed: $short"
            }
            return 'Setup step failed'
        }
    }

    $label = Get-WinMintSetupShellRuntimeTaskLabel `
        -RuntimeStepName $RuntimeStepName `
        -AgentProfile $AgentProfile `
        -ProfileDisplayName $ProfileDisplayName
    if (-not [string]::IsNullOrWhiteSpace($label)) {
        return $label
    }
    if (-not [string]::IsNullOrWhiteSpace($FallbackLabel)) {
        $t = ([string]$FallbackLabel).Trim()
        if ($t.Length -gt 42) { return $t.Substring(0, 39) + '…' }
        return $t
    }
    return 'Working…'
}

function Get-WinMintSetupShellCatalogPath {
    Join-Path (Join-Path (Get-WinMintFirstLogonContext).PayloadDir 'WinMintAgent') 'agent-module-catalog.json'
}

function Get-WinMintSetupShellAgentProfilePath {
    Join-Path (Join-Path (Get-WinMintFirstLogonContext).PayloadDir 'WinMintAgent') 'WinMintAgentProfile.json'
}

function Test-WinMintSetupShellModuleEnabled {
    param(
        [Parameter(Mandatory)]$AgentProfile,
        [Parameter(Mandatory)][string]$Enablement
    )

    switch ($Enablement) {
        'always' { return $true }
        'modules.packageManagers.enabled' { return Test-WinMintSetupShellNestedEnabled -Root $AgentProfile.modules -Name 'packageManagers' }
        'modules.wsl.enabled' { return Test-WinMintSetupShellNestedEnabled -Root $AgentProfile.modules -Name 'wsl' }
        'modules.git.enabled' { return Test-WinMintSetupShellNestedEnabled -Root $AgentProfile.modules -Name 'git' }
        'modules.dotfiles.enabled' { return Test-WinMintSetupShellNestedEnabled -Root $AgentProfile.modules -Name 'dotfiles' }
        'modules.launcherKey.enabled' { return Test-WinMintSetupShellNestedEnabled -Root $AgentProfile.modules -Name 'launcherKey' }
        'modules.phoneLink.enabled' { return Test-WinMintSetupShellNestedEnabled -Root $AgentProfile.modules -Name 'phoneLink' }
        'modules.shell.enabled' { return Test-WinMintSetupShellNestedEnabled -Root $AgentProfile.modules -Name 'shell' }
        'modules.windhawk.enabled' { return Test-WinMintSetupShellNestedEnabled -Root $AgentProfile.modules -Name 'windhawk' }
        'modules.liveInstallAudit.enabled' { return Test-WinMintSetupShellNestedEnabled -Root $AgentProfile.modules -Name 'liveInstallAudit' }
        'browsers.count > 0' { return (@($AgentProfile.browsers).Count -gt 0) }
        'editors.count > 0' { return (@($AgentProfile.editors).Count -gt 0) }
        default { return $false }
    }
}

function Test-WinMintSetupShellNestedEnabled {
    param(
        $Root,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Root) { return $false }
    $prop = $Root.PSObject.Properties[$Name]
    if (-not $prop) { return $false }
    $cfg = $prop.Value
    if ($cfg.PSObject.Properties['enabled']) { return [bool]$cfg.enabled }
    foreach ($p in $cfg.PSObject.Properties) {
        if ($p.Value -is [bool] -and $p.Value) { return $true }
    }
    return $false
}

function Get-WinMintSetupShellGroupDefinitions {
    @(
        @{ Id = 'prepare'; Label = 'Preparing system'; ShellTitle = 'Lock desktop and stage setup shell'; Always = $true }
        @{ Id = 'region'; Label = 'Restoring your region'; ShellTitle = 'Restore locale, region, and time zone'; Always = $true }
        @{ Id = 'tools'; Label = 'Installing tools' }
        @{ Id = 'dev'; Label = 'Development environment' }
        @{ Id = 'desktop'; Label = 'Desktop and shell' }
        @{ Id = 'finish'; Label = 'Finishing setup'; ShellTitle = 'Apply shell pins and release desktop lock'; Always = $true }
    )
}

function Get-WinMintSetupShellVisibleGroups {
    param($AgentProfile)

    $visible = [System.Collections.Generic.List[object]]::new()
    foreach ($group in @(Get-WinMintSetupShellGroupDefinitions)) {
        if ($group.Always) {
            $visible.Add($group) | Out-Null
            continue
        }
        $catalog = @(Get-WinMintSetupShellModuleCatalog)
        $enabled = $false
        foreach ($entry in $catalog) {
            if ([string]$entry.Group -ne [string]$group.Id) { continue }
            if (Test-WinMintSetupShellModuleEnabled -AgentProfile $AgentProfile -Enablement ([string]$entry.Enablement)) {
                $enabled = $true
                break
            }
        }
        if ($enabled) { $visible.Add($group) | Out-Null }
    }
    return @($visible)
}

function Resolve-WinMintSetupShellRuntimeGroupId {
    param([Parameter(Mandatory)][string]$RuntimeStepName)

    $entry = Get-WinMintSetupShellCatalogEntry -RuntimeStepName $RuntimeStepName
    if ($entry -and $entry.PSObject.Properties['Group']) {
        return [string]$entry.Group
    }
    return 'tools'
}

function Get-WinMintSetupShellModuleTitle {
    param([Parameter(Mandatory)][string]$RuntimeStepName)

    $catalogPath = Get-WinMintSetupShellCatalogPath
    if (-not (Test-Path -LiteralPath $catalogPath)) { return $RuntimeStepName }
    $catalog = @(Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    foreach ($entry in $catalog) {
        if ([string]$entry.RuntimeStepName -eq $RuntimeStepName) {
            return [string]$entry.Title
        }
    }
    return $RuntimeStepName
}

function Get-WinMintSetupShellAgentProgress {
    param($AgentState)

    if (-not $AgentState -or -not $AgentState.PSObject.Properties['steps']) {
        return @{
            CurrentRuntimeStep = ''
            CompletedCount = 0
            TotalCount = 0
            RunStatus = 'pending'
            FailedSteps = @()
            NeedsReboot = $false
            WarningCount = 0
        }
    }

    $catalogPath = Get-WinMintSetupShellCatalogPath
    $profilePath = Get-WinMintSetupShellAgentProfilePath
    $agentProfile = $null
    if (Test-Path -LiteralPath $profilePath) {
        $agentProfile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    $enabledSteps = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $catalogPath) {
        foreach ($entry in @(Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json)) {
            if ($agentProfile -and (Test-WinMintSetupShellModuleEnabled -AgentProfile $agentProfile -Enablement ([string]$entry.Enablement))) {
                $enabledSteps.Add([string]$entry.RuntimeStepName) | Out-Null
            }
        }
    }

    $completed = 0
    $current = ''
    $needsReboot = $false
    $warningCount = 0
    foreach ($stepName in @($enabledSteps)) {
        $key = "module:$stepName"
        $stepState = $null
        if ($AgentState.steps.PSObject.Properties[$key]) {
            $stepState = $AgentState.steps.PSObject.Properties[$key].Value
        }
        $status = if ($stepState -and $stepState.PSObject.Properties['status']) { [string]$stepState.status } else { 'pending' }
        if ($status -in @('ok', 'skipped')) { $completed++ }
        elseif ($status -eq 'needsReboot') { $needsReboot = $true; $current = $stepName }
        elseif ($status -in @('running', 'retryable', 'failed') -and -not $current) { $current = $stepName }
        if ($status -eq 'skipped' -and $stepState -and $stepState.PSObject.Properties['error']) { $warningCount++ }
    }

    $runStatus = 'pending'
    if ($AgentState.PSObject.Properties['run'] -and $AgentState.run.PSObject.Properties['status']) {
        $runStatus = [string]$AgentState.run.status
    }
    $failedSteps = @()
    if ($AgentState.run -and $AgentState.run.PSObject.Properties['failedSteps']) {
        $failedSteps = @($AgentState.run.failedSteps | ForEach-Object { [string]$_ })
    }

    return @{
        CurrentRuntimeStep = $current
        CompletedCount = $completed
        TotalCount = @($enabledSteps).Count
        RunStatus = $runStatus
        FailedSteps = $failedSteps
        NeedsReboot = $needsReboot
        WarningCount = $warningCount
    }
}

function Resolve-WinMintSetupShellCurrentGroupId {
    param(
        [string]$Phase,
        [string]$PreAgentStage,
        $Progress
    )

    if ($Phase -eq 'finishing' -or $Phase -eq 'complete') { return 'finish' }
    if ($PreAgentStage -eq 'region') { return 'region' }
    if ($PreAgentStage -in @('defaults', 'agent') -or $Progress.CurrentRuntimeStep -or $Progress.CompletedCount -gt 0) {
        if ($Progress.CurrentRuntimeStep) {
            return Resolve-WinMintSetupShellRuntimeGroupId -RuntimeStepName $Progress.CurrentRuntimeStep
        }
        if ($PreAgentStage -eq 'defaults') { return 'prepare' }
        return 'tools'
    }
    return 'prepare'
}

function Get-WinMintSetupShellGroupStepStatus {
    param(
        [string]$GroupId,
        [string]$CurrentGroupId,
        [string]$Phase,
        [string]$PreAgentStage,
        $Progress,
        [ref]$PassedCurrent
    )

    if ($GroupId -eq 'prepare') {
        if ($PreAgentStage -eq 'locked') { return 'current' }
        if ($PreAgentStage -in @('region', 'defaults', 'agent') -or $Progress.CompletedCount -gt 0 -or $Progress.CurrentRuntimeStep) { return 'done' }
        if ($CurrentGroupId -eq 'prepare') { return 'current' }
        return 'pending'
    }
    if ($GroupId -eq 'region') {
        if ($PreAgentStage -eq 'region') { return 'current' }
        if ($PreAgentStage -in @('defaults', 'agent') -or $Progress.CompletedCount -gt 0 -or $Progress.CurrentRuntimeStep) { return 'done' }
        if ($CurrentGroupId -eq 'region') { return 'current' }
        return 'pending'
    }
    if ($GroupId -eq 'finish') {
        if ($Phase -eq 'complete') { return 'done' }
        if ($Phase -eq 'finishing') { return 'current' }
        return 'pending'
    }
    if ($GroupId -eq $CurrentGroupId) {
        $PassedCurrent.Value = $true
        return 'current'
    }
    if ($PassedCurrent.Value) { return 'pending' }
    return 'done'
}

function Get-WinMintSetupShellHeadlineLabels {
    param(
        [string]$Phase,
        [string]$PreAgentStage,
        $Progress,
        $Control,
        [string]$ProfileName,
        $AgentProfile
    )

    $currentLabel = Get-WinMintSetupShellGroupShellTitle -GroupId 'prepare'
    $banner = ''
    $bannerKind = ''
    if ($Phase -eq 'finishing') {
        $currentLabel = Get-WinMintSetupShellGroupShellTitle -GroupId 'finish'
    }
    elseif ($Phase -eq 'complete') {
        $currentLabel = 'Release desktop lock'
    }
    elseif ($PreAgentStage -eq 'region') {
        $currentLabel = Get-WinMintSetupShellGroupShellTitle -GroupId 'region'
    }
    elseif ($PreAgentStage -eq 'defaults') {
        $currentLabel = 'Apply Explorer and desktop defaults'
    }
    elseif ($Phase -eq 'reboot' -or $Progress.NeedsReboot) {
        $currentLabel = 'Restart to continue setup'
        $banner = 'Setup will resume after restart.'
        $bannerKind = 'warn'
    }
    elseif ($Phase -eq 'failed' -or $Progress.RunStatus -eq 'failed') {
        if ($Progress.CurrentRuntimeStep) {
            $currentLabel = Get-WinMintSetupShellRuntimeTaskLabel `
                -RuntimeStepName $Progress.CurrentRuntimeStep `
                -AgentProfile $AgentProfile `
                -ProfileDisplayName $ProfileName
            if ([string]::IsNullOrWhiteSpace($currentLabel)) {
                $currentLabel = 'An optional setup step failed.'
            }
        }
        else {
            $currentLabel = 'An optional setup step failed.'
        }
        $banner = 'Setup will retry on next sign-in. You can review the setup log for details.'
        $bannerKind = 'fail'
    }
    elseif ($Progress.CurrentRuntimeStep) {
        $currentLabel = Get-WinMintSetupShellRuntimeTaskLabel `
            -RuntimeStepName $Progress.CurrentRuntimeStep `
            -AgentProfile $AgentProfile `
            -ProfileDisplayName $ProfileName
        if ([string]::IsNullOrWhiteSpace($currentLabel)) {
            $currentLabel = 'Continuing setup…'
        }
    }
    elseif ($Progress.CompletedCount -gt 0) {
        $currentLabel = 'Continuing setup…'
    }

    if ($Control -and $Control.PSObject.Properties['message'] -and -not [string]::IsNullOrWhiteSpace([string]$Control.message)) {
        if ($Phase -in @('finishing', 'complete') -and -not $banner) {
            $banner = [string]$Control.message
            $bannerKind = 'warn'
        }
    }

    return @{
        CurrentLabel = $currentLabel
        Banner = $banner
        BannerKind = $bannerKind
    }
}

function Get-WinMintSetupShellPipelineWeights {
    @{
        prepare = 0.05
        region = 0.10
        defaults = 0.10
        agent = 0.70
        finish = 0.05
    }
}

function Get-WinMintSetupShellStepEstimateMs {
    param([string]$RuntimeStepName)

    $estimates = @{
        'package-managers' = 14000
        editors = 22000
        wsl = 28000
        browsers = 18000
        windhawk = 12000
        'desktop-environment' = 9000
    }
    if ($RuntimeStepName -and $estimates.ContainsKey($RuntimeStepName)) {
        return [int]$estimates[$RuntimeStepName]
    }
    return 8000
}

function Get-WinMintSetupShellStepSegments {
    param([string]$RuntimeStepName)

    $segments = @{
        'package-managers' = @(
            @{ at = 0.0; task = 'Scoop bootstrap' }
            @{ at = 0.38; task = 'MinGit via Scoop' }
            @{ at = 0.68; task = 'Starship nerd-font-symbols preset' }
        )
        windhawk = @(
            @{ at = 0.0; task = 'Windhawk install' }
            @{ at = 0.45; task = 'Windhawk preset apply' }
        )
        browsers = @(
            @{ at = 0.0; task = 'Browser install (winget)' }
            @{ at = 0.52; task = 'Browser install (winget)' }
        )
        editors = @(
            @{ at = 0.0; task = 'Editor install (winget/Scoop)' }
            @{ at = 0.55; task = 'Neovim environment hook' }
        )
        wsl = @(
            @{ at = 0.0; task = 'WSL feature enablement' }
            @{ at = 0.45; task = 'WSL distro install' }
        )
    }
    if ($RuntimeStepName -and $segments.ContainsKey($RuntimeStepName)) {
        return @($segments[$RuntimeStepName])
    }
    return @()
}

function Test-WinMintSetupShellGenericCommandMessage {
    param([string]$Message)
    if ([string]::IsNullOrWhiteSpace($Message)) { return $true }
    return [bool]($Message -match '(?i)^Running\s+[\w.-]+\.(exe|cmd|bat|ps1)\.?\s*$')
}

function Format-WinMintSetupShellTaskLabelText {
    param([Parameter(Mandatory)][string]$Text, [int]$MaxLength = 72)

    $trimmed = $Text.Trim()
    if ($trimmed.Length -le $MaxLength) { return $trimmed }
    return $trimmed.Substring(0, [Math]::Max(1, $MaxLength - 1)) + '…'
}

function Get-WinMintSetupShellLiveTaskHint {
    param($AgentState)

    if (-not $AgentState -or -not $AgentState.PSObject.Properties['run']) { return '' }
    $run = $AgentState.run
    if (-not $run -or -not $run.PSObject.Properties['progressEventLog']) { return '' }
    $path = [string]$run.progressEventLog
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }

    try {
        $lines = @(Get-Content -LiteralPath $path -Tail 64 -Encoding UTF8 -ErrorAction Stop)
    }
    catch { return '' }

    $events = [System.Collections.Generic.List[object]]::new()
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
        try { $events.Add(($lines[$i] | ConvertFrom-Json)) | Out-Null } catch { }
    }

    foreach ($preferType in @('install', 'download', 'step', 'user', 'notice', 'command')) {
        foreach ($ev in $events) {
            $type = if ($ev.PSObject.Properties['type']) { [string]$ev.type } else { '' }
            $status = if ($ev.PSObject.Properties['status']) { [string]$ev.status } else { '' }
            $message = if ($ev.PSObject.Properties['message']) { [string]$ev.message } else { '' }
            if ($type -ne $preferType) { continue }
            if ($status -notin @('running', 'info', 'ok')) { continue }
            if ($status -eq 'ok' -and $type -ne 'user') { continue }
            if ([string]::IsNullOrWhiteSpace($message)) { continue }
            if ($type -eq 'command' -and (Test-WinMintSetupShellGenericCommandMessage -Message $message)) { continue }
            return (Format-WinMintSetupShellTaskLabelText -Text $message)
        }
    }
    return ''
}

function Get-WinMintSetupShellSegmentTask {
    param(
        [string]$RuntimeStepName,
        $AgentState
    )

    $segments = @(Get-WinMintSetupShellStepSegments -RuntimeStepName $RuntimeStepName)
    if ($segments.Count -eq 0) { return '' }

    $startedAt = $null
    if ($AgentState -and $AgentState.PSObject.Properties['steps']) {
        $key = "module:$RuntimeStepName"
        if ($AgentState.steps.PSObject.Properties[$key]) {
            $stepState = $AgentState.steps.PSObject.Properties[$key].Value
            $stepStatus = if ($stepState.PSObject.Properties['status']) { [string]$stepState.status } else { '' }
            if ($stepState.PSObject.Properties['startedAt']) {
                $startedAt = [datetime]$stepState.startedAt
            }
            elseif ($stepStatus -eq 'running' -and $stepState.PSObject.Properties['updatedAt']) {
                $startedAt = [datetime]$stepState.updatedAt
            }
        }
    }

    if (-not $startedAt) { return [string]$segments[0].task }

    $estimateMs = [Math]::Max(1000, (Get-WinMintSetupShellStepEstimateMs -RuntimeStepName $RuntimeStepName))
    $intraT = [Math]::Min(0.95, ((Get-Date) - $startedAt).TotalMilliseconds / $estimateMs)
    $task = [string]$segments[0].task
    foreach ($segment in $segments) {
        if ($intraT -ge [double]$segment.at) { $task = [string]$segment.task }
    }
    return $task
}

function Resolve-WinMintSetupShellRunningTaskLabel {
    param(
        [string]$RuntimeStepName,
        [string]$Phase,
        [string]$FallbackLabel,
        [string]$ProfileDisplayName,
        $AgentState,
        $AgentProfile
    )

    $base = Get-WinMintSetupShellDevlogTask `
        -RuntimeStepName $RuntimeStepName `
        -Phase $Phase `
        -FallbackLabel $FallbackLabel `
        -ProfileDisplayName $ProfileDisplayName `
        -AgentProfile $AgentProfile

    if ($Phase -ne 'running' -or [string]::IsNullOrWhiteSpace($RuntimeStepName)) {
        return $base
    }

    $liveHint = Get-WinMintSetupShellLiveTaskHint -AgentState $AgentState
    if (-not [string]::IsNullOrWhiteSpace($liveHint)) {
        return $liveHint
    }

    $segmentTask = Get-WinMintSetupShellSegmentTask -RuntimeStepName $RuntimeStepName -AgentState $AgentState
    if (-not [string]::IsNullOrWhiteSpace($segmentTask)) { return $segmentTask }

    return $base
}

function Get-WinMintSetupShellElapsedMs {
    param($Control)

    if (-not $Control -or -not $Control.PSObject.Properties['startedAt']) { return 0 }
    $startedRaw = [string]$Control.startedAt
    if ([string]::IsNullOrWhiteSpace($startedRaw)) { return 0 }
    try {
        $started = [datetime]$startedRaw
        return [long][Math]::Max(0, ((Get-Date) - $started).TotalMilliseconds)
    }
    catch { return 0 }
}

function Test-WinMintSetupShellPreAgentComplete {
    param(
        [string]$PreAgentStage,
        $Progress
    )

    return $PreAgentStage -in @('defaults', 'agent') `
        -or $Progress.CompletedCount -gt 0 `
        -or -not [string]::IsNullOrWhiteSpace([string]$Progress.CurrentRuntimeStep)
}

function Get-WinMintSetupShellPipelineProgress {
    param(
        [string]$Phase,
        [string]$PreAgentStage,
        $Progress
    )

    $weights = Get-WinMintSetupShellPipelineWeights

    if ($Phase -eq 'complete') {
        return @{ progressPct = 100.0; progressMode = 'determinate' }
    }
    if ($Phase -eq 'finishing') {
        $pct = (1.0 - $weights.finish + ($weights.finish * 0.5)) * 100.0
        return @{ progressPct = $pct; progressMode = 'determinate' }
    }
    if ($Phase -in @('failed', 'reboot')) {
        $agentFraction = if ($Progress.TotalCount -gt 0) {
            [Math]::Min(1.0, $Progress.CompletedCount / [double]$Progress.TotalCount)
        }
        else { 0.0 }
        $completed = 0.0
        if (Test-WinMintSetupShellPreAgentComplete -PreAgentStage $PreAgentStage -Progress $Progress) {
            $completed += $weights.prepare + $weights.region + $weights.defaults
        }
        $pct = ($completed + ($weights.agent * $agentFraction)) * 100.0
        return @{ progressPct = $pct; progressMode = 'determinate' }
    }

    if ($Progress.TotalCount -eq 0 -and $PreAgentStage -in @('', 'locked', 'region', 'defaults')) {
        return @{ progressPct = 0.0; progressMode = 'indeterminate' }
    }

    $completedWeight = 0.0
    $currentWeight = 0.0
    $segmentFraction = 0.0

    if ($PreAgentStage -eq 'locked') {
        $currentWeight = $weights.prepare
        $segmentFraction = 0.5
    }
    elseif ($PreAgentStage -in @('region', 'defaults', 'agent') -or (Test-WinMintSetupShellPreAgentComplete -PreAgentStage $PreAgentStage -Progress $Progress)) {
        $completedWeight += $weights.prepare
    }

    if ($PreAgentStage -eq 'region') {
        $currentWeight = $weights.region
        $segmentFraction = 0.5
    }
    elseif ($PreAgentStage -in @('defaults', 'agent') -or (Test-WinMintSetupShellPreAgentComplete -PreAgentStage 'defaults' -Progress $Progress)) {
        if ($PreAgentStage -ne 'locked') { $completedWeight += $weights.region }
    }

    if ($PreAgentStage -eq 'defaults') {
        $currentWeight = $weights.defaults
        $segmentFraction = 0.5
    }
    elseif ($PreAgentStage -eq 'agent' -or $Progress.CompletedCount -gt 0 -or $Progress.CurrentRuntimeStep) {
        if ($PreAgentStage -notin @('locked', 'region')) { $completedWeight += $weights.defaults }
    }

    if ($Progress.TotalCount -gt 0) {
        $agentFraction = ($Progress.CompletedCount + $(if ($Progress.CurrentRuntimeStep) { 0.5 } else { 0 })) / [double]$Progress.TotalCount
        $agentFraction = [Math]::Min(1.0, [Math]::Max(0.0, $agentFraction))
        $pct = ($completedWeight + ($weights.agent * $agentFraction)) * 100.0
        return @{ progressPct = $pct; progressMode = 'determinate' }
    }

    $pct = ($completedWeight + ($currentWeight * $segmentFraction)) * 100.0
    return @{ progressPct = $pct; progressMode = 'determinate' }
}

function Get-WinMintSetupShellStatusSteps {
    param(
        [string]$Phase,
        [string]$PreAgentStage,
        [string]$CurrentGroupId,
        $Progress,
        $AgentProfile
    )

    $visibleGroups = @(Get-WinMintSetupShellVisibleGroups -AgentProfile $AgentProfile)
    if ($visibleGroups.Count -eq 0) {
        $visibleGroups = @(Get-WinMintSetupShellGroupDefinitions | Where-Object { $_.Always })
    }

    $passed = $false
    $steps = [System.Collections.Generic.List[object]]::new()
    foreach ($group in $visibleGroups) {
        $status = Get-WinMintSetupShellGroupStepStatus `
            -GroupId ([string]$group.Id) `
            -CurrentGroupId $CurrentGroupId `
            -Phase $Phase `
            -PreAgentStage $PreAgentStage `
            -Progress $Progress `
            -PassedCurrent ([ref]$passed)
        $steps.Add([ordered]@{
                id = [string]$group.Id
                label = [string]$group.Label
                status = $status
            }) | Out-Null
    }
    return @($steps)
}

function Get-WinMintSetupShellGroupStepIndex {
    param(
        $VisibleGroups,
        [string]$CurrentGroupId
    )

    for ($i = 0; $i -lt @($VisibleGroups).Count; $i++) {
        if ([string]$VisibleGroups[$i].Id -eq $CurrentGroupId) {
            return $i + 1
        }
    }
    return 1
}

function Get-WinMintProvisioningProjection {
    param(
        $Control,
        $AgentState,
        $AgentProfile,
        [string]$LogDir,
        [ValidateSet('', 'locked', 'region', 'defaults', 'agent')]
        [string]$PreAgentStage = ''
    )

    $phase = 'running'
    if ($Control) {
        if ($Control -is [System.Collections.IDictionary] -and $Control.Contains('phase')) {
            $phase = [string]$Control['phase']
        }
        elseif ($Control.PSObject.Properties['phase']) {
            $phase = [string]$Control.phase
        }
    }
    $preAgentStage = Resolve-WinMintSetupShellPreAgentStage -PreAgentStage $PreAgentStage -Control $Control
    $profileName = if ($Control) {
        if ($Control -is [System.Collections.IDictionary] -and $Control.Contains('profileName') -and $Control['profileName']) {
            [string]$Control['profileName']
        }
        elseif ($Control.PSObject.Properties['profileName'] -and $Control.profileName) {
            [string]$Control.profileName
        }
        else { (Get-WinMintSetupShellProfileName) }
    }
    else { (Get-WinMintSetupShellProfileName) }
    $progress = Get-WinMintSetupShellAgentProgress -AgentState $AgentState
    $currentGroupId = Resolve-WinMintSetupShellCurrentGroupId -Phase $phase -PreAgentStage $preAgentStage -Progress $progress
    $headlineLabels = Get-WinMintSetupShellHeadlineLabels -Phase $phase -PreAgentStage $preAgentStage -Progress $progress -Control $Control -ProfileName $profileName -AgentProfile $AgentProfile
    $pipeline = Get-WinMintSetupShellPipelineProgress -Phase $phase -PreAgentStage $preAgentStage -Progress $progress

    $visibleGroups = @(Get-WinMintSetupShellVisibleGroups -AgentProfile $AgentProfile)
    if ($visibleGroups.Count -eq 0) {
        $visibleGroups = @(Get-WinMintSetupShellGroupDefinitions | Where-Object { $_.Always })
    }
    $stepIndex = Get-WinMintSetupShellGroupStepIndex -VisibleGroups $visibleGroups -CurrentGroupId $currentGroupId
    $stepTotal = [Math]::Max(1, @($visibleGroups).Count)
    $groupLabel = Get-WinMintSetupShellGroupLabel -GroupId $currentGroupId
    $taskLabel = Resolve-WinMintSetupShellRunningTaskLabel `
        -RuntimeStepName $progress.CurrentRuntimeStep `
        -Phase $phase `
        -FallbackLabel $headlineLabels.CurrentLabel `
        -ProfileDisplayName $profileName `
        -AgentState $AgentState `
        -AgentProfile $AgentProfile
    $steps = Get-WinMintSetupShellStatusSteps `
        -Phase $phase `
        -PreAgentStage $preAgentStage `
        -CurrentGroupId $currentGroupId `
        -Progress $progress `
        -AgentProfile $AgentProfile

    return [ordered]@{
        phase = $phase
        groupLabel = $groupLabel
        taskLabel = $taskLabel
        stepIndex = $stepIndex
        stepTotal = $stepTotal
        progressPct = [Math]::Round([double]$pipeline.progressPct, 2)
        progressMode = [string]$pipeline.progressMode
        profileName = $profileName
        elapsedMs = Get-WinMintSetupShellElapsedMs -Control $Control
        steps = $steps
        banner = $headlineLabels.Banner
        bannerKind = $headlineLabels.BannerKind
        logDir = $LogDir
        updatedAt = (Get-Date -Format o)
    }
}

function Update-WinMintSetupShellStatus {
    param(
        [string]$ShellRoot = '',
        [ValidateSet('', 'locked', 'region', 'defaults', 'agent')]
        [string]$PreAgentStage = ''
    )

    $paths = Get-WinMintSetupShellLocalPaths
    $control = Read-WinMintSetupShellJson -Path $paths.ControlPath
    $agentState = Read-WinMintSetupShellJson -Path $paths.AgentStatePath
    $profilePath = Get-WinMintSetupShellAgentProfilePath
    $agentProfile = $null
    if (Test-Path -LiteralPath $profilePath) {
        $agentProfile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    if (-not $ShellRoot) {
        try { $ShellRoot = Get-WinMintSetupShellRoot } catch { $ShellRoot = '' }
    }

    if (-not [string]::IsNullOrWhiteSpace($PreAgentStage)) {
        Merge-WinMintSetupShellPreAgentStageControl -PreAgentStage $PreAgentStage
        $control = Read-WinMintSetupShellJson -Path $paths.ControlPath
    }

    $status = Get-WinMintProvisioningProjection `
        -Control $control `
        -AgentState $agentState `
        -AgentProfile $agentProfile `
        -LogDir $paths.LogDir `
        -PreAgentStage $PreAgentStage

    Save-WinMintSetupShellJson -Path $paths.StatusPath -Value $status
    if (Get-Command Write-WinMintRuntimeState -ErrorAction SilentlyContinue) {
        $controlForRuntime = if ($control) { $control } else { Read-WinMintSetupShellJson -Path $paths.ControlPath }
        Write-WinMintRuntimeState -Control $controlForRuntime -Display $status
    }
    Copy-WinMintSetupShellStatusMirror -Status $status -ShellRoot $ShellRoot
    return $status
}

function Copy-WinMintSetupShellStatusMirror {
    param(
        [Parameter(Mandatory)]$Status,
        [string]$ShellRoot = ''
    )

    if ([string]::IsNullOrWhiteSpace($ShellRoot)) { return }
    $mirrorPath = Join-Path $ShellRoot 'setup-shell-status.json'
    Save-WinMintSetupShellJson -Path $mirrorPath -Value $Status
}

function Start-WinMintSetupShellStatusPump {
    param(
        [int]$PollIntervalMs = 1500
    )

    Stop-WinMintSetupShellStatusPump
    $script:WinMintSetupShellStatusPumpPollMs = [Math]::Max(500, $PollIntervalMs)
    $script:WinMintSetupShellStatusPumpLastTick = [datetime]::MinValue
}

function Invoke-WinMintSetupShellStatusPumpTick {
    param(
        [string]$ShellRoot = ''
    )

    if (-not $script:WinMintSetupShellStatusPumpPollMs) {
        return
    }

    $now = [datetime]::UtcNow
    $elapsedMs = ($now - $script:WinMintSetupShellStatusPumpLastTick).TotalMilliseconds
    if ($script:WinMintSetupShellStatusPumpLastTick -ne [datetime]::MinValue -and $elapsedMs -lt $script:WinMintSetupShellStatusPumpPollMs) {
        return
    }

    $script:WinMintSetupShellStatusPumpLastTick = $now
    try {
        Update-WinMintSetupShellStatus -ShellRoot $ShellRoot | Out-Null
    }
    catch { }
}

function Stop-WinMintSetupShellStatusPump {
    $script:WinMintSetupShellStatusPumpPollMs = $null
    $script:WinMintSetupShellStatusPumpLastTick = [datetime]::MinValue
}
