#Requires -Version 7.6
<#
.SYNOPSIS
    Fast-iterate WinMint setup/agent scripts in a RUNNING Hyper-V test VM without a
    full rebuild.

.DESCRIPTION
    Pushes the repo's current src\runtime\setup and src\runtime\firstlogon into the guest's
    C:\Windows\Setup\Scripts over PowerShell Direct (VMBus - no network, no ESM,
    works on any Windows edition incl. Home), optionally re-runs FirstLogon or the
    agent, then pulls the guest logs + agent state back to the host.

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\Push-WinMintSetupScripts.ps1

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\Push-WinMintSetupScripts.ps1 -WaitForAgent -RerunFirstLogon

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\Push-WinMintSetupScripts.ps1 -RerunFirstLogon -AgentMode Auto
#>
[CmdletBinding()]
param(
    [string]$VMName = 'WinMint-ARM-Test',
    [string]$GuestUser = 'dev',
    [string]$GuestPassword = 'winmint',
    [string]$ProfilePath,
    [switch]$NoRerun,
    [switch]$LaunchOnly,
    [switch]$RerunFirstLogon,
    [switch]$WaitForAgent,
    [switch]$DisplayReboot,
    [int]$TimeoutMinutes = 60,
    [string]$OutDir,
    [ValidateSet('Auto', 'Headless', 'Console')]
    [string]$AgentMode = 'Headless'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
    $ProfilePath = Join-Path $repoRoot 'tests\profiles\hyper-v-smoke-arm64.json'
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run this in an elevated PowerShell - Hyper-V PowerShell Direct requires Administrator.' }
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) { throw "VM '$VMName' not found." }
if ($vm.State -ne 'Running') { throw "VM '$VMName' is not running (state: $($vm.State)). Start it and sign in first." }
if (-not $OutDir) { $OutDir = Join-Path $repoRoot 'output\vm-logs' }
$null = New-Item -ItemType Directory -Path $OutDir -Force

function Send-WinMintGuestFile {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$GuestDirectory
    )

    if (-not (Test-Path -LiteralPath $LocalPath -PathType Leaf)) {
        throw "Local push source is missing: $LocalPath"
    }
    Copy-Item -LiteralPath $LocalPath -Destination $GuestDirectory -ToSession $Session -Force
}

function Ensure-WinMintGuestDirectories {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string[]]$Paths
    )

    Invoke-Command -Session $Session -ScriptBlock {
        param([string[]]$DirectoryPaths)
        foreach ($path in $DirectoryPaths) {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Remove-Item -LiteralPath $path -Force
            }
            $null = New-Item -ItemType Directory -Path $path -Force
        }
    } -ArgumentList @(,$Paths)
}

if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
    throw "ProfilePath is missing: $ProfilePath"
}
$profileJson = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json

$cred = [pscredential]::new($GuestUser, (ConvertTo-SecureString $GuestPassword -AsPlainText -Force))
. (Join-Path $PSScriptRoot 'WinMint-VmConsole.ps1')

function Remove-WinMintVmPushSession {
    param([ref]$SessionRef)

    if ($null -ne $SessionRef.Value) {
        Remove-PSSession $SessionRef.Value -ErrorAction SilentlyContinue
        $SessionRef.Value = $null
    }
}

function Enable-WinMintVmPushGuestAutoLogon {
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][pscredential]$Credential,
        [Parameter(Mandatory)][string]$UserName,
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][string]$ComputerName
    )

    $stamp = Invoke-WinMintVmGuestCommand -VMName $VMName -Credential $Credential -TimeoutSeconds 45 -ScriptBlock {
        param([string]$User, [string]$Pass, [string]$Machine)
        $winlogon = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
        & reg.exe add $winlogon /v AutoAdminLogon /t REG_SZ /d 1 /f | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "reg AutoAdminLogon failed: $LASTEXITCODE" }
        & reg.exe add $winlogon /v DefaultUserName /t REG_SZ /d $User /f | Out-Null
        & reg.exe add $winlogon /v DefaultDomainName /t REG_SZ /d $Machine /f | Out-Null
        & reg.exe add $winlogon /v DefaultPassword /t REG_SZ /d $Pass /f | Out-Null
        & reg.exe delete $winlogon /v AutoLogonCount /f 2>$null | Out-Null
        return 'autologon-stamped'
    } -ArgumentList @($UserName, $Password, $ComputerName)
    if (-not $stamp.Ok) {
        throw "Failed to stamp guest AutoLogon: $($stamp.Error)"
    }
}

function Invoke-WinMintVmPushGuestInteractiveTask {
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][pscredential]$Credential,
        [Parameter(Mandatory)][string]$GuestUser,
        [Parameter(Mandatory)][string]$GuestPassword,
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$TaskCommand
    )

    return Invoke-WinMintVmGuestCommand -VMName $VMName -Credential $Credential -TimeoutSeconds 90 -ScriptBlock {
        param([string]$Name, [string]$User, [string]$Pass, [string]$Command)
        & schtasks.exe /Delete /TN $Name /F 2>$null | Out-Null
        $createOut = & schtasks.exe /Create /TN $Name /TR $Command /SC ONCE /ST 23:59 /RU $User /RP $Pass /RL HIGHEST /IT /F 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "schtasks /Create failed ($LASTEXITCODE): $createOut"
        }
        $runOut = & schtasks.exe /Run /TN $Name 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "schtasks /Run failed ($LASTEXITCODE): $runOut"
        }
        Start-Sleep -Seconds 4
        $info = & schtasks.exe /Query /TN $Name /FO LIST /V 2>&1
        $running = [bool](
            Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.CommandLine -and (
                        $_.CommandLine -like '*FirstLogon.ps1*' -or
                        $_.CommandLine -like '*Start-WinMintAgent.ps1*'
                    )
                }
        )
        return [pscustomobject]@{
            Task = $Name
            CreateOutput = [string]($createOut | Out-String).Trim()
            RunOutput = [string]($runOut | Out-String).Trim()
            QueryOutput = [string]($info | Out-String).Trim()
            ProcessSeen = $running
        }
    } -ArgumentList @($TaskName, $GuestUser, $GuestPassword, $TaskCommand)
}

function Start-WinMintVmPushGuestFirstLogon {
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][pscredential]$Credential,
        [Parameter(Mandatory)][string]$GuestUser,
        [Parameter(Mandatory)][string]$GuestPassword,
        [Parameter(Mandatory)][string]$AgentMode,
        [switch]$RequireDesktopAck
    )

    if ($RequireDesktopAck) {
        Write-Host ''
        Write-Host '>>> In the VM: sign in as dev and reach the desktop. Press Enter on this HOST when ready. <<<' -ForegroundColor Cyan
        Read-Host | Out-Null
    }

    $launch = Invoke-WinMintVmGuestCommand -VMName $VMName -Credential $Credential -TimeoutSeconds 45 -ScriptBlock {
        param([string]$Mode)
        $statePath = Join-Path $env:LOCALAPPDATA 'WinMint\state.json'
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        $pwsh = if (Test-Path -LiteralPath 'C:\Program Files\PowerShell\7\pwsh.exe') {
            'C:\Program Files\PowerShell\7\pwsh.exe'
        } else {
            'powershell.exe'
        }
        $entry = 'C:\Windows\Setup\Scripts\FirstLogon.ps1'
        if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) {
            throw "FirstLogon.ps1 missing on guest: $entry"
        }
        return [pscustomobject]@{
            Pwsh = $pwsh
            Entry = $entry
            Mode = $Mode
        }
    } -ArgumentList $AgentMode
    if (-not $launch.Ok) {
        throw "Failed to prepare FirstLogon launch in guest: $($launch.Error)"
    }

    $tr = ('"{0}" -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}" -AgentMode {2}' -f `
        $launch.Result.Pwsh, $launch.Result.Entry, $launch.Result.Mode)
    $task = Invoke-WinMintVmPushGuestInteractiveTask -VMName $VMName -Credential $Credential `
        -GuestUser $GuestUser -GuestPassword $GuestPassword -TaskName 'WinMintPushFirstLogon' -TaskCommand $tr
    if (-not $task.Ok) {
        throw "Failed to start FirstLogon in guest: $($task.Error)"
    }
    Write-Host "  schtasks WinMintPushFirstLogon started (ProcessSeen=$($task.Result.ProcessSeen))."
    if (-not [bool]$task.Result.ProcessSeen) {
        Write-Host '  WARN: FirstLogon process not visible yet; splash may still be starting.' -ForegroundColor Yellow
    }
}

function Start-WinMintVmPushGuestAgent {
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][pscredential]$Credential,
        [Parameter(Mandatory)][string]$GuestUser,
        [Parameter(Mandatory)][string]$GuestPassword,
        [switch]$RequireDesktopAck
    )

    if ($RequireDesktopAck) {
        Write-Host ''
        Write-Host '>>> In the VM: sign in as dev and reach the desktop. Press Enter on this HOST when ready. <<<' -ForegroundColor Cyan
        Read-Host | Out-Null
    }

    $launch = Invoke-WinMintVmGuestCommand -VMName $VMName -Credential $Credential -TimeoutSeconds 45 -ScriptBlock {
        $pwsh = if (Test-Path -LiteralPath 'C:\Program Files\PowerShell\7\pwsh.exe') {
            'C:\Program Files\PowerShell\7\pwsh.exe'
        } else {
            'powershell.exe'
        }
        $entry = 'C:\Windows\Setup\Scripts\WinMintAgent\Start-WinMintAgent.ps1'
        return [pscustomobject]@{ Pwsh = $pwsh; Entry = $entry }
    }
    if (-not $launch.Ok) {
        throw "Failed to prepare agent launch in guest: $($launch.Error)"
    }
    $tr = ('"{0}" -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}" -Force' -f `
        $launch.Result.Pwsh, $launch.Result.Entry)
    $task = Invoke-WinMintVmPushGuestInteractiveTask -VMName $VMName -Credential $Credential `
        -GuestUser $GuestUser -GuestPassword $GuestPassword -TaskName 'WinMintPushAgent' -TaskCommand $tr
    if (-not $task.Ok) {
        throw "Failed to start WinMintAgent in guest: $($task.Error)"
    }
}

$session = $null
if ($LaunchOnly) {
    if (-not $RerunFirstLogon) { $RerunFirstLogon = $true }
    if ($RerunFirstLogon) {
        Start-WinMintVmPushGuestFirstLogon -VMName $VMName -Credential $cred `
            -GuestUser $GuestUser -GuestPassword $GuestPassword -AgentMode $AgentMode -RequireDesktopAck
    }
    else {
        Start-WinMintVmPushGuestAgent -VMName $VMName -Credential $cred `
            -GuestUser $GuestUser -GuestPassword $GuestPassword -RequireDesktopAck
    }
}
else {
Write-Host "Opening PowerShell Direct session to '$VMName' as $GuestUser ..."
$session = New-PSSession -VMName $VMName -Credential $cred -ErrorAction Stop
try {
    $guestScripts = 'C:\Windows\Setup\Scripts'
    $guestAgent = "$guestScripts\WinMintAgent"
    $guestSetupShell = "$guestScripts\setup-shell"

    Ensure-WinMintGuestDirectories -Session $session -Paths @(
        $guestScripts,
        "$guestScripts\SetupComplete",
        $guestSetupShell,
        $guestAgent,
        "$guestAgent\Modules"
    )

    Write-Host 'Pushing src\runtime\setup (scripts + SetupComplete modules) ...'
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src\runtime\setup') -File) {
        Send-WinMintGuestFile -Session $session -LocalPath $f.FullName -GuestDirectory $guestScripts
    }
    Copy-Item -Path (Join-Path $repoRoot 'src\runtime\setup\SetupComplete\*') -Destination "$guestScripts\SetupComplete" -ToSession $session -Recurse -Force

    Write-Host 'Pushing setup shell native payload ...'
    $guestBin = if ($profileJson.source -and [string]$profileJson.source.architecture -eq 'arm64') { 'arm64' } else { 'x64' }
    $binRoot = Join-Path $repoRoot "assets\runtime\setup\setup-shell\bin\$guestBin"
    $shellSource = $null
    foreach ($candidateName in @('WinMintSetupShell.Native.exe', 'WinMintSetupShell.exe')) {
        $candidate = Join-Path $binRoot $candidateName
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $shellSource = $candidate
            break
        }
    }
    if (-not $shellSource) {
        Write-Host "Setup shell binary missing for $guestBin; running tools\release\Build-WinMintSetupShell.ps1 ..."
        $buildScript = Join-Path $repoRoot 'tools\release\Build-WinMintSetupShell.ps1'
        $hostArchFolder = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
        if ([string]$guestBin -eq 'arm64' -and [string]$hostArchFolder -ne 'ARM64') {
            & $buildScript -AllArch
        }
        else {
            & $buildScript
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Build-WinMintSetupShell.ps1 failed with exit code $LASTEXITCODE."
        }
        foreach ($candidateName in @('WinMintSetupShell.Native.exe', 'WinMintSetupShell.exe')) {
            $candidate = Join-Path $binRoot $candidateName
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $shellSource = $candidate
                break
            }
        }
    }
    if (-not $shellSource) {
        throw "Setup shell executable is missing for $guestBin under $binRoot (run tools\release\Build-WinMintSetupShell.ps1)."
    }
    # ISO staging copies Native as WinMintSetupShell.exe on the guest; match that layout.
    $shellStageDir = Join-Path ([System.IO.Path]::GetTempPath()) ("winmint-shell-{0}" -f [guid]::NewGuid().ToString('n'))
    $null = New-Item -ItemType Directory -Path $shellStageDir -Force
    $stagedExe = Join-Path $shellStageDir 'WinMintSetupShell.exe'
    Copy-Item -LiteralPath $shellSource -Destination $stagedExe -Force
    try {
        Send-WinMintGuestFile -Session $session -LocalPath $stagedExe -GuestDirectory $guestSetupShell
    }
    finally {
        Remove-Item -LiteralPath $shellStageDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    foreach ($asset in @('tokens.json')) {
        Send-WinMintGuestFile -Session $session -LocalPath (Join-Path $repoRoot "assets\runtime\setup\setup-shell\$asset") -GuestDirectory $guestSetupShell
    }
    foreach ($brandFile in @('winmint_hero_ui.png', 'winmint_hero.png')) {
        $brandSource = Join-Path $repoRoot "assets\brand\$brandFile"
        if (-not (Test-Path -LiteralPath $brandSource -PathType Leaf)) {
            throw "WinMint brand hero asset is missing: $brandSource"
        }
        Send-WinMintGuestFile -Session $session -LocalPath $brandSource -GuestDirectory $guestSetupShell
    }

    Write-Host 'Pushing src\runtime\firstlogon (code; preserving generated guest profiles/packages) ...'
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src\runtime\firstlogon') -File) {
        Send-WinMintGuestFile -Session $session -LocalPath $f.FullName -GuestDirectory $guestAgent
    }
    Copy-Item -Path (Join-Path $repoRoot 'src\runtime\firstlogon\Modules\*') -Destination "$guestAgent\Modules" -ToSession $session -Recurse -Force
    Send-WinMintGuestFile -Session $session -LocalPath (Join-Path $repoRoot 'config\packages.json') -GuestDirectory $guestAgent

    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
        throw "ProfilePath is missing: $ProfilePath"
    }
    Import-Module (Join-Path $repoRoot 'src\runtime\modules\WinMint.Engine\WinMint.Engine.psd1') -Force
    $buildProfile = $profileJson
    $installPlan = New-WinMintInstallPlan -BuildProfile $buildProfile
    $profileStagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("winmint-push-{0}" -f [guid]::NewGuid().ToString('n'))
    $null = New-Item -ItemType Directory -Path $profileStagingDir -Force
    try {
        $agentProfilePath = Join-Path $profileStagingDir 'WinMintAgentProfile.json'
        $setupProfilePath = Join-Path $profileStagingDir 'WinMintSetupProfile.json'
        $installPlan.AgentProfile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $agentProfilePath -Encoding utf8
        $installPlan.SetupProfile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $setupProfilePath -Encoding utf8
        Write-Host "Pushing generated agent/setup profiles from '$ProfilePath' ..."
        # Drop stale misnamed push artifact from earlier iterations (agent reads WinMintAgentProfile.json only).
        Invoke-Command -Session $session -ScriptBlock {
            Remove-Item -LiteralPath 'C:\Windows\Setup\Scripts\WinMintAgent\BuildProfile.json' -Force -ErrorAction SilentlyContinue
        }
        Send-WinMintGuestFile -Session $session -LocalPath $agentProfilePath -GuestDirectory $guestAgent
        Send-WinMintGuestFile -Session $session -LocalPath $setupProfilePath -GuestDirectory $guestScripts
    }
    finally {
        Remove-Item -LiteralPath $profileStagingDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not $NoRerun) {
        if ($DisplayReboot) {
            Write-Host 'DisplayReboot: stamping AutoLogon and rebooting guest (optional splash reset) ...'
            $machineName = (Invoke-WinMintVmGuestCommand -VMName $VMName -Credential $cred -TimeoutSeconds 30 -ScriptBlock {
                $env:COMPUTERNAME
            }).Result
            if ([string]::IsNullOrWhiteSpace($machineName)) { $machineName = 'WinMintVM' }
            Enable-WinMintVmPushGuestAutoLogon -VMName $VMName -Credential $cred -UserName $GuestUser -Password $GuestPassword -ComputerName $machineName
            Invoke-Command -Session $session -ScriptBlock { Restart-Computer -Force }
            Remove-WinMintVmPushSession -SessionRef ([ref]$session)
            Wait-WinMintVmGuestDirectReady -VMName $VMName -Credential $cred -TimeoutMinutes 10
        }
        $needDesktopAck = $true
        if ($RerunFirstLogon) {
            Write-Host 'Starting FirstLogon.ps1 in the guest (interactive schtasks) ...'
            Start-WinMintVmPushGuestFirstLogon -VMName $VMName -Credential $cred `
                -GuestUser $GuestUser -GuestPassword $GuestPassword -AgentMode $AgentMode -RequireDesktopAck:$needDesktopAck
        }
        else {
            Write-Host 'Starting WinMintAgent in the guest (interactive schtasks, -Force) ...'
            Start-WinMintVmPushGuestAgent -VMName $VMName -Credential $cred `
                -GuestUser $GuestUser -GuestPassword $GuestPassword -RequireDesktopAck:$needDesktopAck
        }
        Remove-WinMintVmPushSession -SessionRef ([ref]$session)
    }
}
finally {
    Remove-WinMintVmPushSession -SessionRef ([ref]$session)
}
}

if ($WaitForAgent) {
    Write-Host "Waiting for terminal agent run.status (timeout ${TimeoutMinutes}m) ..."
    $waitStartedAt = Get-Date
    $deadline = $waitStartedAt.AddMinutes($TimeoutMinutes)
    $pollSeconds = 10
    $terminal = $false
    while ((Get-Date) -lt $deadline) {
        $now = Get-Date
        $elapsed = $now - $waitStartedAt
        $remaining = $deadline - $now
        if ($remaining -lt [TimeSpan]::Zero) { $remaining = [TimeSpan]::Zero }
        $statusPoll = Invoke-WinMintVmGuestCommand -VMName $VMName -Credential $cred -TimeoutSeconds 45 -ScriptBlock {
            $snapshot = [ordered]@{
                runStatus = ''
                currentStep = ''
                completedSteps = 0
                totalSteps = 0
            }
            $p = Join-Path $env:LOCALAPPDATA 'WinMint\state.json'
            if (-not (Test-Path -LiteralPath $p)) { return [pscustomobject]$snapshot }
            try {
                $state = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
                if ($state.run -and $state.run.PSObject.Properties['status']) {
                    $snapshot.runStatus = [string]$state.run.status
                }
                if ($state.steps) {
                    foreach ($prop in $state.steps.PSObject.Properties) {
                        $snapshot.totalSteps++
                        $stepStatus = if ($prop.Value -and $prop.Value.PSObject.Properties['status']) {
                            [string]$prop.Value.status
                        } else { 'pending' }
                        if ($stepStatus -in @('ok', 'skipped')) { $snapshot.completedSteps++ }
                        if ($stepStatus -eq 'running' -and -not $snapshot.currentStep) {
                            $snapshot.currentStep = [string]$prop.Name
                        }
                    }
                }
            }
            catch { }
            return [pscustomobject]$snapshot
        }
        if (-not $statusPoll.Ok) {
            $hint = if ($statusPoll.TimedOut) { 'guest poll timed out' } else { $statusPoll.Error }
            Write-Host ("  [{0} elapsed, {1} left] run=pending | guest=unreachable ({2})" -f `
                (Format-WinMintVmDuration $elapsed), (Format-WinMintVmDuration $remaining), $hint)
            Start-Sleep -Seconds $pollSeconds
            continue
        }
        $status = $statusPoll.Result
        if ([string]$status.runStatus -in @('ok', 'failed')) {
            $terminal = $true
            Write-Host "Agent run.status = $($status.runStatus)"
            break
        }
        $detail = if ($status.currentStep) { "step=$($status.currentStep)" }
            elseif ($status.totalSteps -gt 0) { "steps=$($status.completedSteps)/$($status.totalSteps)" }
            else { 'agent=starting' }
        Write-Host ("  [{0} elapsed, {1} left] run={2} | {3}" -f `
            (Format-WinMintVmDuration $elapsed), (Format-WinMintVmDuration $remaining), $(if ($status.runStatus) { $status.runStatus } else { 'pending' }), $detail)
        Start-Sleep -Seconds $pollSeconds
    }
    if (-not $terminal) {
        throw "Agent did not reach a terminal run.status within $TimeoutMinutes min."
    }
}

Write-Host 'Pulling guest logs + agent state back to host ...'
Wait-WinMintVmGuestDirectReady -VMName $VMName -Credential $cred -TimeoutMinutes 5
$pullSession = New-PSSession -VMName $VMName -Credential $cred -ErrorAction Stop
try {
    Invoke-Command -Session $pullSession -ScriptBlock {
        $dst = 'C:\Windows\Temp\winmint-pull'
        Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue
        $null = New-Item -ItemType Directory -Path $dst -Force
        Copy-Item -LiteralPath 'C:\ProgramData\WinMint\Logs' -Destination (Join-Path $dst 'ProgramData-Logs') -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath "$env:LOCALAPPDATA\WinMint") {
            Copy-Item -LiteralPath "$env:LOCALAPPDATA\WinMint" -Destination (Join-Path $dst 'LocalAppData-WinMint') -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Copy-Item -FromSession $pullSession -Path 'C:\Windows\Temp\winmint-pull\*' -Destination $OutDir -Recurse -Force
}
finally {
    Remove-PSSession $pullSession -ErrorAction SilentlyContinue
}
Write-Host "Done. Guest logs + state pulled to: $OutDir"
$statePath = Join-Path $OutDir 'LocalAppData-WinMint\state.json'
if (Test-Path -LiteralPath $statePath) {
    Write-Host '--- agent run summary ---'
    $st = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $summary = "run.status = $($st.run.status); failedSteps = $(@($st.run.failedSteps) -join ', ')"
    Write-Host $summary
    if ([string]$st.run.status -eq 'failed') { exit 1 }
}
