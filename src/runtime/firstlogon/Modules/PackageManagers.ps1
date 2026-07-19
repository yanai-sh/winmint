#Requires -Version 7.6

function Get-WinMintAgentStarshipConfigPath {
    $configRoot = if (-not [string]::IsNullOrWhiteSpace([string]$env:XDG_CONFIG_HOME)) {
        [Environment]::ExpandEnvironmentVariables([string]$env:XDG_CONFIG_HOME)
    }
    else {
        Join-Path $env:USERPROFILE '.config'
    }
    return (Join-Path $configRoot 'starship.toml')
}

function Get-WinMintAgentPowerShellProfilePath {
    try {
        if ($PROFILE -and $PROFILE.PSObject.Properties['CurrentUserAllHosts'] -and
            -not [string]::IsNullOrWhiteSpace([string]$PROFILE.CurrentUserAllHosts)) {
            return [string]$PROFILE.CurrentUserAllHosts
        }
    }
    catch {
        Write-AgentLog "PowerShell profile path probe warning: $($_.Exception.Message)"
    }
    return (Join-Path $env:USERPROFILE 'Documents\PowerShell\profile.ps1')
}

function Invoke-WinMintAgentManifestToolSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SelectionId,
        [Parameter(Mandatory)][string[]]$SelectedIds,
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][string]$StateKeyPrefix,
        [string[]]$ExcludedIds = @()
    )

    $selected = @($SelectedIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $excluded = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($excludedId in @($ExcludedIds)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$excludedId)) {
            $excluded.Add([string]$excludedId) | Out-Null
        }
    }
    $installIds = @($selected | Where-Object { -not $excluded.Contains([string]$_) })

    $manifest = (Get-WinMintAgentContext).Manifest
    if (-not $manifest -or -not $manifest.PSObject.Properties['tools']) {
        return [pscustomobject]@{
            Id          = $SelectionId
            Status      = 'failed'
            SelectedIds = $selected
            InstallIds  = $installIds
            ExcludedIds = @($selected | Where-Object { $excluded.Contains([string]$_) })
            UnknownIds  = @()
            FailedIds   = @($installIds)
            ToolResults = @()
            Message     = 'packages.json does not contain a tools manifest.'
        }
    }

    $unknownIds = [System.Collections.Generic.List[string]]::new()
    $failedIds = [System.Collections.Generic.List[string]]::new()
    $toolResults = [System.Collections.Generic.List[object]]::new()

    foreach ($requestedId in $installIds) {
        $property = $manifest.tools.PSObject.Properties[$requestedId]
        $tool = if ($property) { $property.Value } else { $null }
        if (-not $tool) {
            $stateKey = "${StateKeyPrefix}:$requestedId"
            $State.steps[$stateKey] = @{
                status = 'failed'
                updatedAt = (Get-Date -Format o)
                error = "Unknown $StateKeyPrefix id: $requestedId"
            }
            Write-AgentLog "Unknown $StateKeyPrefix id in profile: $requestedId"
            Save-AgentState -State $State
            $unknownIds.Add($requestedId) | Out-Null
            $failedIds.Add($requestedId) | Out-Null
            $toolResults.Add([pscustomobject]@{
                RequestedId = $requestedId
                StateKey = $stateKey
                Status = 'failed'
                Error = "Unknown $StateKeyPrefix id: $requestedId"
            }) | Out-Null
            continue
        }

        Install-AgentTool -Tool $tool -State $State
        Save-AgentState -State $State

        $stateKey = "tool:$([string]$tool.id)"
        $status = if ($State.steps.ContainsKey($stateKey)) { [string]$State.steps[$stateKey].status } else { '' }
        $source = if ($tool.PSObject.Properties['source']) { [string]$tool.source } else { '' }
        $toolResults.Add([pscustomobject]@{
            RequestedId = $requestedId
            ToolId = [string]$tool.id
            Source = $source
            StateKey = $stateKey
            Status = $status
        }) | Out-Null
        if ($status -ne 'ok' -and $status -ne 'skipped') {
            $failedIds.Add($requestedId) | Out-Null
        }
    }

    $status = if ($failedIds.Count -gt 0) { 'failed' } else { 'ok' }
    [pscustomobject]@{
        Id          = $SelectionId
        Status      = $status
        SelectedIds = $selected
        InstallIds  = $installIds
        ExcludedIds = @($selected | Where-Object { $excluded.Contains([string]$_) })
        UnknownIds  = $unknownIds.ToArray()
        FailedIds   = $failedIds.ToArray()
        ToolResults = $toolResults.ToArray()
        Message     = if ($status -eq 'ok') { "$SelectionId installed." } else { "Failed ${SelectionId}: $($failedIds -join ', ')" }
    }
}

function Set-WinMintAgentStarshipPowerShellProfile {
    param([Parameter(Mandatory)][string]$ProfilePath)

    $profileDir = Split-Path -Parent $ProfilePath
    if (-not [string]::IsNullOrWhiteSpace($profileDir)) {
        $null = New-Item -ItemType Directory -Path $profileDir -Force
    }
    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
        Set-Content -LiteralPath $ProfilePath -Value '' -Encoding UTF8
    }

    $profileText = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8
    if ($profileText -match 'starship\s+init\s+powershell') {
        return
    }

    $block = @'

# WinMint Starship prompt begin
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}
# WinMint Starship prompt end
'@
    Add-Content -LiteralPath $ProfilePath -Value $block -Encoding UTF8
}

function Install-WinMintAgentStarshipPrompt {
    param([Parameter(Mandatory)][hashtable]$State)

    $key = 'shell:starship'
    if (-not (Get-WinMintAgentContext).Force -and $State.steps.ContainsKey($key) -and [string]$State.steps[$key].status -eq 'ok') {
        Write-AgentUserNotice -Level OK -Message 'Starship prompt already configured.'
        return
    }

    try {
        Install-AgentManifestTool -ToolId 'starship' -State $State
        Update-AgentProcessPath
        $starship = Get-Command starship -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $starship) { throw 'starship command not available after install.' }

        $configPath = Get-WinMintAgentStarshipConfigPath
        $configDir = Split-Path -Parent $configPath
        if (-not [string]::IsNullOrWhiteSpace($configDir)) {
            $null = New-Item -ItemType Directory -Path $configDir -Force
        }

        if ((Get-WinMintAgentContext).Force -or -not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
            Invoke-AgentNative -FilePath $starship.Source -ArgumentList @('preset', 'nerd-font-symbols', '-o', $configPath)
        }
        else {
            Write-AgentLog "Starship config already exists; leaving user config in place: $configPath"
        }

        $profilePath = Get-WinMintAgentPowerShellProfilePath
        Set-WinMintAgentStarshipPowerShellProfile -ProfilePath $profilePath
        $State.steps[$key] = @{
            status = 'ok'
            updatedAt = (Get-Date -Format o)
            preset = 'nerd-font-symbols'
            configPath = $configPath
            powerShellProfile = $profilePath
            terminalFont = 'Cascadia Code NF'
        }
        Save-AgentState -State $State
        Write-AgentUserNotice -Level OK -Message 'Starship prompt configured.'
    }
    catch {
        $State.steps[$key] = @{
            status = 'failed'
            updatedAt = (Get-Date -Format o)
            preset = 'nerd-font-symbols'
            error = $_.Exception.Message
        }
        Save-AgentState -State $State
        throw
    }
}

# ponytail: partial --all failure ceiling — UPDATE_ALL_HAS_FAILURE is incomplete (failed+partial), not clean ok.
$script:WinMintWingetPartialUpgradeExitCode = -1978335188
$script:WinMintWingetNoUpgradeExitCode = -1978335189
$script:WinMintWingetBootstrapPackageIds = @(
    'Microsoft.AppInstaller'
    'Microsoft.EdgeWebView2Runtime'
    'Microsoft.WindowsTerminal'
)
$script:WinMintWingetMachineScopePackageIds = @(
    'Microsoft.EdgeWebView2Runtime'
    'Microsoft.WindowsTerminal'
)

function Get-WinMintAgentWingetUpgradeArgumentList {
    param(
        [Parameter(Mandatory)][string[]]$Tail,
        [switch]$MachineScope
    )

    $args = @(
        'upgrade'
    ) + $Tail + @(
        '--silent'
        '--disable-interactivity'
        '--accept-source-agreements'
        '--accept-package-agreements'
    )
    if ($MachineScope) {
        $args += @('--scope', 'machine')
    }
    return $args
}

function Get-WinMintAgentWingetBootstrapStateKey {
    param([Parameter(Mandatory)][string]$PackageId)

    $suffix = ($PackageId -replace '[^A-Za-z0-9]+', '-').Trim('-')
    return "package-manager:winget-bootstrap:$suffix"
}

function Test-WinMintAgentWingetPartialUpgradeFailure {
    param([Parameter(Mandatory)][string]$ErrorText)

    return ($ErrorText -match 'exited\s+-1978335188\b' -or $ErrorText -match '0x8A15002C')
}

function Test-WinMintAgentWingetNoUpgradeAvailable {
    param([Parameter(Mandatory)][string]$ErrorText)

    return ($ErrorText -match 'exited\s+-1978335189\b' -or $ErrorText -match '0x8A15002D' -or $ErrorText -match 'No available upgrade found')
}

function Test-WinMintAgentWingetUsesMachineScope {
    param([Parameter(Mandatory)][string]$PackageId)

    return ($script:WinMintWingetMachineScopePackageIds -contains $PackageId)
}

function Invoke-WinMintAgentWingetRepairAndSourceUpdate {
    param([Parameter(Mandatory)][hashtable]$State)

    $key = 'package-manager:winget-repair'
    if (-not (Get-WinMintAgentContext).Force -and $State.steps.ContainsKey($key) -and [string]$State.steps[$key].status -eq 'ok') {
        return
    }

    $State.steps[$key] = @{
        status    = 'running'
        startedAt = (Get-Date -Format o)
        updatedAt = (Get-Date -Format o)
        command   = 'Repair-WinGetPackageManager + winget source update'
    }
    Save-AgentState -State $State
    Write-AgentEvent -Type 'step' -Status 'running' -Step $key -Message 'Repairing winget package manager and refreshing sources.'

    $repairUsed = $false
    $repairError = $null
    try {
        if (Get-Command Repair-WinGetPackageManager -ErrorAction SilentlyContinue) {
            Repair-WinGetPackageManager -ErrorAction Stop
            $repairUsed = $true
        }
        else {
            Write-AgentLog 'Repair-WinGetPackageManager not available; continuing with winget source update.'
        }
    }
    catch {
        $repairError = $_.Exception.Message
        Write-AgentLog "Repair-WinGetPackageManager failed (non-blocking): $repairError"
    }

    $sourceError = $null
    try {
        $winget = Wait-WingetPath
        if (-not $winget) { throw 'winget.exe not available after wait.' }
        Invoke-AgentNative -FilePath $winget -ArgumentList @(
            'source', 'update',
            '--disable-interactivity'
        )
    }
    catch {
        $sourceError = $_.Exception.Message
        Write-AgentLog "winget source update failed (non-blocking): $sourceError"
    }

    $ok = [string]::IsNullOrWhiteSpace($sourceError)
    $State.steps[$key] = @{
        status      = if ($ok) { 'ok' } else { 'failed' }
        updatedAt   = (Get-Date -Format o)
        command     = 'Repair-WinGetPackageManager + winget source update'
        repairUsed  = $repairUsed
        repairError = $repairError
        sourceError = $sourceError
    }
    Save-AgentState -State $State
    if ($ok) {
        Write-AgentEvent -Type 'step' -Status 'ok' -Step $key -Message 'Winget repair/source update completed.'
    }
    else {
        Write-AgentEvent -Type 'step' -Status 'failed' -Step $key -Message "Winget source update failed: $sourceError" -Data @{
            error = $sourceError
        }
    }
}

function Invoke-WinMintAgentWingetBootstrapUpgrades {
    param([Parameter(Mandatory)][hashtable]$State)

    Invoke-WinMintAgentWingetRepairAndSourceUpdate -State $State

    $winget = Wait-WingetPath
    if (-not $winget) { throw 'winget.exe not available after wait.' }

    foreach ($packageId in @($script:WinMintWingetBootstrapPackageIds)) {
        $key = Get-WinMintAgentWingetBootstrapStateKey -PackageId $packageId
        if (-not (Get-WinMintAgentContext).Force -and $State.steps.ContainsKey($key) -and [string]$State.steps[$key].status -eq 'ok') {
            continue
        }

        $machineScope = Test-WinMintAgentWingetUsesMachineScope -PackageId $packageId
        $command = if ($machineScope) { "winget upgrade --id $packageId --scope machine" } else { "winget upgrade --id $packageId" }
        $State.steps[$key] = @{
            status = 'running'
            startedAt = (Get-Date -Format o)
            updatedAt = (Get-Date -Format o)
            command = $command
            packageId = $packageId
            machineScope = $machineScope
        }
        Save-AgentState -State $State
        Write-AgentEvent -Type 'step' -Status 'running' -Step $key -Message "Running $command."

        try {
            $tail = @('--id', $packageId)
            Invoke-AgentNative -FilePath $winget -ArgumentList @(Get-WinMintAgentWingetUpgradeArgumentList -Tail $tail -MachineScope:$machineScope)
            $State.steps[$key] = @{
                status = 'ok'
                updatedAt = (Get-Date -Format o)
                command = $command
                packageId = $packageId
                machineScope = $machineScope
            }
            Save-AgentState -State $State
            Write-AgentEvent -Type 'step' -Status 'ok' -Step $key -Message "$command completed."
        }
        catch {
            if (Test-WinMintAgentWingetNoUpgradeAvailable -ErrorText $_.Exception.Message) {
                $State.steps[$key] = @{
                    status = 'ok'
                    updatedAt = (Get-Date -Format o)
                    command = $command
                    packageId = $packageId
                    machineScope = $machineScope
                    reason = 'already-current'
                }
                Save-AgentState -State $State
                Write-AgentEvent -Type 'step' -Status 'ok' -Step $key -Message "$command already current."
                Write-AgentLog "$command already current (non-blocking): $($_.Exception.Message)"
                continue
            }
            $State.steps[$key] = @{
                status = 'failed'
                updatedAt = (Get-Date -Format o)
                command = $command
                packageId = $packageId
                machineScope = $machineScope
                error = $_.Exception.Message
            }
            Save-AgentState -State $State
            Write-AgentEvent -Type 'step' -Status 'failed' -Step $key -Message "$command failed: $($_.Exception.Message)" -Data @{
                error = $_.Exception.Message
            }
            Write-AgentLog "$command failed (non-blocking): $($_.Exception.Message)"
        }
    }

    Update-AgentProcessPath
}

function Invoke-WinMintAgentWingetCatchUpAll {
    param([Parameter(Mandatory)][hashtable]$State)

    $key = 'package-manager:winget-upgrade-all'
    if (-not (Get-WinMintAgentContext).Force -and $State.steps.ContainsKey($key) -and [string]$State.steps[$key].status -eq 'ok') {
        Write-AgentUserNotice -Level OK -Message 'winget store catch-up already completed.'
        return
    }

    $winget = Wait-WingetPath
    if (-not $winget) { throw 'winget.exe not available after wait.' }

    $command = 'winget upgrade --all'
    try {
        $State.steps[$key] = @{
            status = 'running'
            startedAt = (Get-Date -Format o)
            updatedAt = (Get-Date -Format o)
            command = $command
            phase = 'post-main'
        }
        Save-AgentState -State $State
        Write-AgentEvent -Type 'step' -Status 'running' -Step $key -Message 'Running winget upgrade --all after agent modules.'
        Invoke-AgentNative -FilePath $winget -ArgumentList @(Get-WinMintAgentWingetUpgradeArgumentList -Tail @('--all'))
        Update-AgentProcessPath
        $State.steps[$key] = @{
            status = 'ok'
            updatedAt = (Get-Date -Format o)
            command = $command
            phase = 'post-main'
        }
        Save-AgentState -State $State
        Write-AgentEvent -Type 'step' -Status 'ok' -Step $key -Message 'winget upgrade --all completed.'
    }
    catch {
        $errorText = [string]$_.Exception.Message
        $partial = Test-WinMintAgentWingetPartialUpgradeFailure -ErrorText $errorText
        $warning = if ($partial) {
            'Incomplete: winget upgrade --all reported UPDATE_ALL_HAS_FAILURE (0x8A15002C); some packages failed. Not clean success — retry later or reboot if WebView2/App Installer remain outdated.'
        }
        else { $null }
        # Partial bulk failure is incomplete/failed, never silent ok.
        $State.steps[$key] = @{
            status = 'failed'
            updatedAt = (Get-Date -Format o)
            command = $command
            phase = 'post-main'
            partialFailure = $partial
            incomplete = $partial
            error = $errorText
            warning = $warning
        }
        Save-AgentState -State $State
        Write-AgentEvent -Type 'step' -Status 'failed' -Step $key -Message $(if ($partial) { 'winget upgrade --all incomplete (partial package failures).' } else { "winget upgrade --all failed: $errorText" }) -Data @{
            error = $errorText
            partialFailure = $partial
            incomplete = $partial
            warning = $warning
        }
        Write-AgentLog $(if ($partial) { "winget upgrade --all incomplete (non-blocking): $errorText" } else { "winget upgrade --all failed (non-blocking): $errorText" })
    }
}

function Invoke-WinMintAgentPackageManagerBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    [void]$AgentProfile
    [void]$State
    $winget = Wait-WingetPath
    if (-not $winget) { throw 'winget.exe not available after wait.' }
    Invoke-WinMintAgentWingetBootstrapUpgrades -State $State
    Install-AgentScoop -State $State
    Install-AgentManifestTool -ToolId 'mingit' -State $State
    Install-WinMintAgentStarshipPrompt -State $State
    $mingitStateKey = Get-AgentManifestToolStateKey -ToolId 'mingit'
    $packageManagerStateSteps = @('package-manager:scoop', $mingitStateKey)
    $shellPromptStateSteps = @('shell:starship')

    [pscustomobject]@{
        Id                       = 'package-managers'
        Status                   = 'ok'
        Message                  = 'winget bootstrap ready; Scoop and MinGit installed; Starship prompt configured.'
        RequiredStateSteps       = @($packageManagerStateSteps + $shellPromptStateSteps)
        PackageManagerStateSteps = $packageManagerStateSteps
        ShellPromptStateSteps    = $shellPromptStateSteps
    }
}
