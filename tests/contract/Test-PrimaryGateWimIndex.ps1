#requires -Version 7.6
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools\host\Get-WinMintDefaultWimIndex.ps1')

if ((Get-WinMintDefaultWimIndex -EditionId 'Core') -ne 1) { throw 'Core must map to Home index 1' }
if ((Get-WinMintDefaultWimIndex -EditionId 'CoreN') -ne 1) { throw 'CoreN must map to Home index 1' }
if ((Get-WinMintDefaultWimIndex -EditionId 'Professional') -ne 3) { throw 'Professional must map to Pro index 3' }
if ((Get-WinMintDefaultWimIndex -EditionId 'ProfessionalN') -ne 3) { throw 'ProfessionalN must map to Pro index 3' }
if ((Get-WinMintDefaultWimIndex -EditionId 'Pro') -ne 3) { throw 'Pro must map to Pro index 3' }
if ((Get-WinMintDefaultWimIndex -EditionId 'Enterprise') -ne 1) { throw 'non-Pro SKUs default to Home index 1' }

$hostApply = Get-Content -LiteralPath (Join-Path $repo 'tools\apply\Invoke-HostApply.ps1') -Raw -Encoding utf8
if ($hostApply -notmatch '\[int\] \$WimIndex = 0') { throw 'Invoke-HostApply missing -WimIndex param' }
if ($hostApply -notmatch "\-\-wim-index") { throw 'Invoke-HostApply must emit --wim-index when set' }
if ($hostApply -notmatch '\$WimIndex -gt 0') { throw 'Invoke-HostApply must omit --wim-index when WimIndex is 0' }

$gate = Get-Content -LiteralPath (Join-Path $repo 'tools\apply\Invoke-PrimaryGate.ps1') -Raw -Encoding utf8
if ($gate -notmatch 'Get-WinMintDefaultWimIndex') { throw 'PrimaryGate must resolve host-edition WimIndex' }
if ($gate -notmatch '\-WimIndex \$resolvedWimIndex') { throw 'PrimaryGate must forward resolved WimIndex to HostApply' }

$wizard = Get-Content -LiteralPath (Join-Path $repo 'tools\apply\Invoke-PrimaryGateWizard.ps1') -Raw -Encoding utf8
if ($wizard -notmatch "primary-gate") { throw 'PrimaryGateWizard must invoke primary-gate' }
# Wizard calls just primary-gate without hardcoding index 3 — host default applies.
if ($wizard -match '(?i)wim-index[= ].*3|--wim-index.*\b3\b|-WimIndex\s+3') {
    throw 'PrimaryGateWizard must not hardcode Pro WimIndex 3'
}

$justfile = Get-Content -LiteralPath (Join-Path $repo 'Justfile') -Raw -Encoding utf8
if ($justfile -match "apply-smoke-maintainer[\s\S]{0,400}--wim-index") {
    throw 'Smoke apply must keep omitting --wim-index (Cli Pro default)'
}

Write-Output 'Test-PrimaryGateWimIndex ok'
exit 0
