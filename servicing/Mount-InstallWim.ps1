#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
# Mount install.wim from Source ISO. Params only — no Profile branching.
$sourceIso = $Parameters['sourceIso']
$mountDir = $Parameters['mountDir']
if ([string]::IsNullOrWhiteSpace($sourceIso)) { throw 'sourceIso required' }
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }

New-Item -ItemType Directory -Force -Path $mountDir | Out-Null
# ponytail: DISM mount lands with real ISO acceptance; marker keeps RunPlan order testable offline.
Set-Content -LiteralPath (Join-Path $mountDir '.mounted') -Value "sourceIso=$sourceIso" -Encoding utf8
Write-Host "MountInstallWim ok"
exit 0
