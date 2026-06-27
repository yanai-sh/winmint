#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Auto','UI','Console','Headless')]
    [string]$AgentMode = 'Auto'
)

$ErrorActionPreference = 'Continue'
# Logs land in ProgramData (Administrators-readable) rather than C:\Windows\Setup\Scripts
# (Users-readable). Setup\Scripts holds the staged agent payload; logs do not belong there.
$bootstrapLogDir = Join-Path $env:ProgramData 'WinMint\Logs'
$null = New-Item -ItemType Directory -Path $bootstrapLogDir -Force -ErrorAction SilentlyContinue
$bootstrapPayloadDir = 'C:\Windows\Setup\Scripts'

$contextPath = Join-Path $bootstrapPayloadDir 'FirstLogon.Context.ps1'
if (-not (Test-Path -LiteralPath $contextPath -PathType Leaf)) {
    "$(Get-Date -Format 'o') FirstLogon context module is missing: $contextPath" | Out-File (Join-Path $bootstrapLogDir 'FirstLogon_errors.log') -Append
    exit 1
}
. $contextPath
Set-WinMintFirstLogonContext -Context (New-WinMintFirstLogonContext @{
        LogDir = $bootstrapLogDir
        PayloadDir = $bootstrapPayloadDir
        EntryPath = $PSCommandPath
        MaxAttempts = 3
        SetupScriptRoot = $bootstrapPayloadDir
    })
$ctx = Get-WinMintFirstLogonContext

$supportPath = Join-Path $ctx.PayloadDir 'FirstLogon.Support.ps1'
if (-not (Test-Path -LiteralPath $supportPath -PathType Leaf)) {
    "$(Get-Date -Format 'o') FirstLogon support module is missing: $supportPath" | Out-File (Join-Path $ctx.LogDir 'FirstLogon_errors.log') -Append
    exit 1
}
. $supportPath
Initialize-WinMintConsoleEncoding
"$(Get-Date -Format 'o') FirstLogon.ps1 start" | Out-File (Join-Path $ctx.LogDir 'FirstLogon.log') -Append
try { Start-Transcript -Path (Join-Path $ctx.LogDir 'FirstLogon_transcript.log') -Append -ErrorAction SilentlyContinue | Out-Null } catch { }

$transactionPath = Join-Path $ctx.PayloadDir 'FirstLogon.Transaction.ps1'
if (-not (Test-Path -LiteralPath $transactionPath -PathType Leaf)) {
    Write-WinMintFirstLogonError "FirstLogon transaction module is missing: $transactionPath"
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
    exit 1
}
. $transactionPath

$runtimePath = Join-Path $ctx.PayloadDir 'FirstLogon.Runtime.ps1'
if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
    Write-WinMintFirstLogonError "FirstLogon runtime module is missing: $runtimePath"
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
    exit 1
}
. $runtimePath
exit (Invoke-WinMintFirstLogonSetupPhase -AgentMode $AgentMode)
