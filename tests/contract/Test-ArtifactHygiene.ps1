#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Assert-HygieneHook([string] $Path, [string] $Label) {
    $text = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    if ($text -notmatch 'Invoke-WinMintScratchHygiene') {
        throw "$Label must call Invoke-WinMintScratchHygiene"
    }
}

Assert-HygieneHook (Join-Path $repo 'tools\vm\Invoke-Smoke.ps1') 'Invoke-Smoke'
Assert-HygieneHook (Join-Path $repo 'tools\apply\Invoke-HostApply.ps1') 'Invoke-HostApply'
$cli = Get-Content -LiteralPath (Join-Path $repo 'tools\host\Invoke-WinMintCli.ps1') -Raw -Encoding utf8
if ($cli -notmatch 'Invoke-WinMintScratchHygiene') { throw 'Invoke-WinMintCli must invoke hygiene after build' }
if ($cli -notmatch "cliArgs\[0\] -eq 'build'") { throw 'Invoke-WinMintCli must hygiene only the build verb' }

$hygiene = Get-Content -LiteralPath (Join-Path $repo 'tools\host\Invoke-ArtifactHygiene.ps1') -Raw -Encoding utf8
if ($hygiene -notmatch 'SkipIfBusy') { throw 'hygiene script must support -SkipIfBusy' }
if ($hygiene -notmatch 'Test-WinMintImageServicingBusy') { throw 'hygiene must probe servicing busy' }
if ($hygiene -notmatch '\[int\] \$KeepIso = 1') { throw 'scratch hygiene default KeepIso must be 1' }
if ($hygiene -notmatch '-KeepIso 1') { throw 'Invoke-WinMintScratchHygiene must pass KeepIso 1' }

$resolve = Get-Content -LiteralPath (Join-Path $repo 'tools\Resolve-OutputIso.ps1') -Raw -Encoding utf8
if ($resolve -notmatch 'function Clear-WinMintPriorOutputIsos') { throw 'Resolve-OutputIso must define Clear-WinMintPriorOutputIsos' }

$smoke = Get-Content -LiteralPath (Join-Path $repo 'tools\vm\Invoke-Smoke.ps1') -Raw -Encoding utf8
if ($smoke -notmatch 'Clear-WinMintPriorOutputIsos') { throw 'Invoke-Smoke must clear prior Output ISOs before Apply' }
$hostApply = Get-Content -LiteralPath (Join-Path $repo 'tools\apply\Invoke-HostApply.ps1') -Raw -Encoding utf8
if ($hostApply -notmatch 'Clear-WinMintPriorOutputIsos') { throw 'Invoke-HostApply must clear prior Output ISOs before Apply' }

$just = Get-Content -LiteralPath (Join-Path $repo 'Justfile') -Raw -Encoding utf8
if ($just -notmatch 'clean-artifacts root="\.scratch" keep="1"') { throw 'just clean-artifacts default keep must be 1' }

# Behavioural: Clear-WinMintPriorOutputIsos drops surplus leaves, keeps one.
. (Join-Path $repo 'tools\Resolve-OutputIso.ps1')
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("winmint-prior-iso-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $keep = Join-Path $tmp 'winmint_sl7_Test_20261005-120000.iso'
    Set-Content -LiteralPath $keep -Value 'keep'
    Set-Content -LiteralPath (Join-Path $tmp 'winmint_sl7_Test_20260928-083807.iso') -Value 'drop'
    Set-Content -LiteralPath (Join-Path $tmp 'out.iso') -Value 'legacy'
    $n = Clear-WinMintPriorOutputIsos -WorkDirectory $tmp -KeepPath $keep
    if ($n -ne 2) { throw "Clear-WinMintPriorOutputIsos removed $n; expected 2" }
    if (-not (Test-Path -LiteralPath $keep)) { throw 'kept Output ISO was deleted' }
    if (@(Get-ChildItem -LiteralPath $tmp -Filter '*.iso').Count -ne 1) { throw 'expected exactly one Output ISO after clear' }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

& pwsh -NoProfile -File (Join-Path $repo 'tools\host\Invoke-ArtifactHygiene.ps1') -SelfCheck
if ($LASTEXITCODE -ne 0) { throw "Artifact hygiene SelfCheck failed: $LASTEXITCODE" }
Write-Output 'Test-ArtifactHygiene ok'
exit 0
