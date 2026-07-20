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

function Send-WinMintGuestRuntimeCommon {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$GuestDirectory
    )

    # Repo setup/firstlogon copies are re-exporters; stage the canonical common bytes (same as ISO staging).
    $canonical = Join-Path $repoRoot 'src\runtime\common\WinMint.Runtime.Common.ps1'
    if (-not (Test-Path -LiteralPath $canonical -PathType Leaf)) {
        throw "Canonical WinMint.Runtime.Common.ps1 missing: $canonical"
    }
    Send-WinMintGuestFile -Session $Session -LocalPath $canonical -GuestDirectory $GuestDirectory
}

function Assert-WinMintGuestRuntimeCommon {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$GuestDirectory
    )

    Invoke-Command -Session $Session -ScriptBlock {
        param([string]$Dir)
        $path = Join-Path $Dir 'WinMint.Runtime.Common.ps1'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Guest Common missing after push: $path"
        }
        $raw = Get-Content -LiteralPath $path -Raw
        if ($raw -match 'common\\WinMint\.Runtime\.Common\.ps1' -and $raw -notmatch 'function\s+Resolve-WinMintPowerShell7Host') {
            throw "Guest Common is still the repo re-exporter stub at $path — canonical common was not staged."
        }
        if ($raw -notmatch 'function\s+Resolve-WinMintPowerShell7Host') {
            throw "Guest Common at $path does not define Resolve-WinMintPowerShell7Host."
        }
        if ($raw -notmatch 'function\s+Read-WinMintJsonFile') {
            throw "Guest Common at $path does not define Read-WinMintJsonFile."
        }
    } -ArgumentList $GuestDirectory
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
        [Parameter(Mandatory)][string]$EntryPath,
        [string]$AgentMode,
        [switch]$AgentForce
    )

    # Register-ScheduledTask with Interactive principal runs in the signed-in desktop session (schtasks /RP stays Queued from PS Direct).
    return Invoke-WinMintVmGuestCommand -VMName $VMName -Credential $Credential -TimeoutSeconds 120 -ScriptBlock {
        param([string]$Name, [string]$User, [string]$Pass, [string]$Entry, [string]$Mode, [bool]$Force)
        if (-not (Test-Path -LiteralPath $Entry -PathType Leaf)) {
            throw "Script missing on guest: $Entry"
        }
        $explorer = @(Get-Process -Name explorer -ErrorAction SilentlyContinue)
        if ($explorer.Count -lt 1) {
            throw 'No explorer.exe on guest — sign in to the desktop before launching FirstLogon.'
        }
        $pwsh = if (Test-Path -LiteralPath 'C:\Program Files\PowerShell\7\pwsh.exe') {
            'C:\Program Files\PowerShell\7\pwsh.exe'
        } else {
            'powershell.exe'
        }
        $argTail = if ($Entry -like '*FirstLogon.ps1') {
            "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Entry`" -AgentMode $Mode"
        } else {
            $tail = "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Entry`""
            if ($Force) { $tail += ' -Force' }
            $tail
        }
        $marker = "WINMINT-PUSH-LAUNCH $(Get-Date -Format o)"
        $logDir = 'C:\ProgramData\WinMint\Logs'
        $null = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue
        $logPath = Join-Path $logDir 'FirstLogon.log'
        $errPath = Join-Path $logDir 'FirstLogon_errors.log'
        # Wipe prior run signals so launch detection cannot inherit stale "elevated: False" / error tails.
        foreach ($path in @($logPath, $errPath, (Join-Path $logDir 'FirstLogon_transcript.log'))) {
            if (Test-Path -LiteralPath $path) {
                Set-Content -LiteralPath $path -Value "$marker`n" -Encoding utf8
            }
        }
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction SilentlyContinue
        $action = New-ScheduledTaskAction -Execute $pwsh -Argument $argTail
        $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddSeconds(2))
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        $principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $Name -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
        Start-ScheduledTask -TaskName $Name

        $needle = if ($Entry -like '*FirstLogon.ps1') { '*FirstLogon.ps1*' } else { '*Start-WinMintAgent.ps1*' }
        $deadline = (Get-Date).AddSeconds(25)
        $procs = @()
        $logStarted = $false
        $relaunchLogged = $false
        $hostLine = ''
        do {
            Start-Sleep -Milliseconds 750
            $procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                Where-Object { $_.CommandLine -and ($_.CommandLine -like $needle) })
            if ($Entry -like '*FirstLogon.ps1' -and (Test-Path -LiteralPath $logPath)) {
                $logStarted = [bool](Select-String -LiteralPath $logPath -Pattern 'FirstLogon\.ps1 start' -Quiet)
                $relaunchLogged = [bool](Select-String -LiteralPath $logPath -Pattern 're-launched elevated via scheduled task' -Quiet)
                $hostMatch = Select-String -LiteralPath $logPath -Pattern 'FirstLogon running elevated:' | Select-Object -Last 1
                if ($hostMatch) { $hostLine = [string]$hostMatch.Line }
            }
            $stateNow = [string](Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue).State
            if ($procs.Count -gt 0 -or $logStarted -or $relaunchLogged) { break }
            if ($stateNow -match 'Queued|Ready') {
                try { Start-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue } catch { }
                & schtasks.exe /Run /TN $Name 2>$null | Out-Null
            }
        } while ((Get-Date) -lt $deadline)

        $info = Get-ScheduledTaskInfo -TaskName $Name
        $logTail = @(if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Tail 12 -ErrorAction SilentlyContinue })
        $errTail = @(if (Test-Path -LiteralPath $errPath) { Get-Content -LiteralPath $errPath -Tail 12 -ErrorAction SilentlyContinue })
        $elevTask = Get-ScheduledTask -TaskName 'WinMintFirstLogonElevated' -ErrorAction SilentlyContinue
        $elevInfo = if ($elevTask) { Get-ScheduledTaskInfo -TaskName 'WinMintFirstLogonElevated' } else { $null }
        return [pscustomobject]@{
            Task = $Name
            Principal = $User
            Marker = $marker
            ExplorerSessions = @($explorer | ForEach-Object { $_.SessionId } | Sort-Object -Unique)
            TaskState = (Get-ScheduledTask -TaskName $Name).State
            LastTaskResult = [uint32]$info.LastTaskResult
            ProcessSeen = ($procs.Count -gt 0)
            ProcessCount = $procs.Count
            FirstLogonLogStarted = $logStarted
            RelaunchElevatedLogged = $relaunchLogged
            ElevatedLine = $hostLine
            ElevatedTaskState = if ($elevTask) { [string]$elevTask.State } else { '' }
            ElevatedLastResult = if ($elevInfo) { [uint32]$elevInfo.LastTaskResult } else { $null }
            FirstLogonLogTail = $logTail
            FirstLogonErrorsTail = $errTail
        }
    } -ArgumentList @($TaskName, $GuestUser, $GuestPassword, $EntryPath, $AgentMode, [bool]$AgentForce)
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
        Write-Host 'Waiting for explorer.exe to start on guest VM (automatic desktop detection)...'
        $expStarted = Get-Date
        $expTimeout = $expStarted.AddMinutes(5)
        $expReady = $false
        while ((Get-Date) -lt $expTimeout) {
            $expCheck = Invoke-WinMintVmGuestCommand -VMName $VMName -Credential $Credential -TimeoutSeconds 15 -ScriptBlock {
                Get-Process -Name explorer -ErrorAction SilentlyContinue
            }
            if ($expCheck.Ok -and $expCheck.Result) {
                $expReady = $true
                break
            }
            Start-Sleep -Seconds 5
        }
        if (-not $expReady) {
            throw "explorer.exe did not start on the guest VM within 5 minutes."
        }
        Write-Host '  explorer.exe is running on guest desktop.'
    }

    $reset = Invoke-WinMintVmGuestCommand -VMName $VMName -Credential $Credential -TimeoutSeconds 30 -ScriptBlock {
        $statePath = Join-Path $env:LOCALAPPDATA 'WinMint\state.json'
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        $logDir = 'C:\ProgramData\WinMint\Logs'
        foreach ($name in @(
                'FirstLogon_self-elevation.flag',
                'FirstLogon_pwsh7.flag',
                'FirstLogonState.json'
            )) {
            Remove-Item -LiteralPath (Join-Path $logDir $name) -Force -ErrorAction SilentlyContinue
        }
        & schtasks.exe /Delete /TN 'WinMintFirstLogonElevated' /F 2>$null | Out-Null
    }
    if (-not $reset.Ok) {
        throw "Failed to reset guest FirstLogon bootstrap state: $($reset.Error)"
    }

    $task = Invoke-WinMintVmPushGuestInteractiveTask -VMName $VMName -Credential $Credential `
        -GuestUser $GuestUser -GuestPassword $GuestPassword -TaskName 'WinMintPushFirstLogon' `
        -EntryPath 'C:\Windows\Setup\Scripts\FirstLogon.ps1' -AgentMode $AgentMode
    if (-not $task.Ok) {
        throw "Failed to start FirstLogon in guest: $($task.Error)"
    }
    $r = $task.Result
    Write-Host ("  scheduled task {0} started (state={1}, lastResult={2}, ProcessSeen={3}, log={4}, elev={5})." -f `
        $r.Task, $r.TaskState, $r.LastTaskResult, $r.ProcessSeen, $r.FirstLogonLogStarted, $(if ($r.ElevatedLine) { $r.ElevatedLine } else { 'n/a' }))
    $stillRunning = [uint32]$r.LastTaskResult -eq 267009 -or [string]$r.TaskState -match 'Running'
    $elevRunning = [string]$r.ElevatedTaskState -match 'Running' -or [uint32]$r.ElevatedLastResult -eq 267009
    if ($stillRunning -or $r.ProcessSeen -or $elevRunning) {
        return
    }
    if ([bool]$r.RelaunchElevatedLogged) {
        Write-Host '  FirstLogon handed off to elevated child task; continuing poll.' -ForegroundColor DarkGray
        return
    }
    if ([bool]$r.FirstLogonLogStarted -and [string]$r.ElevatedLine -match 'elevated:\s*True') {
        Write-Host '  FirstLogon elevated bootstrap confirmed in fresh log.' -ForegroundColor DarkGray
        return
    }
    if ([bool]$r.FirstLogonLogStarted -and [uint32]$r.LastTaskResult -eq 0) {
        Write-Host '  FirstLogon wrote a fresh start line; continuing poll.' -ForegroundColor DarkGray
        return
    }
    $errText = if ($r.FirstLogonErrorsTail) { ($r.FirstLogonErrorsTail -join ' | ') }
        elseif ($r.FirstLogonLogTail) { ($r.FirstLogonLogTail -join ' | ') }
        else { '(no FirstLogon log tails)' }
    throw ("FirstLogon did not actually start after launch (state={0}, LastTaskResult={1}). Log/errors: {2}" -f `
        $r.TaskState, $r.LastTaskResult, $errText)
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
        Write-Host 'Waiting for explorer.exe to start on guest VM (automatic desktop detection)...'
        $expStarted = Get-Date
        $expTimeout = $expStarted.AddMinutes(5)
        $expReady = $false
        while ((Get-Date) -lt $expTimeout) {
            $expCheck = Invoke-WinMintVmGuestCommand -VMName $VMName -Credential $Credential -TimeoutSeconds 15 -ScriptBlock {
                Get-Process -Name explorer -ErrorAction SilentlyContinue
            }
            if ($expCheck.Ok -and $expCheck.Result) {
                $expReady = $true
                break
            }
            Start-Sleep -Seconds 5
        }
        if (-not $expReady) {
            throw "explorer.exe did not start on the guest VM within 5 minutes."
        }
        Write-Host '  explorer.exe is running on guest desktop.'
    }

    $task = Invoke-WinMintVmPushGuestInteractiveTask -VMName $VMName -Credential $Credential `
        -GuestUser $GuestUser -GuestPassword $GuestPassword -TaskName 'WinMintPushAgent' `
        -EntryPath 'C:\Windows\Setup\Scripts\WinMintAgent\Start-WinMintAgent.ps1' -AgentForce
    if (-not $task.Ok) {
        throw "Failed to start WinMintAgent in guest: $($task.Error)"
    }
    if (-not $task.Result.ProcessSeen) {
        Write-Host "  WARN: agent process not visible yet (lastResult=$($task.Result.LastTaskResult))." -ForegroundColor Yellow
    }
}

function Sync-WinMintVmPushGuestAgentProfiles {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$GuestScripts,
        [Parameter(Mandatory)][string]$GuestAgent,
        [Parameter(Mandatory)][object]$BuildProfile
    )

    Import-Module (Join-Path $repoRoot 'src\runtime\modules\WinMint.Engine\WinMint.Engine.psd1') -Force
    $installPlan = New-WinMintInstallPlan -BuildProfile $BuildProfile
    $profileStagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("winmint-push-{0}" -f [guid]::NewGuid().ToString('n'))
    $null = New-Item -ItemType Directory -Path $profileStagingDir -Force
    try {
        $agentProfilePath = Join-Path $profileStagingDir 'WinMintAgentProfile.json'
        $setupProfilePath = Join-Path $profileStagingDir 'WinMintSetupProfile.json'
        $installPlan.AgentProfile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $agentProfilePath -Encoding utf8
        $installPlan.SetupProfile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $setupProfilePath -Encoding utf8
        Invoke-Command -Session $Session -ScriptBlock {
            Remove-Item -LiteralPath 'C:\Windows\Setup\Scripts\WinMintAgent\BuildProfile.json' -Force -ErrorAction SilentlyContinue
        }
        Send-WinMintGuestFile -Session $Session -LocalPath $agentProfilePath -GuestDirectory $GuestAgent
        Send-WinMintGuestFile -Session $Session -LocalPath $setupProfilePath -GuestDirectory $GuestScripts
        Write-Host '  Synced generated agent/setup profiles to guest.'
    }
    finally {
        Remove-Item -LiteralPath $profileStagingDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Sync-WinMintVmPushGuestSetupScripts {
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][pscredential]$Credential
    )

    # Lightweight for -LaunchOnly: sync FirstLogon entry + host modules before rerun.
    $session = New-PSSession -VMName $VMName -Credential $Credential -ErrorAction Stop
    try {
        $guestScripts = 'C:\Windows\Setup\Scripts'
        Ensure-WinMintGuestDirectories -Session $session -Paths @($guestScripts, "$guestScripts\TerminalIcons")
        $setupRoot = Join-Path $repoRoot 'src\runtime\setup'
        foreach ($name in @(
                'FirstLogon.ps1',
                'FirstLogon.Context.ps1',
                'FirstLogon.Support.ps1',
                'FirstLogon.Host.ps1',
                'FirstLogon.State.ps1',
                'FirstLogon.Transaction.ps1',
                'FirstLogon.Runtime.ps1',
                'WinMint.RuntimeState.ps1',
                'WinMint.Diagnostics.ps1',
                'WindowsTerminal.Profiles.ps1',
                'WinMintSetupShell.Status.ps1',
                'ProvisioningGuard.ps1',
                'FirstLogon.Desktop.ps1',
                'FirstLogon.Region.ps1',
                'FirstLogon.Cleanup.ps1'
            )) {
            $local = Join-Path $setupRoot $name
            if (Test-Path -LiteralPath $local -PathType Leaf) {
                Send-WinMintGuestFile -Session $session -LocalPath $local -GuestDirectory $guestScripts
            }
        }
        foreach ($iconName in @('ubuntu.png', 'fedora.png', 'archlinux.png', 'nixos.png', 'pengwin.png')) {
            $iconPath = Join-Path $repoRoot "assets\ui\wsl\$iconName"
            if (Test-Path -LiteralPath $iconPath -PathType Leaf) {
                Send-WinMintGuestFile -Session $session -LocalPath $iconPath -GuestDirectory "$guestScripts\TerminalIcons"
            }
        }
        Send-WinMintGuestRuntimeCommon -Session $session -GuestDirectory $guestScripts
        Assert-WinMintGuestRuntimeCommon -Session $session -GuestDirectory $guestScripts

        $guestAgent = "$guestScripts\WinMintAgent"
        Ensure-WinMintGuestDirectories -Session $session -Paths @($guestAgent, "$guestAgent\Modules")
        $firstlogonRoot = Join-Path $repoRoot 'src\runtime\firstlogon'
        foreach ($f in Get-ChildItem -LiteralPath $firstlogonRoot -File) {
            if ($f.Name -eq 'WinMint.Runtime.Common.ps1') { continue }
            Send-WinMintGuestFile -Session $session -LocalPath $f.FullName -GuestDirectory $guestAgent
        }
        Send-WinMintGuestRuntimeCommon -Session $session -GuestDirectory $guestAgent
        Copy-Item -Path (Join-Path $firstlogonRoot 'Modules\*') -Destination "$guestAgent\Modules" -ToSession $session -Recurse -Force
        Send-WinMintGuestFile -Session $session -LocalPath (Join-Path $repoRoot 'config\packages.json') -GuestDirectory $guestAgent
        Sync-WinMintVmPushGuestAgentProfiles -Session $session -GuestScripts $guestScripts -GuestAgent $guestAgent -BuildProfile $profileJson
        Write-Host '  Synced FirstLogon bootstrap + agent scripts to guest.'
    }
    finally {
        Remove-PSSession $session -ErrorAction SilentlyContinue
    }
}

$session = $null
if ($LaunchOnly) {
    if (-not $RerunFirstLogon) { $RerunFirstLogon = $true }
    Sync-WinMintVmPushGuestSetupScripts -VMName $VMName -Credential $cred
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
        "$guestScripts\TerminalIcons",
        $guestSetupShell,
        $guestAgent,
        "$guestAgent\Modules"
    )

    # Terminate any running WinMintSetupShell or setup script instances to prevent locks and race condition cleanups.
    Invoke-Command -Session $session -ScriptBlock {
        Stop-Process -Name 'WinMintSetupShell' -Force -ErrorAction SilentlyContinue
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and ($_.CommandLine -match 'FirstLogon|WinMintAgent') } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    }

    Write-Host 'Pushing src\runtime\setup (scripts + SetupComplete modules) ...'
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src\runtime\setup') -File) {
        if ($f.Name -eq 'WinMint.Runtime.Common.ps1') { continue }
        Send-WinMintGuestFile -Session $session -LocalPath $f.FullName -GuestDirectory $guestScripts
    }
    Send-WinMintGuestRuntimeCommon -Session $session -GuestDirectory $guestScripts
    Assert-WinMintGuestRuntimeCommon -Session $session -GuestDirectory $guestScripts
    Copy-Item -Path (Join-Path $repoRoot 'src\runtime\setup\SetupComplete\*') -Destination "$guestScripts\SetupComplete" -ToSession $session -Recurse -Force
    Write-Host 'Pushing WSL Terminal icons ...'
    foreach ($iconName in @('ubuntu.png', 'fedora.png', 'archlinux.png', 'nixos.png', 'pengwin.png')) {
        $iconPath = Join-Path $repoRoot "assets\ui\wsl\$iconName"
        if (Test-Path -LiteralPath $iconPath -PathType Leaf) {
            Send-WinMintGuestFile -Session $session -LocalPath $iconPath -GuestDirectory "$guestScripts\TerminalIcons"
        }
    }

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
        if ($f.Name -eq 'WinMint.Runtime.Common.ps1') { continue }
        Send-WinMintGuestFile -Session $session -LocalPath $f.FullName -GuestDirectory $guestAgent
    }
    Send-WinMintGuestRuntimeCommon -Session $session -GuestDirectory $guestAgent
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
            Write-Host 'Starting FirstLogon.ps1 in the guest (interactive scheduled task) ...'
            Start-WinMintVmPushGuestFirstLogon -VMName $VMName -Credential $cred `
                -GuestUser $GuestUser -GuestPassword $GuestPassword -AgentMode $AgentMode -RequireDesktopAck:$needDesktopAck
        }
        else {
            Write-Host 'Starting WinMintAgent in the guest (interactive scheduled task, -Force) ...'
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
            if (-not (Test-Path -LiteralPath $p)) {
                $snapshot.runStatus = 'missing'
                return [pscustomobject]$snapshot
            }
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
        if ([string]$status.runStatus -eq 'missing') {
            $flCheck = Invoke-WinMintVmGuestCommand -VMName $VMName -Credential $cred -TimeoutSeconds 30 -ScriptBlock {
                param([datetime]$Since)
                $errPath = 'C:\ProgramData\WinMint\Logs\FirstLogon_errors.log'
                $flStatePath = 'C:\ProgramData\WinMint\Logs\FirstLogonState.json'
                $logPath = 'C:\ProgramData\WinMint\Logs\FirstLogon.log'
                $freshStarts = 0
                $freshElevTrue = $false
                $freshElevFalse = $false
                $freshErrors = [System.Collections.Generic.List[string]]::new()
                if (Test-Path -LiteralPath $logPath) {
                    foreach ($line in @(Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue)) {
                        if ($line -notmatch '^(?<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})') { continue }
                        try {
                            $ts = [datetime]::Parse([string]$Matches['ts'], $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                        } catch { continue }
                        if ($ts -lt $Since.AddSeconds(-30)) { continue }
                        if ($line -match 'FirstLogon\.ps1 start') { $freshStarts++ }
                        if ($line -match 'FirstLogon running elevated:\s*True') { $freshElevTrue = $true }
                        if ($line -match 'FirstLogon running elevated:\s*False') { $freshElevFalse = $true }
                    }
                }
                if (Test-Path -LiteralPath $errPath) {
                    foreach ($line in @(Get-Content -LiteralPath $errPath -ErrorAction SilentlyContinue)) {
                        if ($line -notmatch '^(?<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})') { continue }
                        try {
                            $ts = [datetime]::Parse([string]$Matches['ts'], $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                        } catch { continue }
                        if ($ts -lt $Since.AddSeconds(-30)) { continue }
                        if ($line -match '(?i)AppX removal failed') { continue }
                        if (-not [string]::IsNullOrWhiteSpace($line)) { $freshErrors.Add($line) }
                    }
                }
                $flStatus = ''
                if (Test-Path -LiteralPath $flStatePath) {
                    try { $flStatus = [string](Get-Content -LiteralPath $flStatePath -Raw | ConvertFrom-Json).status } catch { }
                }
                $task = Get-ScheduledTask -TaskName 'WinMintPushFirstLogon' -ErrorAction SilentlyContinue
                $info = if ($task) { Get-ScheduledTaskInfo -TaskName 'WinMintPushFirstLogon' } else { $null }
                [pscustomobject]@{
                    FirstLogonStatus = $flStatus
                    FreshStarts = $freshStarts
                    FreshElevTrue = $freshElevTrue
                    FreshElevFalse = $freshElevFalse
                    FreshErrors = @($freshErrors)
                    TaskState = if ($task) { [string]$task.State } else { '' }
                    LastTaskResult = if ($info) { [uint32]$info.LastTaskResult } else { $null }
                }
            } -ArgumentList $waitStartedAt
            if ($flCheck.Ok -and $flCheck.Result) {
                $fl = $flCheck.Result
                if ($fl.FreshErrors.Count -gt 0) {
                    throw ("FirstLogon failed before agent state appeared: {0}" -f ($fl.FreshErrors -join ' | '))
                }
                if ([string]$fl.FirstLogonStatus -eq 'failed') {
                    throw "FirstLogonState.status=failed before agent state appeared."
                }
                if ($fl.FreshStarts -lt 1 -and [string]$fl.TaskState -match 'Queued|Ready' -and ($elapsed.TotalSeconds -ge 45)) {
                    throw ("FirstLogon task stuck {0} (lastResult={1}) with no fresh FirstLogon.log start after launch." -f $fl.TaskState, $fl.LastTaskResult)
                }
            }
        }
        $detail = if ($status.currentStep) { "step=$($status.currentStep)" }
            elseif ([string]$status.runStatus -eq 'missing') { 'state=missing' }
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
