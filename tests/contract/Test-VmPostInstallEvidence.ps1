#Requires -Version 7.6
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'tools\vm\lib\VmPostInstallEvidence.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Fail([string]$Message) { $script:failures.Add($Message) | Out-Null }

$okState = [pscustomobject]@{
    steps = [pscustomobject]@{
        'module:profiles'          = [pscustomobject]@{ status = 'ok' }
        'module:package-managers'  = [pscustomobject]@{ status = 'ok' }
        'module:wsl'               = [pscustomobject]@{ status = 'skipped' }
        'module:launcher-key'      = [pscustomobject]@{ status = 'ok' }
    }
}
$stepOk = Test-WinMintVmFirstLogonRequiredSteps -AgentState $okState
if (-not $stepOk.plumbingOk) {
    Add-Fail "expected required steps ok/skipped; failures=$($stepOk.plumbingFailures -join '|')"
}

$badState = [pscustomobject]@{
    steps = [pscustomobject]@{
        'module:profiles' = [pscustomobject]@{ status = 'failed' }
    }
}
$stepBad = Test-WinMintVmFirstLogonRequiredSteps -AgentState $badState
if ($stepBad.plumbingOk) {
    Add-Fail 'failed profiles step should fail plumbing'
}

$diskOff = Test-WinMintVmDiskLayoutEvidence -Probe ([pscustomobject]@{
        windowsPresent = $true
        winrePresent   = $false
        devDriveLabel  = $false
        vhdPresent     = $false
    }) -DiskMode 'AutoWipeDisk0' -DevDriveMode 'Off'
if (-not $diskOff.plumbingOk) {
    Add-Fail 'AutoWipe with Windows present should pass disk plumbing'
}

$diskVhdFail = Test-WinMintVmDiskLayoutEvidence -Probe ([pscustomobject]@{
        windowsPresent = $true
        winrePresent   = $true
        devDriveLabel  = $false
        vhdPresent     = $false
    }) -DiskMode 'AutoWipeDisk0' -DevDriveMode 'VhdDynamic'
if ($diskVhdFail.plumbingOk) {
    Add-Fail 'VhdDynamic without VHDX/label should fail disk plumbing'
}

$probeScript = Get-WinMintVmDiskLayoutProbeScript
if ($probeScript -notmatch 'DevDrive' -or $probeScript -notmatch 'WinMint\.vhdx') {
    Add-Fail 'disk layout probe script should look for DevDrive label and WinMint.vhdx'
}

if ($failures.Count -gt 0) {
    throw "VmPostInstallEvidence contract failed:`n$($failures -join "`n")"
}
Write-Host 'VM post-install evidence contract: OK'
