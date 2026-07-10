#Requires -Version 7.6
# Host-side: print the guest FirstLogon failure signal without waiting for agent state.
[CmdletBinding()]
param(
    [string]$VMName = 'WinMint-ARM-Test',
    [string]$GuestUser = 'dev',
    [string]$GuestPassword = 'winmint'
)

$ErrorActionPreference = 'Stop'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run elevated (Hyper-V PowerShell Direct needs Administrator).' }

. (Join-Path $PSScriptRoot '..\vm\WinMint-VmConsole.ps1')
$cred = [pscredential]::new($GuestUser, (ConvertTo-SecureString $GuestPassword -AsPlainText -Force))
$result = Invoke-WinMintVmGuestCommand -VMName $VMName -Credential $cred -TimeoutSeconds 60 -ScriptBlock {
    $logDir = 'C:\ProgramData\WinMint\Logs'
    $tail = {
        param([string]$Path, [int]$N = 40)
        if (Test-Path -LiteralPath $Path) {
            Get-Content -LiteralPath $Path -Tail $N
        } else {
            @("(missing) $Path")
        }
    }
    $task = Get-ScheduledTask -TaskName 'WinMintPushFirstLogon' -ErrorAction SilentlyContinue
    $info = if ($task) { $task | Get-ScheduledTaskInfo } else { $null }
    $elev = $false
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $elev = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { }
    [pscustomobject]@{
        user = $env:USERNAME
        elevatedProbe = $elev
        explorer = [bool](Get-Process explorer -ErrorAction SilentlyContinue)
        pushTask = if ($task) {
            '{0}|state={1}|last={2}|result={3}' -f $task.TaskName, $task.State, $info.LastRunTime, $info.LastTaskResult
        } else { '(no WinMintPushFirstLogon task)' }
        elevFlag = Test-Path 'C:\ProgramData\WinMint\Logs\FirstLogon_self-elevation.flag'
        pwsh7Flag = Test-Path 'C:\ProgramData\WinMint\Logs\FirstLogon_pwsh7.flag'
        agentState = Test-Path (Join-Path $env:LOCALAPPDATA 'WinMint\state.json')
        firstLogonState = Test-Path 'C:\ProgramData\WinMint\Logs\FirstLogon.state.json'
        firstLogonLog = & $tail 'C:\ProgramData\WinMint\Logs\FirstLogon.log' 50
        errorsLog = & $tail 'C:\ProgramData\WinMint\Logs\FirstLogon_errors.log' 40
        transcriptTail = & $tail 'C:\ProgramData\WinMint\Logs\FirstLogon_transcript.log' 30
        elevTask = @(Get-ScheduledTask -TaskName 'WinMintFirstLogonElevated' -ErrorAction SilentlyContinue | ForEach-Object {
            $i = $_ | Get-ScheduledTaskInfo
            $a = ($_ | Get-ScheduledTask).Actions | Select-Object -First 1
            '{0}|state={1}|lastResult={2}|exe={3}|args={4}' -f $_.TaskName, $_.State, $i.LastTaskResult, $a.Execute, $a.Arguments
        })
        commonProbe = $(
            $p = 'C:\Windows\Setup\Scripts\WinMint.Runtime.Common.ps1'
            if (-not (Test-Path -LiteralPath $p)) { 'MISSING' }
            else {
                $raw = Get-Content -LiteralPath $p -Raw
                if ($raw -match "Join-Path \(Split-Path -Parent \`$?PSScriptRoot\) 'common\\WinMint\.Runtime\.Common\.ps1'") {
                    'STUB-REEXPORT'
                }
                elseif ($raw -match 'function\s+Resolve-WinMintPowerShell7Host' -and $raw -match 'function\s+Read-WinMintJsonFile') {
                    'CANONICAL'
                }
                else { 'UNEXPECTED' }
            }
        )
        commonBytes = if (Test-Path 'C:\Windows\Setup\Scripts\WinMint.Runtime.Common.ps1') {
            (Get-Item 'C:\Windows\Setup\Scripts\WinMint.Runtime.Common.ps1').Length
        } else { 0 }
    }
}
if (-not $result.Ok) { throw $result.Error }
$result.Result | ConvertTo-Json -Depth 6
