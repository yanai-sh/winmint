#Requires -Version 7.6
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\vm\lib\VmGuest.ps1')
$cred = New-Object pscredential('dev', (ConvertTo-SecureString 'winmint' -AsPlainText -Force))
Invoke-WinMintVmGuestCommand -VMName 'WinMint-ARM-Test' -Credential $cred -TimeoutSeconds 120 -ScriptBlock {
    $paths = @(
        'C:\ProgramData\WinMint\Logs\FirstLogon.log'
        'C:\ProgramData\WinMint\Logs\FirstLogon_errors.log'
        'C:\ProgramData\WinMint\Logs\WinMintAgent.log'
        'C:\Windows\Setup\Scripts\WinMintAgent\WinMintAgentProfile.json'
        "$env:LOCALAPPDATA\WinMint\state.json"
        "$env:LOCALAPPDATA\WinMint\Logs\WinMintAgent-events.jsonl"
    )
    foreach ($p in $paths) {
        Write-Output "=== $p ==="
        if (Test-Path -LiteralPath $p) {
            if ($p.EndsWith('.json') -or $p.EndsWith('.jsonl')) {
                Get-Content -LiteralPath $p -Raw
            }
            else {
                Get-Content -LiteralPath $p -Tail 60
            }
        }
        else {
            Write-Output '(missing)'
        }
    }
}
