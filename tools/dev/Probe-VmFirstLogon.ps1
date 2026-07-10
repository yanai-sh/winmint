#Requires -Version 7.6
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\vm\WinMint-VmConsole.ps1')
$cred = [pscredential]::new('dev', (ConvertTo-SecureString 'winmint' -AsPlainText -Force))
$r = Invoke-WinMintVmGuestCommand -VMName 'WinMint-ARM-Test' -Credential $cred -TimeoutSeconds 45 -ScriptBlock {
    $winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    [pscustomobject]@{
        computer   = $env:COMPUTERNAME
        user       = $env:USERNAME
        explorer   = [bool](Get-Process explorer -ErrorAction SilentlyContinue)
        autologon  = [string](Get-ItemProperty -Path $winlogon -Name AutoAdminLogon -ErrorAction SilentlyContinue).AutoAdminLogon
        defaultUser = [string](Get-ItemProperty -Path $winlogon -Name DefaultUserName -ErrorAction SilentlyContinue).DefaultUserName
        hasPassword = -not [string]::IsNullOrWhiteSpace([string](Get-ItemProperty -Path $winlogon -Name DefaultPassword -ErrorAction SilentlyContinue).DefaultPassword)
        stateExists = Test-Path (Join-Path $env:LOCALAPPDATA 'WinMint\state.json')
        firstLogonTail = @(if (Test-Path 'C:\ProgramData\WinMint\Logs\FirstLogon.log') { Get-Content 'C:\ProgramData\WinMint\Logs\FirstLogon.log' -Tail 15 } else { '(no FirstLogon.log)' })
        errorsTail = @(if (Test-Path 'C:\ProgramData\WinMint\Logs\FirstLogon_errors.log') { Get-Content 'C:\ProgramData\WinMint\Logs\FirstLogon_errors.log' -Tail 15 } else { '(no errors log)' })
        task = @(Get-ScheduledTask -TaskName 'WinMintPushFirstLogon' -ErrorAction SilentlyContinue | ForEach-Object {
            $i = $_ | Get-ScheduledTaskInfo
            '{0}|state={1}|last={2}|result={3}' -f $_.TaskName, $_.State, $i.LastRunTime, $i.LastTaskResult
        })
        setupShell = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'WinMintSetupShell.exe' } |
            ForEach-Object { '{0}|{1}|{2}' -f $_.Name, $_.ProcessId, $_.CommandLine })
        procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^(pwsh|powershell|WinMintSetupShell)\.exe$' -and ($_.CommandLine -match 'FirstLogon|WinMintAgent|WinMintSetupShell') } |
            ForEach-Object { '{0}|{1}|{2}' -f $_.Name, $_.ProcessId, $_.CommandLine })
    }
}
"Ok=$($r.Ok) Err=$($r.Error)"
if ($r.Ok) { $r.Result | ConvertTo-Json -Depth 5 }
