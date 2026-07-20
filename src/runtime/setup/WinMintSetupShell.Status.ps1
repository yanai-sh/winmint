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

function Get-WinMintSetupShellCatalogPath {
    Join-Path (Join-Path (Get-WinMintFirstLogonContext).PayloadDir 'WinMintAgent') 'agent-module-catalog.json'
}

function Get-WinMintSetupShellAgentProfilePath {
    Join-Path (Join-Path (Get-WinMintFirstLogonContext).PayloadDir 'WinMintAgent') 'WinMintAgentProfile.json'
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

function Get-WinMintSetupShellStageDefinitions {
    @(
        @{ Id = 'ready'; Label = 'Getting things ready'; Weight = 0.15; Always = $true }
        @{ Id = 'apps'; Label = 'Installing your apps'; Weight = 0.55 }
        @{ Id = 'wsl'; Label = 'Setting up WSL'; Weight = 0.20 }
        @{ Id = 'finish'; Label = 'Finishing up'; Weight = 0.10; Always = $true }
    )
}

function Get-WinMintSetupShellStageLabel {
    param([string]$StageId)

    foreach ($stage in @(Get-WinMintSetupShellStageDefinitions)) {
        if ([string]$stage.Id -eq $StageId) { return [string]$stage.Label }
    }
    return 'Getting things ready'
}

function Resolve-WinMintSetupShellStageIdForRuntimeStep {
    param([string]$RuntimeStepName)

    switch ($RuntimeStepName) {
        { $_ -in @('profiles', 'package-managers', 'git', 'dotfiles') } { return 'ready' }
        { $_ -in @('editors', 'browsers', 'windhawk', 'desktop-environment', 'phone-link') } { return 'apps' }
        'wsl' { return 'wsl' }
        { $_ -in @('launcher-key', 'liveInstallAudit') } { return 'finish' }
        default { return 'ready' }
    }
}

function Test-WinMintSetupShellWslStageVisible {
    param($AgentProfile)

    if (-not $AgentProfile) { return $false }
    if (-not (Test-WinMintSetupShellModuleEnabled -AgentProfile $AgentProfile -Enablement 'modules.wsl.enabled')) {
        return $false
    }
    if (Get-Command Test-WinMintAgentWslRuntimeValidationSkipped -ErrorAction SilentlyContinue) {
        if (Test-WinMintAgentWslRuntimeValidationSkipped -AgentProfile $AgentProfile) { return $false }
    }
    return $true
}

function Test-WinMintSetupShellAppsStageVisible {
    param($AgentProfile)

    if (-not $AgentProfile) { return $false }
    if (@($AgentProfile.editors).Count -gt 0) { return $true }
    if (@($AgentProfile.browsers).Count -gt 0) { return $true }
    if (Test-WinMintSetupShellModuleEnabled -AgentProfile $AgentProfile -Enablement 'modules.windhawk.enabled') { return $true }
    if (Test-WinMintSetupShellModuleEnabled -AgentProfile $AgentProfile -Enablement 'modules.shell.enabled') { return $true }
    if (Test-WinMintSetupShellModuleEnabled -AgentProfile $AgentProfile -Enablement 'modules.phoneLink.enabled') { return $true }
    return $false
}

function Get-WinMintSetupShellVisibleStages {
    param($AgentProfile)

    $visible = [System.Collections.Generic.List[object]]::new()
    foreach ($stage in @(Get-WinMintSetupShellStageDefinitions)) {
        $id = [string]$stage.Id
        if ($stage.Always) {
            $visible.Add($stage) | Out-Null
            continue
        }
        if ($id -eq 'apps' -and (Test-WinMintSetupShellAppsStageVisible -AgentProfile $AgentProfile)) {
            $visible.Add($stage) | Out-Null
            continue
        }
        if ($id -eq 'wsl' -and (Test-WinMintSetupShellWslStageVisible -AgentProfile $AgentProfile)) {
            $visible.Add($stage) | Out-Null
        }
    }
    return @($visible)
}

function Get-WinMintSetupShellDisplayName {
    param([string]$Id)

    if ([string]::IsNullOrWhiteSpace($Id)) { return '' }
    $raw = [string]$Id
    # Common package ids → friendly names
    $map = @{
        cursor = 'Cursor'
        zen = 'Zen'
        neovim = 'Neovim'
        vscode = 'VS Code'
        windhawk = 'Windhawk'
        yasb = 'YASB'
        thide = 'thide'
        komorebi = 'Komorebi'
        nilesoft = 'Nilesoft Shell'
        mingit = 'MinGit'
        starship = 'Starship'
        firefox = 'Firefox'
        chrome = 'Chrome'
        edge = 'Edge'
        fedora = 'Fedora'
        ubuntu = 'Ubuntu'
        debian = 'Debian'
    }
    $key = $raw.Trim().ToLowerInvariant()
    if ($map.ContainsKey($key)) { return [string]$map[$key] }
    if ($raw -match '^[a-z0-9]+$') {
        return $raw.Substring(0, 1).ToUpperInvariant() + $raw.Substring(1)
    }
    return $raw
}

function Get-WinMintSetupShellAppsItemPlan {
    param($AgentProfile)

    $items = [System.Collections.Generic.List[string]]::new()
    if (-not $AgentProfile) { return @() }

    foreach ($editor in @($AgentProfile.editors)) {
        $name = Get-WinMintSetupShellDisplayName -Id ([string]$editor)
        if ($name) { $items.Add($name) | Out-Null }
    }
    foreach ($browser in @($AgentProfile.browsers)) {
        $name = Get-WinMintSetupShellDisplayName -Id ([string]$browser)
        if ($name) { $items.Add($name) | Out-Null }
    }
    if (Test-WinMintSetupShellModuleEnabled -AgentProfile $AgentProfile -Enablement 'modules.windhawk.enabled') {
        $items.Add('Windhawk') | Out-Null
    }
    if (Test-WinMintSetupShellModuleEnabled -AgentProfile $AgentProfile -Enablement 'modules.shell.enabled') {
        $shell = $AgentProfile.modules.shell
        if ($shell) {
            foreach ($prop in $shell.PSObject.Properties) {
                if ($prop.Name -eq 'enabled') { continue }
                if ($prop.Value -is [bool] -and $prop.Value) {
                    $items.Add((Get-WinMintSetupShellDisplayName -Id $prop.Name)) | Out-Null
                }
            }
        }
    }
    if (Test-WinMintSetupShellModuleEnabled -AgentProfile $AgentProfile -Enablement 'modules.phoneLink.enabled') {
        $items.Add('Phone Link') | Out-Null
    }
    return @($items)
}

function Get-WinMintSetupShellWslItemPlan {
    param($AgentProfile)

    $items = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-WinMintSetupShellWslStageVisible -AgentProfile $AgentProfile)) { return @() }
    if ($AgentProfile.modules -and $AgentProfile.modules.PSObject.Properties['wsl']) {
        $wsl = $AgentProfile.modules.wsl
        if ($wsl.PSObject.Properties['distros']) {
            foreach ($distro in @($wsl.distros)) {
                $name = Get-WinMintSetupShellDisplayName -Id ([string]$distro)
                if ($name) { $items.Add($name) | Out-Null }
            }
        }
    }
    if ($items.Count -eq 0) { $items.Add('WSL') | Out-Null }
    return @($items)
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

function Test-WinMintSetupShellGenericCommandMessage {
    param([string]$Message)
    if ([string]::IsNullOrWhiteSpace($Message)) { return $true }
    return [bool]($Message -match '(?i)^Running\s+[\w.-]+\.(exe|cmd|bat|ps1)\.?\s*$')
}

function Format-WinMintSetupShellSplashDetail {
    param([Parameter(Mandatory)][string]$Text, [int]$MaxLength = 72)

    $trimmed = $Text.Trim()
    $trimmed = $trimmed -replace '(?i)\s+with\s+winget\b', ''
    $trimmed = $trimmed -replace '(?i)\s+with\s+Scoop\b', ''
    $trimmed = $trimmed -replace '(?i)\s+from\s+Microsoft\s+Store\b', ''
    $trimmed = $trimmed -replace '(?i)\s+via\s+Scoop\b', ''
    $trimmed = $trimmed -replace '(?i)\s+via\s+winget\b', ''
    $trimmed = $trimmed -replace '(?i)\s+\(arm64\)', ''
    $trimmed = $trimmed -replace '(?i)\s+\(x64\)', ''
    $trimmed = $trimmed -replace '(?i)\s+for\s+arm64\b', ''
    $trimmed = $trimmed -replace '(?i)\s+for\s+x64\b', ''
    $trimmed = $trimmed -replace '\s{2,}', ' '
    $trimmed = $trimmed.Trim().TrimEnd('.')
    if ($trimmed -match '(?i)^Installing\s+(.+)$') {
        $name = Get-WinMintSetupShellDisplayName -Id $Matches[1].Trim()
        $trimmed = "Installing $name"
    }
    elseif ($trimmed -match '(?i)^Downloading\s+(.+)$') {
        $name = Get-WinMintSetupShellDisplayName -Id $Matches[1].Trim()
        $trimmed = "Downloading $name"
    }
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
            return (Format-WinMintSetupShellSplashDetail -Text $message)
        }
    }
    return ''
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

function Test-WinMintSetupShellModuleDone {
    param(
        $AgentState,
        [string]$RuntimeStepName
    )

    if (-not $AgentState -or -not $AgentState.PSObject.Properties['steps']) { return $false }
    $key = "module:$RuntimeStepName"
    if (-not $AgentState.steps.PSObject.Properties[$key]) { return $false }
    $status = [string]$AgentState.steps.PSObject.Properties[$key].Value.status
    return $status -in @('ok', 'skipped')
}

function Resolve-WinMintSetupShellCurrentStageId {
    param(
        [string]$Phase,
        [string]$PreAgentStage,
        $Progress,
        $AgentProfile
    )

    if ($Phase -in @('finishing', 'complete', 'failed', 'reboot')) { return 'finish' }
    if ($PreAgentStage -in @('', 'locked', 'region', 'defaults')) { return 'ready' }

    if ($Progress.CurrentRuntimeStep) {
        $mapped = Resolve-WinMintSetupShellStageIdForRuntimeStep -RuntimeStepName $Progress.CurrentRuntimeStep
        if ($mapped -eq 'wsl' -and -not (Test-WinMintSetupShellWslStageVisible -AgentProfile $AgentProfile)) {
            return 'finish'
        }
        if ($mapped -eq 'apps' -and -not (Test-WinMintSetupShellAppsStageVisible -AgentProfile $AgentProfile)) {
            return 'ready'
        }
        return $mapped
    }

    if ($Progress.CompletedCount -gt 0) {
        if (Test-WinMintSetupShellAppsStageVisible -AgentProfile $AgentProfile) { return 'apps' }
        if (Test-WinMintSetupShellWslStageVisible -AgentProfile $AgentProfile) { return 'wsl' }
        return 'finish'
    }

    return 'ready'
}

function Resolve-WinMintSetupShellItemProgress {
    param(
        [string]$StageId,
        [string]$DetailLabel,
        $AgentProfile,
        $AgentState,
        $Progress
    )

    $plan = @()
    if ($StageId -eq 'apps') {
        $plan = @(Get-WinMintSetupShellAppsItemPlan -AgentProfile $AgentProfile)
    }
    elseif ($StageId -eq 'wsl') {
        $plan = @(Get-WinMintSetupShellWslItemPlan -AgentProfile $AgentProfile)
    }
    else {
        return @{ ItemIndex = 0; ItemTotal = 0 }
    }

    $total = @($plan).Count
    if ($total -le 0) { return @{ ItemIndex = 0; ItemTotal = 0 } }

    $index = 0
    if (-not [string]::IsNullOrWhiteSpace($DetailLabel)) {
        for ($i = 0; $i -lt $total; $i++) {
            if ($DetailLabel -match [regex]::Escape([string]$plan[$i])) {
                $index = $i + 1
                break
            }
        }
    }

    if ($index -eq 0) {
        # Estimate from completed apps-stage modules as a coarse fallback.
        $moduleSteps = if ($StageId -eq 'apps') {
            @('editors', 'browsers', 'windhawk', 'desktop-environment', 'phone-link')
        }
        else { @('wsl') }

        $doneModules = 0
        $enabledModules = 0
        foreach ($step in $moduleSteps) {
            $entry = Get-WinMintSetupShellCatalogEntry -RuntimeStepName $step
            if (-not $entry) { continue }
            if (-not (Test-WinMintSetupShellModuleEnabled -AgentProfile $AgentProfile -Enablement ([string]$entry.Enablement))) { continue }
            $enabledModules++
            if ($AgentState -and (Test-WinMintSetupShellModuleDone -AgentState $AgentState -RuntimeStepName $step)) {
                $doneModules++
            }
            elseif ($Progress.CurrentRuntimeStep -eq $step) {
                # current module counts as in-progress at least item 1
                if ($index -eq 0) { $index = [Math]::Max(1, [int][Math]::Ceiling(($doneModules / [Math]::Max(1, $enabledModules)) * $total)) }
            }
        }
        if ($index -eq 0 -and $enabledModules -gt 0) {
            $index = [Math]::Min($total, [Math]::Max(1, [int][Math]::Round(($doneModules / $enabledModules) * $total)))
            if ($Progress.CurrentRuntimeStep -and (Resolve-WinMintSetupShellStageIdForRuntimeStep -RuntimeStepName $Progress.CurrentRuntimeStep) -eq $StageId) {
                if ($doneModules -lt $enabledModules -and $index -lt $total) { $index = [Math]::Max($index, 1) }
            }
        }
    }

    if ($index -lt 1) { $index = 1 }
    if ($index -gt $total) { $index = $total }
    return @{ ItemIndex = $index; ItemTotal = $total }
}

function Get-WinMintSetupShellStageProgress {
    param(
        [string]$Phase,
        [string]$StageId,
        [int]$ItemIndex,
        [int]$ItemTotal,
        $AgentProfile,
        [string]$DetailLabel
    )

    if ($Phase -eq 'complete') {
        return @{ progressPct = 100.0; progressMode = 'determinate' }
    }
    if ($Phase -in @('failed', 'reboot')) {
        return @{ progressPct = 0.0; progressMode = 'indeterminate' }
    }

    $visible = @(Get-WinMintSetupShellVisibleStages -AgentProfile $AgentProfile)
    $weightSum = 0.0
    foreach ($s in $visible) { $weightSum += [double]$s.Weight }
    if ($weightSum -le 0) { $weightSum = 1.0 }

    $completedWeight = 0.0
    $currentWeight = 0.0
    $foundCurrent = $false
    foreach ($s in $visible) {
        $id = [string]$s.Id
        $w = [double]$s.Weight / $weightSum
        if ($id -eq $StageId) {
            $currentWeight = $w
            $foundCurrent = $true
            break
        }
        $completedWeight += $w
    }
    if (-not $foundCurrent) {
        return @{ progressPct = ($completedWeight * 100.0); progressMode = 'indeterminate' }
    }

    if ($StageId -in @('ready', 'finish') -or $Phase -eq 'finishing') {
        if ($Phase -eq 'finishing') {
            return @{ progressPct = [Math]::Round(($completedWeight + $currentWeight * 0.5) * 100.0, 2); progressMode = 'indeterminate' }
        }
        return @{ progressPct = 0.0; progressMode = 'indeterminate' }
    }

    # Long current item: keep i of n but use indeterminate fill so the bar does not freeze.
    $longItem = $false
    if ($ItemTotal -gt 0 -and -not [string]::IsNullOrWhiteSpace($DetailLabel)) {
        if ($DetailLabel -match '(?i)^(Installing|Downloading)\s+') { $longItem = $true }
    }

    $itemFraction = if ($ItemTotal -gt 0) {
        [Math]::Min(1.0, [Math]::Max(0.0, ($ItemIndex - 0.5) / [double]$ItemTotal))
    }
    else { 0.5 }

    $pct = ($completedWeight + ($currentWeight * $itemFraction)) * 100.0
    if ($longItem) {
        return @{ progressPct = [Math]::Round($pct, 2); progressMode = 'indeterminate' }
    }
    return @{ progressPct = [Math]::Round($pct, 2); progressMode = 'determinate' }
}

function Get-WinMintSetupShellRuntimeTaskLabel {
    param(
        [string]$RuntimeStepName,
        $AgentProfile,
        [string]$ProfileDisplayName
    )

    $entry = Get-WinMintSetupShellCatalogEntry -RuntimeStepName $RuntimeStepName
    if (-not $entry) { return $RuntimeStepName }
    if ($entry.PSObject.Properties['ShellLabel'] -and $entry.ShellLabel) {
        return [string]$entry.ShellLabel
    }
    return [string]$entry.Title
}

function Resolve-WinMintSetupShellStageCopy {
    param(
        [string]$Phase,
        [string]$StageId,
        [string]$PreAgentStage,
        $Progress,
        $AgentState,
        $AgentProfile,
        $Control
    )

    $taskLabel = Get-WinMintSetupShellStageLabel -StageId $StageId
    $detailLabel = ''
    $banner = ''
    $bannerKind = ''

    if ($Phase -eq 'complete') {
        return @{
            TaskLabel = "You're all set"
            DetailLabel = ''
            Banner = ''
            BannerKind = ''
            StageId = 'finish'
        }
    }
    if ($Phase -eq 'reboot' -or $Progress.NeedsReboot) {
        return @{
            TaskLabel = 'Restart required'
            DetailLabel = 'Setup will continue after restart'
            Banner = 'Setup will continue after restart'
            BannerKind = 'warn'
            StageId = 'finish'
        }
    }
    if ($Phase -eq 'failed' -or $Progress.RunStatus -eq 'failed') {
        $failDetail = 'Your desktop will unlock. You can continue and retry later.'
        if ($Progress.CurrentRuntimeStep) {
            $failDetail = "A setup step didn’t finish. Your desktop will unlock."
        }
        return @{
            TaskLabel = 'Something went wrong'
            DetailLabel = $failDetail
            Banner = $failDetail
            BannerKind = 'fail'
            StageId = 'finish'
        }
    }
    if ($Phase -eq 'finishing') {
        return @{
            TaskLabel = 'Finishing up'
            DetailLabel = 'Almost done'
            Banner = ''
            BannerKind = ''
            StageId = 'finish'
        }
    }

    if ($StageId -eq 'ready') {
        $detailLabel = if ($PreAgentStage -in @('locked', 'region', 'defaults', '')) {
            'This may take a few minutes'
        }
        else {
            $live = Get-WinMintSetupShellLiveTaskHint -AgentState $AgentState
            if ($live) { $live } else { 'This may take a few minutes' }
        }
    }
    elseif ($StageId -eq 'apps') {
        $live = Get-WinMintSetupShellLiveTaskHint -AgentState $AgentState
        if ($live) {
            $detailLabel = $live
        }
        else {
            $plan = @(Get-WinMintSetupShellAppsItemPlan -AgentProfile $AgentProfile)
            if ($plan.Count -gt 0) { $detailLabel = "Installing $($plan[0])" }
        }
    }
    elseif ($StageId -eq 'wsl') {
        $live = Get-WinMintSetupShellLiveTaskHint -AgentState $AgentState
        if ($live) {
            $detailLabel = $live
        }
        else {
            $plan = @(Get-WinMintSetupShellWslItemPlan -AgentProfile $AgentProfile)
            if ($plan.Count -eq 1 -and $plan[0] -eq 'WSL') {
                $detailLabel = 'Setting up WSL'
            }
            elseif ($plan.Count -gt 0) {
                $detailLabel = "Installing $($plan[0])"
            }
            else {
                $detailLabel = 'Setting up WSL'
            }
        }
    }
    elseif ($StageId -eq 'finish') {
        $detailLabel = 'Pinning apps'
    }

    if ($Control -and $Control.PSObject.Properties['message'] -and -not [string]::IsNullOrWhiteSpace([string]$Control.message)) {
        if ($Phase -in @('finishing', 'complete') -and -not $banner) {
            $banner = [string]$Control.message
            $bannerKind = 'warn'
        }
    }

    return @{
        TaskLabel = $taskLabel
        DetailLabel = $detailLabel
        Banner = $banner
        BannerKind = $bannerKind
        StageId = $StageId
    }
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
    $stageId = Resolve-WinMintSetupShellCurrentStageId `
        -Phase $phase `
        -PreAgentStage $preAgentStage `
        -Progress $progress `
        -AgentProfile $AgentProfile

    # Prefer runtime-step mapping when agent is active.
    if ($phase -eq 'running' -and $preAgentStage -eq 'agent' -and $progress.CurrentRuntimeStep) {
        $mapped = Resolve-WinMintSetupShellStageIdForRuntimeStep -RuntimeStepName $progress.CurrentRuntimeStep
        if ($mapped -eq 'wsl' -and -not (Test-WinMintSetupShellWslStageVisible -AgentProfile $AgentProfile)) {
            $stageId = 'finish'
        }
        elseif ($mapped -eq 'apps' -and -not (Test-WinMintSetupShellAppsStageVisible -AgentProfile $AgentProfile)) {
            $stageId = 'ready'
        }
        else {
            $stageId = $mapped
        }
    }

    $copy = Resolve-WinMintSetupShellStageCopy `
        -Phase $phase `
        -StageId $stageId `
        -PreAgentStage $preAgentStage `
        -Progress $progress `
        -AgentState $AgentState `
        -AgentProfile $AgentProfile `
        -Control $Control

    $stageId = [string]$copy.StageId
    $itemProgress = Resolve-WinMintSetupShellItemProgress `
        -StageId $stageId `
        -DetailLabel ([string]$copy.DetailLabel) `
        -AgentProfile $AgentProfile `
        -AgentState $AgentState `
        -Progress $progress

    $pipeline = Get-WinMintSetupShellStageProgress `
        -Phase $phase `
        -StageId $stageId `
        -ItemIndex ([int]$itemProgress.ItemIndex) `
        -ItemTotal ([int]$itemProgress.ItemTotal) `
        -AgentProfile $AgentProfile `
        -DetailLabel ([string]$copy.DetailLabel)

    return [ordered]@{
        phase = $phase
        stageId = $stageId
        taskLabel = [string]$copy.TaskLabel
        detailLabel = [string]$copy.DetailLabel
        itemIndex = [int]$itemProgress.ItemIndex
        itemTotal = [int]$itemProgress.ItemTotal
        progressPct = [double]$pipeline.progressPct
        progressMode = [string]$pipeline.progressMode
        profileName = $profileName
        elapsedMs = Get-WinMintSetupShellElapsedMs -Control $Control
        groupLabel = ''
        banner = [string]$copy.Banner
        bannerKind = [string]$copy.BannerKind
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

# Compatibility aliases referenced by older contract smoke checks / callers.
function Get-WinMintSetupShellGroupLabel {
    param([string]$GroupId)
    # Map legacy group ids onto stage labels where possible.
    switch ($GroupId) {
        'prepare' { return (Get-WinMintSetupShellStageLabel -StageId 'ready') }
        'region' { return (Get-WinMintSetupShellStageLabel -StageId 'ready') }
        'tools' { return (Get-WinMintSetupShellStageLabel -StageId 'apps') }
        'dev' { return (Get-WinMintSetupShellStageLabel -StageId 'apps') }
        'desktop' { return (Get-WinMintSetupShellStageLabel -StageId 'apps') }
        'finish' { return (Get-WinMintSetupShellStageLabel -StageId 'finish') }
        default { return (Get-WinMintSetupShellStageLabel -StageId 'ready') }
    }
}

function Resolve-WinMintSetupShellCurrentGroupId {
    param(
        [string]$Phase,
        [string]$PreAgentStage,
        $Progress
    )
    return (Resolve-WinMintSetupShellCurrentStageId -Phase $Phase -PreAgentStage $PreAgentStage -Progress $Progress -AgentProfile $null)
}

function Get-WinMintSetupShellGroupDefinitions {
    Get-WinMintSetupShellStageDefinitions
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
        'finishing' { return (Get-WinMintSetupShellStageLabel -StageId 'finish') }
        'complete' { return "You're all set" }
        'reboot' { return 'Restart required' }
        'failed' { return 'Something went wrong' }
    }
    $stage = Resolve-WinMintSetupShellStageIdForRuntimeStep -RuntimeStepName $RuntimeStepName
    return (Get-WinMintSetupShellStageLabel -StageId $stage)
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

    $stageId = Resolve-WinMintSetupShellCurrentStageId -Phase $Phase -PreAgentStage $PreAgentStage -Progress $Progress -AgentProfile $AgentProfile
    $copy = Resolve-WinMintSetupShellStageCopy -Phase $Phase -StageId $stageId -PreAgentStage $PreAgentStage -Progress $Progress -AgentState $null -AgentProfile $AgentProfile -Control $Control
    return @{
        CurrentLabel = $copy.TaskLabel
        Banner = $copy.Banner
        BannerKind = $copy.BannerKind
    }
}

function Get-WinMintSetupShellPipelineProgress {
    param(
        [string]$Phase,
        [string]$PreAgentStage,
        $Progress
    )

    $stageId = Resolve-WinMintSetupShellCurrentStageId -Phase $Phase -PreAgentStage $PreAgentStage -Progress $Progress -AgentProfile $null
    return (Get-WinMintSetupShellStageProgress -Phase $Phase -StageId $stageId -ItemIndex 0 -ItemTotal 0 -AgentProfile $null -DetailLabel '')
}

function Resolve-WinMintSetupShellRuntimeGroupId {
    param([Parameter(Mandatory)][string]$RuntimeStepName)
    return (Resolve-WinMintSetupShellStageIdForRuntimeStep -RuntimeStepName $RuntimeStepName)
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

    $live = Get-WinMintSetupShellLiveTaskHint -AgentState $AgentState
    if (-not [string]::IsNullOrWhiteSpace($live)) { return $live }
    if (-not [string]::IsNullOrWhiteSpace($FallbackLabel)) { return (Format-WinMintSetupShellSplashDetail -Text $FallbackLabel) }
    return (Get-WinMintSetupShellDevlogTask -RuntimeStepName $RuntimeStepName -Phase $Phase -FallbackLabel $FallbackLabel -ProfileDisplayName $ProfileDisplayName -AgentProfile $AgentProfile)
}
