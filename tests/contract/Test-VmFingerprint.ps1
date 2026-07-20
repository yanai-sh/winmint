#Requires -Version 7.6
<#
.SYNOPSIS
    Image fingerprint must include staged setup runtime (image-v2) and Build-And-TestVm
    must prefer the Final ISO path from the verbose build log.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [System.Collections.Generic.List[string]]::new()

function Add-VmFingerprintFailure {
    param([string]$Message)
    $script:failures.Add($Message) | Out-Null
}

$fpText = Get-Content -LiteralPath (Join-Path $root 'tools\vm\lib\VmFingerprint.ps1') -Raw
if ($fpText -notmatch 'schema=image-v2') {
    Add-VmFingerprintFailure 'VmFingerprint image blob must use schema=image-v2.'
}
if ($fpText -notmatch 'setupRuntime=') {
    Add-VmFingerprintFailure 'VmFingerprint image blob must include setupRuntime= so setup script edits bust the ISO cache.'
}
if ($fpText -notmatch 'src\\runtime\\setup') {
    Add-VmFingerprintFailure 'VmFingerprint must hash src\runtime\setup for image fingerprint.'
}

$buildVm = Get-Content -LiteralPath (Join-Path $root 'tools\vm\Build-And-TestVm.ps1') -Raw
if ($buildVm -notmatch 'Final ISO:') {
    Add-VmFingerprintFailure 'Build-And-TestVm.ps1 must prefer Final ISO from the verbose build log.'
}
if ($buildVm -notmatch 'Using Final ISO from build log') {
    Add-VmFingerprintFailure 'Build-And-TestVm.ps1 must log when selecting Final ISO from the build log.'
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}

Write-Host 'VM fingerprint / Final ISO contract: OK'
exit 0
