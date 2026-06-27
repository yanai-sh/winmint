#Requires -Version 5.1

function Set-WinMintFirstLogonWindowsTerminalDefault {
    $terminalKey = 'HKCU\Console\%%Startup'
    Invoke-WinMintFirstLogonReg -Arguments @('add', $terminalKey, '/v', 'DelegationConsole', '/t', 'REG_SZ', '/d', '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}', '/f') -AllowFailure
    Invoke-WinMintFirstLogonReg -Arguments @('add', $terminalKey, '/v', 'DelegationTerminal', '/t', 'REG_SZ', '/d', '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}', '/f') -AllowFailure
    "$(Get-Date -Format 'o') Windows Terminal set as the live user's default terminal host." |
        Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
}


function Set-WinMintFirstLogonTerminalProfiles {
    param([Parameter()][string]$AgentProfilePath)

    $distros = Get-WinMintProfileWslDistros -AgentProfilePath $AgentProfilePath
    $status = Set-WinMintWindowsTerminalProfiles -WslDistros $distros
    if ($status -eq 'missing-terminal-settings') { return }

    $settingsPath = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    $profileNames = try {
        $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        @($settings.profiles.list | ForEach-Object { [string]$_.name }) -join ', '
    }
    catch {
        'PowerShell'
    }
    "$(Get-Date -Format 'o') Windows Terminal defaults applied; profiles present: $profileNames" |
        Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
}
