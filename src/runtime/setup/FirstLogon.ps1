#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Auto','UI','Console','Headless')]
    [string]$AgentMode = 'Auto'
)

$ErrorActionPreference = 'Continue'
# Logs land in ProgramData (Administrators-readable) rather than C:\Windows\Setup\Scripts
# (Users-readable). Setup\Scripts holds the staged agent payload; logs do not belong there.
$logDir = Join-Path $env:ProgramData 'WinMint\Logs'
$null = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue
$payloadDir = 'C:\Windows\Setup\Scripts'  # where the staged agent + state file live

function Initialize-WinMintFirstLogonConsoleEncoding {
    try {
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [Console]::InputEncoding = $utf8
        [Console]::OutputEncoding = $utf8
        $global:OutputEncoding = $utf8
        $global:PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
        $global:PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
        $global:PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
    }
    catch { }
    try {
        $chcpExe = Join-Path $env:SystemRoot 'System32\chcp.com'
        $null = & $chcpExe 65001 2>$null
    }
    catch { }
}

Initialize-WinMintFirstLogonConsoleEncoding
$script:WinMintFirstLogonMaxAttempts = 3
"$(Get-Date -Format 'o') FirstLogon.ps1 start" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
try { Start-Transcript -Path (Join-Path $logDir 'FirstLogon_transcript.log') -Append -ErrorAction SilentlyContinue | Out-Null } catch { }

$script:WinMintFirstLogonEntryPath = $PSCommandPath
$supportPath = Join-Path $payloadDir 'FirstLogon.Support.ps1'
if (-not (Test-Path -LiteralPath $supportPath -PathType Leaf)) {
    "$(Get-Date -Format 'o') FirstLogon support module is missing: $supportPath" | Out-File (Join-Path $logDir 'FirstLogon_errors.log') -Append
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
    exit 1
}
. $supportPath

$transactionPath = Join-Path $payloadDir 'FirstLogon.Transaction.ps1'
if (-not (Test-Path -LiteralPath $transactionPath -PathType Leaf)) {
    Write-WinMintFirstLogonError "FirstLogon transaction module is missing: $transactionPath"
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
    exit 1
}
. $transactionPath

$runtimePath = Join-Path $payloadDir 'FirstLogon.Runtime.ps1'
if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
    Write-WinMintFirstLogonError "FirstLogon runtime module is missing: $runtimePath"
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
    exit 1
}
. $runtimePath
exit (Invoke-WinMintFirstLogonSetupPhase -AgentMode $AgentMode)
