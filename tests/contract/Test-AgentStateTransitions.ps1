#Requires -Version 7.6
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)

    $failures.Add($Message) | Out-Null
    Write-Error $Message -ErrorAction Continue
}

function Assert-Equal {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
    )

    if ([string]$Actual -ne [string]$Expected) {
        Add-Failure "$Message Expected '$Expected', got '$Actual'."
    }
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) { Add-Failure $Message }
}

function Assert-Throws {
    param(
        [scriptblock]$ScriptBlock,
        [string]$ExpectedText,
        [string]$Message
    )

    try {
        & $ScriptBlock
        Add-Failure "$Message Expected an exception."
    }
    catch {
        if (-not [string]::IsNullOrWhiteSpace($ExpectedText)) {
            $actual = [string]$_.Exception.Message
            if ($actual -notlike "*$ExpectedText*") {
                Add-Failure "$Message Expected exception containing '$ExpectedText', got '$actual'."
            }
        }
    }
}

function New-TestAgentState {
    [ordered]@{
        version = 1
        steps = @{}
    }
}

function Set-TestAgentStep {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][string]$Key,
        [string]$Status = 'ok',
        [string]$Source = 'fixture',
        [string]$ErrorText = ''
    )

    $entry = @{
        status = $Status
        updatedAt = (Get-Date -Format o)
    }
    if (-not [string]::IsNullOrWhiteSpace($Source)) { $entry.source = $Source }
    if (-not [string]::IsNullOrWhiteSpace($ErrorText)) { $entry.error = $ErrorText }
    $State.steps[$Key] = $entry
}

function Write-AgentLog { param([string]$Message) [void]$Message }
function Write-AgentEvent {
    param(
        [string]$Type,
        [string]$Status,
        [string]$Step,
        [string]$Message,
        [hashtable]$Data = @{}
    )
    [void]$Type
    [void]$Status
    [void]$Step
    [void]$Message
    [void]$Data
}
function Write-AgentConsoleLine { param([string]$Level, [string]$Message) [void]$Level; [void]$Message }
function Write-AgentUserNotice { param([string]$Level, [string]$Message) [void]$Level; [void]$Message }

$script:agentRoot = Join-Path $root 'src\runtime\firstlogon'
. (Join-Path $agentRoot 'Agent.Load.ps1')
$script:WinMintAgentFastWaits = $true
$script:WinMintWingetPathOverride = 'winget.exe'
$script:WinMintScoopPathOverride = 'scoop.ps1'
function Install-AgentManifestTool {
    param([Parameter(Mandatory)][string]$ToolId, [Parameter(Mandatory)][hashtable]$State)
    $key = Get-AgentManifestToolStateKey -ToolId $ToolId
    Set-TestAgentStep -State $State -Key $key
}
. (Join-Path $root 'src\runtime\firstlogon\Modules\PackageManagers.ps1')
. (Join-Path $root 'src\runtime\firstlogon\Modules\LauncherKey.ps1')
. (Join-Path $root 'src\runtime\firstlogon\Modules\TilingDesktop.ps1')
. (Join-Path $root 'src\runtime\firstlogon\Modules\Windhawk.ps1')
function Get-WinMintAgentEverythingExePath { 'C:\WinMint\Test\Everything.exe' }

function Install-AgentTool {
    param($Tool, [hashtable]$State)

    $key = "tool:$($Tool.id)"
    $State.steps[$key] = @{
        status = 'ok'
        updatedAt = (Get-Date -Format o)
        source = [string]$Tool.source
    }
    Save-AgentState -State $State
}

$nativePreferredTool = [pscustomobject]@{
    architectures = @('amd64', 'arm64')
    wingetArchitectureByHost = [pscustomobject]@{
        arm64 = 'x86'
    }
}
Assert-Equal (Get-AgentToolWingetArchitecture -Tool $nativePreferredTool -HostArchitecture 'arm64' -TargetArchitecture 'arm64') 'arm64' 'Native ARM64 support must win over stale x86 overrides.'

$x64Tool = [pscustomobject]@{
    architectures = @('amd64', 'arm64')
}
Assert-Equal (Get-AgentToolWingetArchitecture -Tool $x64Tool -HostArchitecture 'amd64' -TargetArchitecture 'amd64') '' 'amd64 targets should use package-manager default architecture without a winget override.'
Assert-Equal (Get-AgentToolWingetArchitecture -Tool $x64Tool -HostArchitecture 'arm64' -TargetArchitecture 'arm64') 'arm64' 'ARM64 targets should request native arm64 winget packages when supported.'

function Invoke-TestAgentOkModule {
    param([object]$AgentProfile, [hashtable]$State)
    [void]$AgentProfile
    [void]$State
    [pscustomobject]@{ Status = 'ok'; Marker = 'ok-result' }
}

function Invoke-TestAgentRequiredOkModule {
    param([object]$AgentProfile, [hashtable]$State)
    [void]$AgentProfile
    Set-TestAgentStep -State $State -Key 'required:runtime-ok'
    [pscustomobject]@{ Status = 'ok'; RequiredStateSteps = @('required:runtime-ok'); Marker = 'required-ok-result' }
}

function Invoke-TestAgentMissingRequiredModule {
    param([object]$AgentProfile, [hashtable]$State)
    [void]$AgentProfile
    [void]$State
    [pscustomobject]@{ Status = 'ok'; RequiredStateSteps = @('required:runtime-missing'); Marker = 'required-missing-result' }
}

function Invoke-TestAgentSkippedRequiredModule {
    param([object]$AgentProfile, [hashtable]$State)
    [void]$AgentProfile
    [void]$State
    [pscustomobject]@{ Status = 'skipped'; RequiredStateSteps = @('required:runtime-missing'); Marker = 'required-skipped-result' }
}

function Invoke-TestAgentNeedsRebootModule {
    param([object]$AgentProfile, [hashtable]$State)
    [void]$AgentProfile
    [void]$State
    [pscustomobject]@{ Status = 'needsReboot'; Marker = 'reboot-result' }
}

function Invoke-TestAgentFailedModule {
    param([object]$AgentProfile, [hashtable]$State)
    [void]$AgentProfile
    [void]$State
    throw 'fixture failure'
}

function Invoke-TestLiveAuditFindingsModule {
    param([object]$AgentProfile, [hashtable]$State)
    [void]$AgentProfile
    [void]$State
    [pscustomobject]@{
        Status = 'ok'
        Summary = [pscustomobject]@{
            error = 2
            warning = 3
        }
    }
}

function Invoke-TestPostStepHook {
    param([object]$AgentProfile, [hashtable]$State)
    [void]$AgentProfile
    [void]$State
    $script:postStepHookCalls++
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('winmint-agent-state-test-' + [Guid]::NewGuid().ToString('n'))
try {
    $null = New-Item -ItemType Directory -Path $tempRoot -Force
    $script:statePath = Join-Path $tempRoot 'state.json'
    $testState = New-TestAgentState
    $testProfile = [pscustomobject]@{
        targetArchitecture = 'arm64'
        browsers = @('firefox')
        editors = @('neovim')
        modules = [pscustomobject]@{
            packageManagers = [pscustomobject]@{ enabled = $true }
            wsl = [pscustomobject]@{ enabled = $true }
            git = [pscustomobject]@{ enabled = $true }
            dotfiles = [pscustomobject]@{ enabled = $true }
            launcherKey = [pscustomobject]@{ enabled = $true; target = 'Search'; chord = 'Win+Shift+F23' }
            phoneLink = [pscustomobject]@{ enabled = $true }
            shell = [pscustomobject]@{ enabled = $true }
            windhawk = [pscustomobject]@{ enabled = $true }
            liveInstallAudit = [pscustomobject]@{ enabled = $true }
        }
    }
    $testContext = New-WinMintAgentContext @{
        AgentRoot = $agentRoot
        State = $testState
        StatePath = $script:statePath
        AgentProfile = $testProfile
        Manifest = $null
        Force = $false
        LogDir = $tempRoot
        EventLogPath = Join-Path $tempRoot 'events.jsonl'
        CommandLogDir = Join-Path $tempRoot 'commands'
        StateDir = $tempRoot
        TargetArchitecture = 'arm64'
        Interactive = $false
        EmitProgressJson = $false
    }
    Initialize-TestAgentContext -Context $testContext
    $script:State = $testState

    $runtimePlan = @(New-WinMintAgentRuntimeStepPlan)
    $moduleCatalog = @(Get-WinMintAgentModuleCatalog)
    $expectedStepOrder = @(
        'profiles',
        'package-managers',
        'wsl',
        'git',
        'dotfiles',
        'launcher-key',
        'phone-link',
        'desktop-environment',
        'windhawk',
        'browsers',
        'editors',
        'liveInstallAudit'
    )
    Assert-Equal (@($moduleCatalog | ForEach-Object { $_.Id }) -join ',') 'profiles,packageManagers,wsl,git,dotfiles,launcherKey,phoneLink,shell,windhawk,browsers,editors,liveInstallAudit' 'Agent module catalog should declare the explicit FirstLogon registration order.'
    Assert-Equal (@($moduleCatalog | ForEach-Object { $_.BootstrapFunction }) -join ',') 'Invoke-WinMintAgentProfileBootstrap,Invoke-WinMintAgentPackageManagerBootstrap,Invoke-WinMintAgentWslBootstrap,Invoke-WinMintAgentGitBootstrap,Invoke-WinMintAgentDotfileBootstrap,Invoke-WinMintAgentLauncherKeyBootstrap,Invoke-WinMintAgentPhoneLinkBootstrap,Invoke-WinMintAgentDesktopEnvironmentBootstrap,Invoke-WinMintAgentWindhawkBootstrap,Invoke-WinMintAgentBrowsersBootstrap,Invoke-WinMintAgentEditorBootstrap,Invoke-WinMintAgentLiveInstallAuditBootstrap' 'Agent module catalog should declare the required bootstrap functions explicitly.'
    Assert-Equal (@($runtimePlan | Sort-Object Order | ForEach-Object { $_.StepName }) -join ',') ($expectedStepOrder -join ',') 'Agent runtime step plan should preserve module order.'
    $profilesStep = $runtimePlan | Where-Object { $_.StepName -eq 'profiles' } | Select-Object -First 1
    $editorsStep = $runtimePlan | Where-Object { $_.StepName -eq 'editors' } | Select-Object -First 1
    $auditStep = $runtimePlan | Where-Object { $_.StepName -eq 'liveInstallAudit' } | Select-Object -First 1
    Assert-Equal $profilesStep.Id 'module:profiles' 'Agent runtime step ids should match state keys.'
    Assert-Equal $profilesStep.FailurePolicy 'blocking' 'Profile bootstrap should be the blocking FirstLogon step.'
    Assert-Equal $editorsStep.PostStepHook 'Set-WinMintAgentNeovimEnvironment' 'Editors should declare the Neovim environment post-step hook.'
    Assert-Equal $auditStep.Phase 'finalValidation' 'Live install audit should run during final validation.'
    Assert-Equal $auditStep.FailurePolicy 'advisory' 'Live install audit should remain advisory.'
    Assert-True ([bool]$runtimePlan[1].Enabled) 'Enabled module config should be reflected in the runtime plan.'
    $launcherKeyStep = $runtimePlan | Where-Object { $_.StepName -eq 'launcher-key' } | Select-Object -First 1
    Assert-Equal $launcherKeyStep.Enablement 'modules.launcherKey.enabled' 'Launcher key binding should be controlled by the launcherKey module.'

    Set-TestAgentStep -State $State -Key 'required:ok'
    Assert-WinMintAgentStateStepsOk -State $State -Keys @('required:ok') -Context 'test required steps'
    Assert-Throws -ScriptBlock {
        Assert-WinMintAgentStateStepsOk -State $State -Keys @('required:missing') -Context 'test required steps'
    } -ExpectedText 'missing: required:missing' -Message 'Required state validation should reject missing state keys.'
    Set-TestAgentStep -State $State -Key 'required:failed' -Status 'failed' -ErrorText 'fixture failure'
    Assert-Throws -ScriptBlock {
        Assert-WinMintAgentStateStepsOk -State $State -Keys @('required:failed') -Context 'test required steps'
    } -ExpectedText 'not ok: required:failed=fixture failure' -Message 'Required state validation should reject failed state keys.'

    $raycastKeyPlan = Get-WinMintAgentLauncherKeyPlan -AgentProfile (Get-WinMintAgentContext).AgentProfile
    Assert-Equal $raycastKeyPlan.Target 'Search' 'Launcher key plan should prefer explicit launcherKey target.'
    Assert-Equal $raycastKeyPlan.Chord 'Win+Shift+F23' 'Launcher key plan should preserve the common Copilot hardware-key chord.'

    $testContext.Manifest = [pscustomobject]@{
        tools = [pscustomobject]@{
            firefox = [pscustomobject]@{
                id = 'Mozilla.Firefox'
                source = 'winget'
            }
            neovim = [pscustomobject]@{
                id = 'neovim'
                source = 'scoop'
            }
            mingit = [pscustomobject]@{
                id = 'mingit'
                source = 'scoop'
            }
            raycast = [pscustomobject]@{
                id = '9PFXXSHC64H3'
                source = 'store'
            }
            yasb = [pscustomobject]@{
                id = 'AmN.yasb'
                source = 'winget'
            }
            nilesoft = [pscustomobject]@{
                id = 'Nilesoft.Shell'
                source = 'winget'
            }
            komorebi = [pscustomobject]@{
                id = 'LGUG2Z.komorebi'
                source = 'winget'
            }
            whkd = [pscustomobject]@{
                id = 'LGUG2Z.whkd'
                source = 'winget'
            }
        }
    }
    Set-WinMintAgentContext -Context $testContext

    Assert-Equal (Get-AgentManifestToolStateKey -ToolId 'mingit') 'tool:mingit' 'MinGit state keys should resolve from the package manifest.'
    Assert-Equal (Get-AgentManifestToolStateKey -ToolId 'raycast') 'tool:9PFXXSHC64H3' 'Raycast state keys should resolve from the package manifest.'
    Assert-Equal (Get-AgentManifestToolStateKey -ToolId 'yasb') 'tool:AmN.yasb' 'YASB state keys should resolve from the package manifest.'
    Assert-Equal (Get-AgentManifestToolStateKey -ToolId 'nilesoft') 'tool:Nilesoft.Shell' 'Nilesoft state keys should resolve from the package manifest.'
    Assert-Equal (Get-AgentManifestToolStateKey -ToolId 'komorebi') 'tool:LGUG2Z.komorebi' 'Komorebi state keys should resolve from the package manifest.'
    Assert-Equal (Get-AgentManifestToolStateKey -ToolId 'whkd') 'tool:LGUG2Z.whkd' 'whkd state keys should resolve from the package manifest.'

    $selection = Invoke-WinMintAgentManifestToolSelection -SelectionId 'browsers' -SelectedIds @('edge', 'firefox', 'missing-browser') -State $State -StateKeyPrefix 'browser' -ExcludedIds @('edge')
    Assert-Equal (@($selection.SelectedIds) -join ',') 'edge,firefox,missing-browser' 'Package selection should preserve selected ids.'
    Assert-Equal (@($selection.InstallIds) -join ',') 'firefox,missing-browser' 'Package selection should omit excluded ids from installs.'
    Assert-Equal (@($selection.ExcludedIds) -join ',') 'edge' 'Package selection should surface excluded ids.'
    Assert-Equal (@($selection.UnknownIds) -join ',') 'missing-browser' 'Package selection should surface unknown ids.'
    Assert-Equal $selection.ToolResults[0].Source 'winget' 'Package selection should expose package source ownership.'
    Assert-Equal $selection.ToolResults[0].StateKey 'tool:Mozilla.Firefox' 'Package selection should expose tool state key naming.'
    Assert-Equal $State.steps['browser:missing-browser'].status 'failed' 'Unknown selected package ids should write the domain state key.'

    function Wait-WingetPath { 'winget.exe' }
    function Invoke-WinMintAgentWingetBootstrapUpgrades {
        param([hashtable]$State)
        Set-TestAgentStep -State $State -Key 'package-manager:winget-bootstrap:AppInstaller'
    }
    function Install-AgentScoop {
        param([hashtable]$State)
        Set-TestAgentStep -State $State -Key 'package-manager:scoop'
    }
    function Install-WinMintAgentStarshipPrompt {
        param([hashtable]$State)
        Set-TestAgentStep -State $State -Key 'shell:starship'
    }
    $packageBootstrapState = New-TestAgentState
    $packageBootstrapResult = Invoke-WinMintAgentPackageManagerBootstrap -AgentProfile (Get-WinMintAgentContext).AgentProfile -State $packageBootstrapState
    Assert-Equal $packageBootstrapResult.Status 'ok' 'Package manager bootstrap should pass when package-manager and shell-prompt state keys are ok.'
    Assert-Equal (@($packageBootstrapResult.PackageManagerStateSteps) -join ',') 'package-manager:scoop,tool:mingit' 'Package manager readiness should require only Scoop and MinGit.'
    Assert-Equal (@($packageBootstrapResult.ShellPromptStateSteps) -join ',') 'shell:starship' 'Starship prompt setup should be reported as required shell-prompt state.'
    Assert-Equal (@($packageBootstrapResult.RequiredStateSteps) -join ',') 'package-manager:scoop,tool:mingit,shell:starship' 'Package manager bootstrap should report all runtime-enforced required state.'

    function Install-WinMintAgentStarshipPrompt {
        param([hashtable]$State)
        Set-TestAgentStep -State $State -Key 'shell:starship' -Status 'failed' -ErrorText 'visual prompt failed'
    }
    $failedPromptState = New-TestAgentState
    $failedPromptResult = Invoke-WinMintAgentPackageManagerBootstrap -AgentProfile (Get-WinMintAgentContext).AgentProfile -State $failedPromptState
    Assert-Equal $failedPromptResult.Status 'ok' 'Package manager module should return its result contract and leave readiness enforcement to the runtime.'
    Assert-Equal (@($failedPromptResult.PackageManagerStateSteps) -join ',') 'package-manager:scoop,tool:mingit' 'Starship failure should not move Starship into package-manager readiness.'

    function Start-WinMintRaycastApp {
        param([hashtable]$State)
        Set-TestAgentStep -State $State -Key 'config:raycast-start'
    }
    function Install-WinMintRaycastEverythingBackend {
        param(
            [object]$RaycastConfig,
            [hashtable]$State
        )
        [void]$RaycastConfig
        [void]$State
        return $false
    }
    $raycastProfile = [pscustomobject]@{
        modules = [pscustomobject]@{
            raycast = [pscustomobject]@{
                enabled = $true
                extensions = @()
            }
        }
    }
    $raycastState = New-TestAgentState
    $raycastResult = Invoke-WinMintAgentRaycastBootstrap -AgentProfile $raycastProfile -State $raycastState
    Assert-Equal $raycastResult.Status 'ok' 'Raycast bootstrap should pass when Raycast package state is ok.'
    Assert-Equal (@($raycastResult.RequiredStateSteps) -join ',') 'tool:9PFXXSHC64H3' 'Raycast readiness should require the Store package install state.'

    $launcherKeySearchProfile = [pscustomobject]@{
        modules = [pscustomobject]@{
            launcherKey = [pscustomobject]@{ enabled = $true; target = 'Search'; chord = 'Win+Shift+F23' }
            raycast = [pscustomobject]@{ enabled = $false }
        }
    }
    $launcherKeyState = New-TestAgentState
    $launcherKeyResult = Invoke-WinMintAgentLauncherKeyBootstrap -AgentProfile $launcherKeySearchProfile -State $launcherKeyState
    Assert-Equal $launcherKeyResult.Status 'ok' 'Launcher-key Search fallback should be an ok state.'
    Assert-Equal (@($launcherKeyResult.RequiredStateSteps) -join ',') 'config:launcher-key' 'Launcher-key readiness should require persisted launcher key config state.'
    Assert-Equal $launcherKeyState.steps['config:launcher-key'].status 'ok' 'Launcher-key bootstrap should persist config state.'

    function Install-WinMintYasbLayer {
        param([hashtable]$State)
        Set-TestAgentStep -State $State -Key 'tool:AmN.yasb'
    }
    function Install-WinMintThideLayer {
        param([hashtable]$State)
        Set-TestAgentStep -State $State -Key 'shell:thide'
    }
    function Install-WinMintNilesoftLayer {
        param([hashtable]$State)
        Set-TestAgentStep -State $State -Key 'tool:Nilesoft.Shell'
    }
    function Install-WinMintKomorebiLayer {
        param([hashtable]$State)
        Set-TestAgentStep -State $State -Key 'tool:LGUG2Z.komorebi'
        Set-TestAgentStep -State $State -Key 'tool:LGUG2Z.whkd'
    }
    $shellProfile = [pscustomobject]@{
        modules = [pscustomobject]@{
            shell = [pscustomobject]@{
                yasb = $true
                thide = $true
                nilesoft = $true
                komorebi = $true
                whkd = $true
            }
        }
    }
    $shellState = New-TestAgentState
    $shellResult = Invoke-WinMintAgentDesktopEnvironmentBootstrap -AgentProfile $shellProfile -State $shellState
    Assert-Equal $shellResult.Status 'ok' 'Desktop environment bootstrap should pass when selected layer state keys are ok.'
    Assert-Equal $shellResult.Id 'desktop-environment' 'Desktop environment bootstrap should use the product-facing step id.'
    Assert-Equal (@($shellResult.RequiredStateSteps) -join ',') 'tool:AmN.yasb,shell:thide,tool:Nilesoft.Shell,tool:LGUG2Z.komorebi,tool:LGUG2Z.whkd' 'Desktop environment readiness should report selected layer state keys.'

    function Install-WinMintNilesoftLayer {
        param([hashtable]$State)
        [void]$State
    }
    $missingShellState = New-TestAgentState
    $nilesoftOnlyProfile = [pscustomobject]@{
        modules = [pscustomobject]@{
            shell = [pscustomobject]@{
                yasb = $false
                thide = $false
                nilesoft = $true
                komorebi = $false
                whkd = $false
            }
        }
    }
    $missingShellResult = Invoke-WinMintAgentDesktopEnvironmentBootstrap -AgentProfile $nilesoftOnlyProfile -State $missingShellState
    Assert-Equal $missingShellResult.Status 'ok' 'Desktop environment module should return required state and leave enforcement to the runtime.'
    $previousState = $testContext.State
    $previousProfile = $testContext.AgentProfile
    $testContext.State = $missingShellState
    $testContext.AgentProfile = $nilesoftOnlyProfile
    Set-WinMintAgentContext -Context $testContext
    Invoke-AgentProfileModule -StepName 'desktop-environment' -FunctionName 'Invoke-WinMintAgentDesktopEnvironmentBootstrap' -Enabled $true
    Assert-Equal $testContext.State.steps['module:desktop-environment'].status 'failed' 'Missing selected desktop layer state should fail through runtime enforcement.'
    Assert-True ([string]$testContext.State.steps['module:desktop-environment'].error -like '*missing: tool:Nilesoft.Shell*') 'Runtime desktop environment failure should include the missing layer state key.'
    $testContext.State = $previousState
    $testContext.AgentProfile = $previousProfile
    Set-WinMintAgentContext -Context $testContext

    $script:windhawkWriteEvidence = $true
    $windhawkAssetDir = Join-Path $tempRoot 'AgentRoot\Assets\Windhawk'
    $windhawkInstallRoot = Join-Path $tempRoot 'WindhawkInstall'
    $null = New-Item -ItemType Directory -Path $windhawkAssetDir -Force
    $null = New-Item -ItemType Directory -Path $windhawkInstallRoot -Force
    Set-Content -LiteralPath (Join-Path $windhawkAssetDir 'WindhawkBootstrap.ps1') -Value '# fixture' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $windhawkAssetDir 'preset.json') -Value '{}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $windhawkInstallRoot 'windhawk.exe') -Value '' -Encoding UTF8
    $testContext.AgentRoot = Join-Path $tempRoot 'AgentRoot'
    Set-WinMintAgentContext -Context $testContext
    $script:WinMintWindhawkInstallRootOverride = $windhawkInstallRoot
    $script:windhawkNativeCalls = 0
    $script:WinMintAgentNativeHandler = {
        param([string]$FilePath, [string[]]$ArgumentList)
        [void]$FilePath
        $script:windhawkNativeCalls++
        if ($script:windhawkWriteEvidence -and @($ArgumentList) -contains '-EvidencePath') {
            $evidenceIndex = [array]::IndexOf([string[]]$ArgumentList, '-EvidencePath')
            $presetIndex = [array]::IndexOf([string[]]$ArgumentList, '-PresetFile')
            $installRootIndex = [array]::IndexOf([string[]]$ArgumentList, '-WindhawkInstallRoot')
            $evidencePath = $ArgumentList[$evidenceIndex + 1]
            $evidenceParent = Split-Path -Parent $evidencePath
            $null = New-Item -ItemType Directory -Path $evidenceParent -Force
            [ordered]@{
                status = 'ok'
                presetPath = $ArgumentList[$presetIndex + 1]
                installRoot = $ArgumentList[$installRootIndex + 1]
                timestamp = (Get-Date -Format o)
            } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
        }
    }
    $windhawkProfile = [pscustomobject]@{
        modules = [pscustomobject]@{
            windhawk = [pscustomobject]@{ enabled = $true }
        }
    }
    $windhawkState = New-TestAgentState
    $windhawkResult = Invoke-WinMintAgentWindhawkBootstrap -AgentProfile $windhawkProfile -State $windhawkState
    Assert-Equal $windhawkResult.Status 'ok' 'Windhawk bootstrap should pass when preset restore commands complete.'
    Assert-Equal (@($windhawkResult.RequiredStateSteps) -join ',') 'shell:windhawk-preset' 'Windhawk readiness should require preset application state.'
    Assert-Equal $windhawkState.steps['shell:windhawk-preset'].status 'ok' 'Windhawk bootstrap should persist preset application state.'
    Assert-Equal $script:windhawkNativeCalls 1 'Windhawk bootstrap should run the preset restore script.'

    $script:windhawkNativeCalls = 0
    $script:windhawkWriteEvidence = $false
    $windhawkMissingEvidenceState = New-TestAgentState
    Assert-Throws -ScriptBlock {
        Invoke-WinMintAgentWindhawkBootstrap -AgentProfile $windhawkProfile -State $windhawkMissingEvidenceState
    } -ExpectedText 'Windhawk preset evidence marker was not written' -Message 'Windhawk bootstrap should fail when native restore does not produce preset evidence.'
    Assert-True (-not $windhawkMissingEvidenceState.steps.ContainsKey('shell:windhawk-preset')) 'Windhawk should not persist preset state without native evidence.'
    $script:windhawkWriteEvidence = $true

    Invoke-AgentProfileModule -StepName 'disabled' -FunctionName 'Invoke-TestAgentOkModule' -Enabled $false
    Assert-Equal $State.steps['module:disabled'].status 'skipped' 'Disabled modules should persist skipped status.'
    Assert-True (Test-Path -LiteralPath $statePath) 'Save-AgentState should create state.json for skipped modules.'

    Invoke-AgentProfileModule -StepName 'ok-step' -FunctionName 'Invoke-TestAgentOkModule' -Enabled $true
    Assert-Equal $State.steps['module:ok-step'].status 'ok' 'Successful modules should persist ok status.'
    Assert-Equal $State.steps['module:ok-step'].attempts 1 'Successful modules should record first attempt.'
    Assert-Equal $State.steps['module:ok-step'].result.Marker 'ok-result' 'Successful modules should persist result payload.'

    Invoke-AgentProfileModule -StepName 'required-ok-step' -FunctionName 'Invoke-TestAgentRequiredOkModule' -Enabled $true
    Assert-Equal $State.steps['module:required-ok-step'].status 'ok' 'Runtime should accept successful modules when their required state is ok.'
    Assert-Equal $State.steps['module:required-ok-step'].result.Marker 'required-ok-result' 'Runtime should preserve required-state module results.'

    Invoke-AgentProfileModule -StepName 'required-missing-step' -FunctionName 'Invoke-TestAgentMissingRequiredModule' -Enabled $true
    Assert-Equal $State.steps['module:required-missing-step'].status 'failed' 'Runtime should fail ok module results when required state is missing.'
    Assert-True ([string]$State.steps['module:required-missing-step'].error -like '*missing: required:runtime-missing*') 'Runtime required-state failure should name missing keys.'

    Invoke-AgentProfileModule -StepName 'required-skipped-step' -FunctionName 'Invoke-TestAgentSkippedRequiredModule' -Enabled $true
    Assert-Equal $State.steps['module:required-skipped-step'].status 'skipped' 'Runtime should not enforce required state for skipped module results.'

    $script:postStepHookCalls = 0
    Invoke-AgentProfileModule -StepName 'hook-step' -FunctionName 'Invoke-TestAgentOkModule' -Enabled $true -PostStepHook 'Invoke-TestPostStepHook'
    Assert-Equal $script:postStepHookCalls 1 'Successful modules should invoke their post-step hook.'
    Invoke-AgentProfileModule -StepName 'hook-step' -FunctionName 'Invoke-TestAgentFailedModule' -Enabled $true -PostStepHook 'Invoke-TestPostStepHook'
    Assert-Equal $script:postStepHookCalls 2 'Idempotently skipped completed modules should still invoke their post-step hook.'

    Invoke-AgentProfileModule -StepName 'ok-step' -FunctionName 'Invoke-TestAgentFailedModule' -Enabled $true
    Assert-Equal $State.steps['module:ok-step'].status 'ok' 'Completed modules should be idempotently skipped without Force.'
    Assert-Equal $State.steps['module:ok-step'].attempts 1 'Completed modules should not increment attempts without Force.'

    $testContext.Force = $true
    Set-WinMintAgentContext -Context $testContext
    Invoke-AgentProfileModule -StepName 'ok-step' -FunctionName 'Invoke-TestAgentOkModule' -Enabled $true
    Assert-Equal $State.steps['module:ok-step'].attempts 2 'Force should re-run completed modules and increment attempts.'
    $testContext.Force = $false
    Set-WinMintAgentContext -Context $testContext

    Invoke-AgentProfileModule -StepName 'reboot-step' -FunctionName 'Invoke-TestAgentNeedsRebootModule' -Enabled $true
    Assert-Equal $State.steps['module:reboot-step'].status 'needsReboot' 'Modules should persist needsReboot status for retry after reboot.'
    Assert-Equal $State.steps['module:reboot-step'].attempts 1 'needsReboot modules should record attempts.'

    Invoke-AgentProfileModule -StepName 'reboot-step' -FunctionName 'Invoke-TestAgentOkModule' -Enabled $true
    Assert-Equal $State.steps['module:reboot-step'].status 'ok' 'needsReboot modules should be retried on the next run.'
    Assert-Equal $State.steps['module:reboot-step'].attempts 2 'Retried needsReboot modules should increment attempts.'

    Invoke-AgentProfileModule -StepName 'failed-step' -FunctionName 'Invoke-TestAgentFailedModule' -Enabled $true
    Assert-Equal $State.steps['module:failed-step'].status 'failed' 'Throwing modules should persist failed status.'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$State.steps['module:failed-step'].error)) 'Failed modules should persist error text.'

    Invoke-AgentProfileModule -StepName 'liveInstallAudit' -FunctionName 'Invoke-TestLiveAuditFindingsModule' -Enabled $true
    Assert-Equal $State.steps['module:liveInstallAudit'].status 'ok' 'Live audit findings should not fail the FirstLogon agent state.'
    Assert-Equal $State.steps['module:liveInstallAudit'].result.Summary.error 2 'Live audit result should preserve error count for diagnostics.'

    $runtimeText = @(
            (Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Agent.Runtime.ps1') -Raw),
            (Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Agent.Plan.ps1') -Raw)
        ) -join "`n"
    Assert-True ($runtimeText -notmatch 'Invoke-WinMintAgentTilingDesktopBootstrap') 'Runtime should not reference the retired tiling desktop bootstrap name.'
    Assert-True ($runtimeText -notmatch "'tiling-desktop'") 'Runtime should not use tiling-desktop as a state step.'

    foreach ($moduleFile in @(Get-ChildItem -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Modules') -Filter '*.ps1' -File)) {
        $moduleText = Get-Content -LiteralPath $moduleFile.FullName -Raw
        Assert-True ($moduleText -notmatch 'Assert-WinMintAgentStateStepsOk') "FirstLogon module '$($moduleFile.Name)' should return RequiredStateSteps and leave enforcement to the runtime."
        Assert-True ($moduleText -notmatch 'Invoke-WinMintAgentTilingDesktopBootstrap') "FirstLogon module '$($moduleFile.Name)' should not reference the retired tiling desktop bootstrap name."
        Assert-True ($moduleText -notmatch "'tiling-desktop'") "FirstLogon module '$($moduleFile.Name)' should not use tiling-desktop as a state step."
        Assert-True ($moduleText -notmatch 'tool:(mingit|9PFXXSHC64H3|AmN\.yasb|Nilesoft\.Shell|LGUG2Z\.komorebi|LGUG2Z\.whkd)') "FirstLogon module '$($moduleFile.Name)' should resolve manifest-backed tool state keys through Get-AgentManifestToolStateKey."
    }

    $saved = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    Assert-Equal $saved.steps.'module:ok-step'.status 'ok' 'Saved state should round-trip ok module status.'
    Assert-Equal $saved.steps.'module:reboot-step'.attempts 2 'Saved state should round-trip retry attempts.'
    Assert-Equal $saved.steps.'module:liveInstallAudit'.status 'ok' 'Saved state should keep live audit diagnostic failures non-blocking.'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    throw "Agent state transition tests failed with $($failures.Count) failure(s)."
}

Write-Host 'Agent state transition tests passed.'

