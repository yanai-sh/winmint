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

& pwsh -NoProfile -File (Join-Path $repo 'tools\host\Invoke-ArtifactHygiene.ps1') -SelfCheck
if ($LASTEXITCODE -ne 0) { throw "Artifact hygiene SelfCheck failed: $LASTEXITCODE" }
Write-Output 'Test-ArtifactHygiene ok'
exit 0
