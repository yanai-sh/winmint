#requires -Version 7.6
<#
.SYNOPSIS
  Walks a human through the Primary (SL7) wipe path, one stage at a time.
.NOTES
  Host tool, not a gate. Remembers answers in .scratch/primary-gate.env so a
  multi-day metal run can stop at any stage and resume.

  Run elevated to let the wizard drive `just primary-gate` / `primary-gate-assert`
  itself and read the verdict from the exit code. Unelevated it prints the same
  commands and asks you to run them, which is the weaker path: the operator, not
  the gate, decides what "green" meant.
#>
[CmdletBinding()]
param(
    [string] $EnvFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $repoRoot
. (Join-Path $repoRoot 'tools\AcceptanceManifest.ps1')

if (-not $EnvFile) { $EnvFile = Join-Path $repoRoot '.scratch\primary-gate.env' }

$TotalStages = 9
$script:StageIndex = 0
$script:Answers = [ordered]@{}

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]::new($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Import-Answer {
    if (-not (Test-Path -LiteralPath $EnvFile)) { return }
    foreach ($line in Get-Content -LiteralPath $EnvFile) {
        if ($line -match '^\s*([A-Z_][A-Z0-9_]*)=(.*)$') {
            $script:Answers[$Matches[1]] = $Matches[2]
        }
    }
}

function Save-Answer {
    param([Parameter(Mandatory)][string] $Key, [string] $Value)
    $script:Answers[$Key] = $Value
    $dir = Split-Path -Parent $EnvFile
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $lines = foreach ($k in $script:Answers.Keys) { "$k=$($script:Answers[$k])" }
    Set-Content -LiteralPath $EnvFile -Value $lines -Encoding utf8NoBOM
    Write-Host "  + saved $Key -> $EnvFile" -ForegroundColor Green
}

function Show-Stage {
    param([Parameter(Mandatory)][string] $Name)
    if (-not [Console]::IsOutputRedirected) { Clear-Host }
    $script:StageIndex++
    Write-Host ''
    Write-Host "> Stage $script:StageIndex/$TotalStages - $Name" -ForegroundColor Blue
    Write-Host ''
}

function Write-Say { param([string] $Text) Write-Host "  $Text" }
function Write-Step { param([string] $Text) Write-Host "  * $Text" -ForegroundColor Cyan }
function Write-Note { param([string] $Text) Write-Host "  $Text" -ForegroundColor DarkGray }
function Write-Warn { param([string] $Text) Write-Host "  ! $Text" -ForegroundColor Yellow }
function Write-Good { param([string] $Text) Write-Host "  + $Text" -ForegroundColor Green }

function Wait-Human {
    param([string] $Message = 'Press Enter to continue')
    Write-Host "  $Message " -ForegroundColor DarkGray -NoNewline
    [void](Read-Host)
}

function Confirm-Yes {
    param([Parameter(Mandatory)][string] $Question)
    Write-Host "  ? $Question [y/N] " -ForegroundColor Yellow -NoNewline
    return ((Read-Host) -match '^\s*[Yy]')
}

function Read-Answer {
    param([Parameter(Mandatory)][string] $Key, [Parameter(Mandatory)][string] $Prompt)
    $current = if ($script:Answers.Contains($Key)) { $script:Answers[$Key] } else { '' }
    if ($current) {
        Write-Host "  $Prompt " -NoNewline
        Write-Host "[Enter keeps $current] " -ForegroundColor DarkGray -NoNewline
    }
    else {
        Write-Host "  $Prompt " -NoNewline
    }
    $answer = Read-Host
    if (-not $answer -and $current) { $answer = $current }
    return $answer
}

function Get-JsonValue {
    param($Object, [Parameter(Mandatory)][string] $Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

# Invoke-Gate — run a just recipe when elevated (exit code is the verdict), or
# print it and fall back to the operator's word when not.
function Invoke-Gate {
    param(
        [Parameter(Mandatory)][string[]] $JustArgs,
        [Parameter(Mandatory)][string] $ConfirmQuestion
    )
    $rendered = 'just ' + (($JustArgs | ForEach-Object { if ($_ -match '\s') { """$_""" } else { $_ } }) -join ' ')
    Write-Step $rendered
    if (-not (Test-Elevated)) {
        Write-Warn 'This shell is not elevated - run that in an elevated pwsh.'
        return (Confirm-Yes $ConfirmQuestion)
    }
    if (-not (Get-Command just -ErrorAction SilentlyContinue)) {
        Write-Warn 'just is not on PATH (winget install Casey.Just) - run it yourself.'
        return (Confirm-Yes $ConfirmQuestion)
    }
    & just @JustArgs
    $code = $LASTEXITCODE
    if ($code -eq 0) { return $true }
    Write-Warn "exit code $code"
    return $false
}

Import-Answer

# ── Banner ──────────────────────────────────────────────────────────────────
if (-not [Console]::IsOutputRedirected) { Clear-Host }
Write-Host ''
Write-Host '  WinMint Primary wipe path' -ForegroundColor Blue
Write-Host "  $TotalStages stages" -ForegroundColor DarkGray
Write-Host ''
Write-Note 'This wizard tells you what to do and captures what you copy back.'
Write-Note "Stop any time with Ctrl-C - answers so far are kept in $EnvFile."
if (Test-Elevated) {
    Write-Good 'Elevated - the wizard will run the gate and read its exit code.'
}
else {
    Write-Warn 'Not elevated - you will run the gate yourself and report the result.'
}
Wait-Human 'Ready to start?'

# ── Stage 1: Restore path ───────────────────────────────────────────────────
Show-Stage 'Restore path'
Write-Say 'Before the destructive install, have a restore path for THIS PC ready.'
Write-Say 'This is operator hygiene, not a WinMint feature - WinMint never downloads'
Write-Say 'or ships recovery images (see README).'
Start-Process 'https://support.microsoft.com/surfacerecoveryimage'
Write-Step 'Surface: grab a serial-matched recovery image (BMR) from the page just opened.'
Write-Note "Not a Surface? Use your PC maker's OEM recovery site, or a Windows recovery drive."
Write-Note 'Maintainer note: a local serial-matched BMR (e.g. under Downloads) is fine for'
Write-Note 'this device - just never commit or link that file in the repo.'
if (-not (Confirm-Yes 'Restore path ready for this PC?')) {
    Write-Warn 'Get a restore path sorted first - re-run this wizard when ready.'
    exit 1
}

# ── Stage 2: Password file ──────────────────────────────────────────────────
Show-Stage 'Password file'
$passwordPath = Join-Path $repoRoot '.scratch\sl7.password'
Write-Say 'samples/sl7.profile.json expects account.passwordPath to resolve to'
Write-Say '  .scratch/sl7.password'
Write-Say "(WinMint never prints or logs this file's contents.)"
if (-not (Test-Path -LiteralPath $passwordPath -PathType Leaf)) {
    Write-Warn '.scratch/sl7.password not found.'
    Write-Step "Create it: Set-Content -LiteralPath '$passwordPath' -Value 'yourpassword' -NoNewline"
    Wait-Human 'Press Enter once the file exists'
}
if (Test-Path -LiteralPath $passwordPath -PathType Leaf) {
    Write-Good '.scratch/sl7.password exists'
}
else {
    Write-Warn 'still missing - the build will fail without it. Continuing anyway.'
}

# ── Stage 3: Source ISO ─────────────────────────────────────────────────────
Show-Stage 'Source ISO'
Write-Say 'Point at the official Microsoft Source ISO for this build (ADR-001 - WinMint'
Write-Say 'never downloads or redistributes Windows media).'
$sourceIso = Read-Answer 'SOURCE_ISO' 'Path to Source ISO:'
Save-Answer 'SOURCE_ISO' $sourceIso
if ($sourceIso -and (Test-Path -LiteralPath $sourceIso -PathType Leaf)) {
    Write-Good "found: $sourceIso"
}
else {
    Write-Warn 'That path does not resolve - fix it before Gate B.'
}

# ── Stage 4: Gate B + wipe ISO (one Release + package-strict Apply) ─────────
Show-Stage 'Gate B + wipe ISO'
Write-Say 'Run Primary once (Release + package-strict). This is DISM hours, not minutes.'
$gateWork = Read-Answer 'GATE_WORK' 'Gate B workdir (Enter for the default):'
if (-not $gateWork) { $gateWork = Join-Path $env:LOCALAPPDATA 'WinMint\work\sl7-primary' }
Save-Answer 'GATE_WORK' $gateWork
Write-Note "Arguments are positional - 'just primary-gate ISO=... WORK=...' passes the"
Write-Note 'NAME= prefix through as part of the value and the run dies on a bad path.'
if (-not (Invoke-Gate -JustArgs @('primary-gate', $sourceIso, $gateWork) `
            -ConfirmQuestion 'Did that build finish without error?')) {
    Write-Warn 'The build did not succeed - do not flash a USB. Fix it, then re-run.'
    exit 1
}

# A workdir full of evidence is not a green gate: a build can carry a complete
# apply-acceptance.json and still be media the assert refuses (a pre-guard
# LaunchApply.cmd erasing disk 0 is the case that motivated this). Ask the gate.
Write-Say 'Evidence on disk is not a verdict. Let the gate decide:'
if (-not (Invoke-Gate -JustArgs @('primary-gate-assert', $gateWork) `
            -ConfirmQuestion "Did it print 'Host Apply acceptance OK' and exit 0?")) {
    Write-Warn 'Gate B is not green - do not flash a USB.'
    exit 1
}
Write-Good 'Gate B assert passed'

$wipeIso = $null
$wipeSha = $null
$evidencePath = Join-Path $gateWork 'evidence.json'
if (Test-Path -LiteralPath $evidencePath -PathType Leaf) {
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    $wipeIso = Get-JsonValue $evidence 'outputIsoPath'
    $wipeSha = Get-JsonValue (Get-JsonValue $evidence 'digests') 'outputIso.sha256'
}
if (-not $wipeIso -or -not (Test-Path -LiteralPath $wipeIso -PathType Leaf)) {
    $newest = Get-ChildItem -LiteralPath $gateWork -Filter 'winmint_*.iso' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($newest) { $wipeIso = $newest.FullName }
}
if (-not $wipeIso -or -not (Test-Path -LiteralPath $wipeIso -PathType Leaf)) {
    Write-Warn "No output ISO under $gateWork - do not flash a USB yet."
    exit 1
}
Write-Good "wipe ISO: $wipeIso"
Save-Answer 'WIPE_ISO' $wipeIso
if ($wipeSha) { Save-Answer 'WIPE_SHA' $wipeSha }

# ── Stage 5: USB write ──────────────────────────────────────────────────────
Show-Stage 'USB write'
if ($wipeSha) {
    Write-Say 'Checking the ISO against the digest the gate recorded...'
    $actual = (Get-FileHash -LiteralPath $wipeIso -Algorithm SHA256).Hash
    if ($actual -ieq $wipeSha) {
        Write-Good "SHA-256 matches evidence: $actual"
    }
    else {
        Write-Warn 'SHA-256 MISMATCH - this ISO is not the one the gate accepted.'
        Write-Note "evidence  $wipeSha"
        Write-Note "on disk   $actual"
        exit 1
    }
}
Write-Say 'Flash this ISO - and only this one - with Rufus DD (or another honest writer):'
Write-Step $wipeIso
Wait-Human 'Press Enter once the USB is flashed and ready'

# ── Stage 6: Destructive install ────────────────────────────────────────────
Show-Stage 'Destructive install'
Write-Warn 'This step WIPES the primary Surface Laptop 7. It is irreversible.'
if (-not (Confirm-Yes 'Restore path confirmed AND you intend to wipe this PC now?')) {
    Write-Warn "Stopping - re-run this wizard when you're ready."
    exit 1
}
Wait-Human 'Boot the SL7 from the USB and start the WinPE apply. Press Enter once it is running'
if (-not (Confirm-Yes 'Apply completed and the machine rebooted into OOBE/FirstLogon?')) {
    Write-Warn 'Apply did not complete cleanly - investigate before calling this gate met.'
}

# ── Stage 7: FirstLogon watch ───────────────────────────────────────────────
Show-Stage 'FirstLogon watch'
Write-Say 'Watch FirstLogon on the SL7 and confirm each of these in order:'
Write-Step 'splash appears'
Write-Step 'DMA settle reaches green (hard fields)'
Write-Step 'AppX safetyNet completes online (session not Failed)'
Write-Step 'deprovisioned marks present for remove-list AppX (safetyNet / AppxAllUserStore)'
Write-Step 'curated packages install under --package-strict: Cursor, Zen, WSL Fedora'
Write-Step 'shell core: pwsh + Terminal + scoop toolbox + shell.stamp'
Write-Step 'Explorer unlock happens'
Wait-Human 'Press Enter once you have watched FirstLogon through to Explorer unlock'

# ── Stage 8: Evidence copy-off ──────────────────────────────────────────────
Show-Stage 'Evidence copy-off'
Write-Say 'Copy %ProgramData%\WinMint\evidence\ off the SL7 before doing anything else.'
$evidenceDir = Read-Answer 'EVIDENCE_DIR' 'Where did you copy the evidence to (path on this machine):'
Save-Answer 'EVIDENCE_DIR' $evidenceDir

# ── Stage 9: Checklist assert ───────────────────────────────────────────────
Show-Stage 'Checklist assert'
Write-Say 'Eyeball packages.evidence.json in the copied evidence and confirm it shows'
Write-Say 'the curated packages (Cursor, Zen, WSL Fedora) green with no failures.'
Write-Say 'Also confirm FU posture still present after FirstLogon:'
Write-Step 'HKLM ...\CloudContent\DisableWindowsConsumerFeatures = 1'
Write-Step 'HKLM ...\CloudContent\DisableSoftLanding = 1'
Write-Step 'HKLM ...\WindowsStore\AutoDownload = 2'
Write-Note 'True FU survival needs a later Feature Update + re-check - record the baseline now.'
if (Confirm-Yes 'packages.evidence.json green AND FU HKLM baseline present?') {
    Write-Good 'Primary wipe path looks met - attach evidence in-repo when ready.'
    if (-not (Test-Path -LiteralPath $evidenceDir -PathType Container)) {
        throw "Primary evidence copy directory not found: $evidenceDir"
    }
    $evidenceFull = (Resolve-Path -LiteralPath $evidenceDir).Path
    $gateFull = (Resolve-Path -LiteralPath $gateWork).Path
    if ($evidenceFull -eq $gateFull -or $evidenceFull.StartsWith($gateFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Primary evidence must be copied from outside the Gate B workdir'
    }
    if ($evidenceFull -match '(?i)(^|[\\/])tests[\\/]fixtures([\\/]|$)|(^|[\\/])fixture[^\\/]*([\\/]|$)') {
        throw 'Fixture evidence cannot support Primary'
    }
    $gateManifestPath = Join-Path $gateWork 'apply-acceptance.json'
    if (-not (Test-Path -LiteralPath $gateManifestPath -PathType Leaf)) {
        throw 'Gate B acceptance manifest is missing'
    }
    $gateManifest = Get-Content -LiteralPath $gateManifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ([string]$gateManifest.schemaVersion -cne 'winmint.apply.acceptance/v1' -or
        [string]$gateManifest.lane -cne 'Release' -or
        $gateManifest.preWipeOnly -ne $true) {
        throw 'Gate B manifest must be a Release pre-wipe acceptance result'
    }

    # The manifest must bind the evidence actually copied off-box, not merely
    # trust arbitrary JSON that happens to contain a known schema.
    $copiedEvidenceRoot = Join-Path $gateWork 'primary-evidence'
    if (Test-Path -LiteralPath $copiedEvidenceRoot) {
        Remove-Item -LiteralPath $copiedEvidenceRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $copiedEvidenceRoot | Out-Null
    $copiedArtifacts = @()
    $copiedSchemas = @()
    foreach ($sourceFile in Get-ChildItem -LiteralPath $evidenceDir -Filter '*.json' -File -Recurse -ErrorAction Stop) {
        $relative = [IO.Path]::GetRelativePath((Resolve-Path $evidenceDir).Path, $sourceFile.FullName).Replace('\', '/')
        $artifact = Normalize-WinMintArtifactPath ("primary-evidence/$relative")
        $target = Join-Path $copiedEvidenceRoot ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if ($artifact -match '(?i)(^|/)(password|secret|credential)([^/]*)(/|$)|(?i)(^|/)[^/]*\.(password|secret|pem|pfx|key)$') {
            throw "Primary evidence path is not safe to copy: $relative"
        }
        $targetParent = Split-Path -Parent $target
        New-Item -ItemType Directory -Force -Path $targetParent | Out-Null
        Copy-Item -LiteralPath $sourceFile.FullName -Destination $target -Force
        $copiedArtifacts += $artifact
        try {
            $doc = Get-Content -LiteralPath $target -Raw -Encoding utf8 | ConvertFrom-Json
            $schema = [string]$doc.schemaVersion
            if ($script:WinMintAcceptanceKnownSchemas -contains $schema) {
                $copiedSchemas += $schema
            }
        }
        catch {
            throw "Copied Primary evidence is not valid JSON: $relative"
        }
    }
    $copiedSchemas = @($copiedSchemas | Sort-Object -Unique)
    if ($copiedSchemas -notcontains 'winmint.provisioning.evidence/v1') {
        throw 'Primary evidence copy lacks live provisioning evidence'
    }
    if ($copiedSchemas -notcontains 'winmint.packages.evidence/v1') {
        throw 'Primary evidence copy lacks package-strict package evidence'
    }
    $liveProvisioning = Get-ChildItem -LiteralPath $copiedEvidenceRoot -Filter '*.json' -File -Recurse |
        Where-Object {
            try {
                $doc = Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8 | ConvertFrom-Json
                [string]$doc.schemaVersion -eq 'winmint.provisioning.evidence/v1' -and
                    [string]$doc.outcome -eq 'Complete'
            }
            catch { $false }
        }
    if (-not $liveProvisioning) { throw 'Primary evidence lacks a complete live provisioning run' }
    $packageEvidence = Get-ChildItem -LiteralPath $copiedEvidenceRoot -Filter '*.json' -File -Recurse |
        Where-Object {
            try {
                $doc = Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8 | ConvertFrom-Json
                [string]$doc.schemaVersion -eq 'winmint.packages.evidence/v1' -and @($doc.failures).Count -eq 0
            }
            catch { $false }
        }
    if (-not $packageEvidence) { throw 'Primary package evidence contains failures or is unreadable' }
    $primarySchemas = @('winmint.image.evidence/v1') + $copiedSchemas | Sort-Object -Unique
    $gateEvidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    if ([string]$gateEvidence.schemaVersion -cne 'winmint.image.evidence/v1') {
        throw 'Gate B evidence is not image evidence'
    }
    $primaryDigest = Get-JsonValue (Get-JsonValue $gateEvidence 'digests') 'outputIso.sha256'
    $primarySourceSha = Get-JsonValue (Get-JsonValue $gateEvidence 'digests') 'source.isoSha256'
    $primarySourceLength = [long](Get-JsonValue (Get-JsonValue $gateEvidence 'digests') 'source.isoLength')
    $primaryOutput = if ($wipeIso) { $wipeIso } else { $null }
    $primaryRoot = (Resolve-Path $gateWork).Path
    $primaryOutputRelative = [IO.Path]::GetRelativePath($primaryRoot, (Resolve-Path $primaryOutput).Path).Replace('\', '/')
    $primaryArtifacts = @($primaryOutputRelative, 'evidence.json', 'apply-acceptance.json') + $copiedArtifacts
    Write-WinMintAcceptanceManifest -Path (Join-Path $gateWork 'primary.acceptance.manifest.json') `
        -AcceptanceKind Primary -Outcome green -Lane Release -RepositoryRoot $repoRoot `
        -ProfilePath 'samples/sl7.profile.json' -SourceIsoPath $sourceIso -OutputIsoPath $primaryOutput `
        -SourceIsoSha256 $primarySourceSha -SourceIsoLength $primarySourceLength `
        -OutputIsoSha256 $primaryDigest -SourceEvidenceSchemas $primarySchemas `
        -ArtifactPaths $primaryArtifacts `
        -PackageStrict $true
}
else {
    Write-Warn 'Not green - do not treat Primary as proven without install evidence.'
}

Write-Host ''
Write-Host '  Done.' -ForegroundColor Green
Write-Note "answers kept in $EnvFile"
Write-Host ''
