#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$inventory = Join-Path $repo 'tools/release/Get-WinMintReleaseInventory.ps1'

$root = Join-Path ([IO.Path]::GetTempPath()) ('winmint-inv-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $root 'bin\cli'), (Join-Path $root 'bin\wizard'), (Join-Path $root 'artifacts\provisioning'), (Join-Path $root 'artifacts\winpe-apply'), (Join-Path $root 'servicing'), (Join-Path $root 'tools\apply') | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $root 'bin\cli\WinMint.Cli.exe') -Value 'cli' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $root 'bin\cli\WinMint.Contracts.dll') -Value 'contracts' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $root 'bin\cli\coreclr.dll') -Value 'runtime' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $root 'bin\wizard\WinMint.Wizard.exe') -Value 'wiz' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $root 'artifacts\provisioning\WinMint.Provisioning.exe') -Value 'prov' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $root 'artifacts\winpe-apply\WinMintApply.exe') -Value 'winpe' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $root 'servicing\Mount-InstallWim.ps1') -Value '# kernel' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $root 'Justfile') -Value 'check:' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $root 'config.json') -Value '{}' -Encoding ascii

    $doc = & $inventory -StageRoot $root -Tag 'v1.2.3' -Phase Unsigned
    $byPath = @{}
    foreach ($f in $doc.files) { $byPath[$f.path] = $f }
    if ($byPath['bin/cli/WinMint.Cli.exe'].class -cne 'winmint-pe') { throw 'cli class' }
    if ($byPath['artifacts/winpe-apply/WinMintApply.exe'].class -cne 'winmint-pe') { throw 'winpe helper class' }
    if (-not $byPath['artifacts/winpe-apply/WinMintApply.exe'].signingCandidate) { throw 'winpe helper should be a signing candidate' }
    if (-not $byPath['bin/cli/WinMint.Cli.exe'].signingCandidate) { throw 'cli should be a signing candidate' }
    if ($byPath['bin/cli/coreclr.dll'].class -cne 'upstream-pe') { throw 'upstream class' }
    if ($byPath['bin/cli/coreclr.dll'].signingCandidate) { throw 'upstream must not be a signing candidate' }
    if ($byPath['servicing/Mount-InstallWim.ps1'].class -cne 'winmint-powershell') { throw 'ps1 class' }
    if ($byPath['servicing/Mount-InstallWim.ps1'].signingCandidate) { throw 'ps1 signing is gated on provider confirmation' }
    if ($byPath['Justfile'].class -cne 'hash-only') { throw 'Justfile class' }

    $psSigned = & $inventory -StageRoot $root -Tag 'v1.2.3' -Phase Unsigned -AllowPowerShellSigning
    $psFile = @($psSigned.files | Where-Object { $_.path -eq 'servicing/Mount-InstallWim.ps1' })[0]
    if (-not $psFile.signingCandidate) { throw 'AllowPowerShellSigning did not mark scripts' }

    Set-Content -LiteralPath (Join-Path $root 'unknown.exe') -Value 'nope' -Encoding ascii
    $unknownThrew = $false
    try { & $inventory -StageRoot $root -Tag 'v1.2.3' -Phase Unsigned | Out-Null }
    catch {
        $unknownThrew = $true
        if ([string]$_.Exception.Message -notmatch 'unknown executable') { throw }
    }
    if (-not $unknownThrew) { throw 'unknown executable was classified' }
    Remove-Item -LiteralPath (Join-Path $root 'unknown.exe') -Force

    Set-Content -LiteralPath (Join-Path $root 'sneaky.ps1') -Value 'nope' -Encoding ascii
    $scriptThrew = $false
    try { & $inventory -StageRoot $root -Tag 'v1.2.3' -Phase Unsigned | Out-Null }
    catch {
        $scriptThrew = $true
        if ([string]$_.Exception.Message -notmatch 'unknown script') { throw }
    }
    if (-not $scriptThrew) { throw 'unknown script was classified' }

    $compress = Get-Content -LiteralPath (Join-Path $repo 'tools/release/Compress-WinMintRelease.ps1') -Raw
    if ($compress -match 'dotnet') { throw 'Compress-WinMintRelease must not invoke dotnet' }

    $zipDir = Join-Path ([IO.Path]::GetTempPath()) ('winmint-inv-out-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $zipDir | Out-Null
    try {
        & (Join-Path $repo 'tools/release/Compress-WinMintRelease.ps1') -Tag v1.2.3 -StageRoot $root -OutDir $zipDir
        $shaFile = Join-Path $zipDir 'WinMint-v1.2.3.zip.sha256'
        $shaText = Get-Content -LiteralPath $shaFile -Raw
        if ($shaText -notmatch '^[0-9a-f]{64}  WinMint-v1\.2\.3\.zip$') { throw "hash format: $shaText" }
    }
    finally {
        Remove-Item -LiteralPath $zipDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Test-ReleaseInventory ok'
