# WinMint v2 — host tasks (winget install Casey.Just)

set windows-shell := ["pwsh.exe", "-NoProfile", "-Command"]

default:
    @just --list

wizard:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-WinMintWizard.ps1'

restore:
    dotnet restore

build: restore
    dotnet build --no-restore

plan PROFILE="samples/smoke.profile.json" OUT=".scratch/plan":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-WinMintCli.ps1' -- plan '{{PROFILE}}' --out '{{OUT}}'

# Product-curated Profile + bootstrap password (issue #136); distinct from samples/sl7.profile.json.
curated-emit OUT=".scratch/curated":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-WinMintCli.ps1' -- emit-defaults --out '{{OUT}}'

curated-plan OUT=".scratch/curated" PLAN=".scratch/curated-plan": curated-emit
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-WinMintCli.ps1' -- plan '{{OUT}}/winmint.profile.json' --out '{{PLAN}}'

# Pack no-clone toolkit zip + sha256 (win-arm64). Requires a clean worktree and tag vMAJOR.MINOR.PATCH at HEAD.
pack-release TAG:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/release/Compress-WinMintRelease.ps1' -Tag '{{TAG}}'

format-check:
    dotnet format --verify-no-changes

check:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-CheckGate.ps1'

# Discover tests/contract/Test-*.ps1 (WinPE / DISM / release helpers that cannot run on a live host).
contract-tests:
    pwsh -NoProfile -File '{{justfile_directory()}}/tests/contract/Invoke-ContractTests.ps1'

# Live winget/scoop prove → config/packages.proof.json. Not in `just check` (offline proof enforces freshness).
packages-check:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-WinMintCli.ps1' -- packages-check

# Live Microsoft Update Catalog B-release reconcile (25H2/24H2 ARM64). Not in `just check`.
quality-check:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-QualityCheck.ps1'

# SL7 maintainer: quality-check + Source ISO advisory (mounts maintainer ISO). Not in `just check`.
maintainer-check:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-MaintainerCheck.ps1'

bootstrap-contract:
    pwsh -NoProfile -File '{{justfile_directory()}}/tests/contract/Test-BootstrapContract.ps1'

# WinPE decides which disk to erase with no operator present — prove every branch, including refusal.
disk-guard-contract:
    pwsh -NoProfile -File '{{justfile_directory()}}/tests/contract/Test-DiskGuard.ps1'

packages-check-contract:
    pwsh -NoProfile -File '{{justfile_directory()}}/tests/contract/Test-PackagesCheckContract.ps1'

source-media-cache-contract:
    pwsh -NoProfile -File '{{justfile_directory()}}/tests/contract/Test-SourceMediaCache.ps1'

mount-recovery-contract:
    pwsh -NoProfile -File '{{justfile_directory()}}/tests/contract/Test-WinMintMountRecovery.ps1'

release-signing-policy-contract:
    pwsh -NoProfile -File '{{justfile_directory()}}/tests/contract/Test-ReleaseSigningPolicy.ps1'

release-version-contract:
    pwsh -NoProfile -File '{{justfile_directory()}}/tests/contract/Test-ReleaseVersion.ps1'

release-inventory-contract:
    pwsh -NoProfile -File '{{justfile_directory()}}/tests/contract/Test-ReleaseInventory.ps1'

release-contract:
    just release-signing-policy-contract
    just release-version-contract
    just release-inventory-contract

# Install once: Install-Module -Name PSScriptAnalyzer -Scope CurrentUser
analyze-powershell:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-ScriptAnalyzerGate.ps1'

analyze-servicing: analyze-powershell

publish-provisioning:
    dotnet publish src/WinMint.WinPeApply/WinMint.WinPeApply.csproj -c Release -o artifacts/winpe-apply
    dotnet publish src/WinMint.Provisioning/WinMint.Provisioning.csproj -c Release -o artifacts/provisioning

# Admin: Defender exclusions for DISM workdirs.
exclude-scratch ISO="":
    $scratch = Join-Path '{{justfile_directory()}}' '.scratch'; $servicing = Join-Path $env:ProgramData 'WinMint\Servicing'; New-Item -ItemType Directory -Force -Path $scratch, $servicing | Out-Null; $paths = @($scratch, $servicing); if ('{{ISO}}' -ne '') { $paths += '{{ISO}}' }; foreach ($p in $paths) { Add-MpPreference -ExclusionPath $p; Write-Host "Excluded: $p" }

# Admin: discard a leftover install/boot mount after a killed Apply (0xc1420117 / Error 50).
# Does not start Apply. If this still fails: close Explorer on that path, then reboot.
# Recipe body is already pwsh -Command (windows-shell) — do not nest another -Command or $vars vanish.
discard-stale-mount:
    . '{{justfile_directory()}}/servicing/Resolve-WinMintMount.ps1'; $held = Enter-WinMintImageServicingLock; try { Resolve-WinMintStaleMount | ConvertTo-Json -Compress } finally { Exit-WinMintImageServicingLock $held }

# Artifact hygiene under .scratch (or root=…). Also runs after smoke / host-apply / Cli build with -SkipIfBusy.
# Nuclear: just wipe-scratch
clean-artifacts root=".scratch" keep="1" workdirs="1" days="14":
    $root = '{{root}}'; if (-not [System.IO.Path]::IsPathRooted($root)) { $root = Join-Path '{{justfile_directory()}}' $root }; pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-ArtifactHygiene.ps1' -Root $root -KeepIso {{keep}} -KeepWorkDirs {{workdirs}} -MaxAgeDays {{days}}

wipe-scratch:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-ArtifactHygiene.ps1' -Root (Join-Path '{{justfile_directory()}}' '.scratch') -Wipe

# Own-console apply-status watch. Default WORK = Gate B (%LOCALAPPDATA%\WinMint\work\gate-b).
watch-apply WORK="":
    pwsh -NoProfile -NonInteractive -File '{{justfile_directory()}}/tools/host/Watch-Host.ps1' -Kind apply -Work '{{WORK}}'

# Maintainer Apply (DISM hours). Cli verb is build.
# Prereq: just publish-provisioning. INCLUDE_SMOKE_STUBS=true → --include-smoke-stubs.
apply-maintainer ISO WORK PROFILE="samples/smoke.profile.json" INCLUDE_SMOKE_STUBS="false":
    Write-Host 'Maintainer Apply can take multiple hours (DISM I/O). Prefer just check day-to-day.'; $stubs = @(); if ('{{INCLUDE_SMOKE_STUBS}}' -eq 'true') { $stubs = @('--include-smoke-stubs') }; Set-Location '{{justfile_directory()}}'; $args = @('build', '{{PROFILE}}', '--iso', '{{ISO}}', '--work', '{{WORK}}', '--package-audit-strict') + $stubs; & pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-WinMintCli.ps1' -- @args; exit $LASTEXITCODE

# S4 Hyper-V Smoke — not in `just check`. Assert-only: just smoke-assert tests/fixtures/smoke-evidence
# Default Profile = samples/sl7.profile.json (same install target as Primary / this machine).
# Needs .scratch/sl7.password (SECRETS). Longer wall — winget/WSL after Supervisor (offline OOBE default).
# Offline OOBE (default): NIC deferred until Supervisor; ONLINE=1 for legacy always-on Default Switch.
# PowerShell: pass ISO as a positional arg only — not ISO=path. NAME=value overrides are not reliable on Windows;
# use positional WORK WALL MONITOR STALL ONLINE or `smoke-maintainer-monitor` for VMConnect.
# Usage: just smoke 'C:\Users\yanai\Documents\Win11_25H2_English_Arm64_v2.iso'
#        just smoke-maintainer .scratch/smoke 180 1 45 0
smoke ISO WORK=".scratch/smoke" PROFILE="samples/sl7.profile.json" WALL="180" MONITOR="0" STALL="45" ONLINE="0":
    pwsh -NoProfile -NonInteractive -File '{{justfile_directory()}}/tools/vm/Invoke-SmokeRecipe.ps1' -Iso '{{ISO}}' -Work '{{WORK}}' -ProfilePath '{{PROFILE}}' -WallClockMinutes {{WALL}} -StallMinutes {{STALL}} -Monitor '{{MONITOR}}' -OnlineOobe '{{ONLINE}}'

# Maintainer SL7 vanilla Source ISO — tests/fixtures/maintainer-host.json
# Starts elevated via Start-SmokeElevated (Windows Terminal when wt.exe resolves).
smoke-maintainer WORK=".scratch/smoke" WALL="180" MONITOR="0" STALL="45" ONLINE="0":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/vm/Start-SmokeElevated.ps1' -Work '{{WORK}}' -WallClockMinutes {{WALL}} -StallMinutes {{STALL}} -Monitor '{{MONITOR}}' -OnlineOobe '{{ONLINE}}'

# VMConnect during maintainer smoke. ONLINE=1 for online-OOBE escape.
smoke-maintainer-monitor WORK=".scratch/smoke" WALL="180" STALL="45" ONLINE="0":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/vm/Start-SmokeElevated.ps1' -Work '{{WORK}}' -WallClockMinutes {{WALL}} -StallMinutes {{STALL}} -Monitor 1 -OnlineOobe '{{ONLINE}}'

# Own-console host watch (Apply/Smoke keep running if you close it).
# smoke-maintainer already spawns one Watch-Host; use this to attach a second view.
watch-smoke WORK=".scratch/smoke":
    pwsh -NoProfile -NonInteractive -File '{{justfile_directory()}}/tools/host/Watch-Host.ps1' -Kind smoke -Work '{{WORK}}'

# Attach to just check. Default PATH = .scratch/check-status.json. just check does not spawn this.
watch-check PATH="":
    pwsh -NoProfile -NonInteractive -File '{{justfile_directory()}}/tools/host/Watch-Host.ps1' -Kind check -Path '{{PATH}}'

smoke-assert EVIDENCE:
    pwsh -NoProfile -NonInteractive -File '{{justfile_directory()}}/tools/vm/Invoke-Smoke.ps1' -AssertOnly -EvidenceDir '{{EVIDENCE}}'

# S5 Host Apply (pre-wipe). Test lane ≠ Primary. Wipe ISO: just primary-gate <iso> <work>
host-apply ISO WORK=".scratch/sl7-build" PROFILE="samples/sl7.profile.json" QUALITY="Test":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/apply/Invoke-HostApply.ps1' -Iso '{{ISO}}' -Work '{{WORK}}' -Profile '{{PROFILE}}' -ImageQuality '{{QUALITY}}'

# Gate B wipe ISO: Release + package-strict. Workdir survives TEMP toolkit cleanup.
primary-gate ISO WORK="" PROFILE="samples/sl7.profile.json":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/apply/Invoke-PrimaryGate.ps1' -Iso '{{ISO}}' -Work '{{WORK}}' -Profile '{{PROFILE}}'

host-apply-assert WORK=".scratch/sl7-build":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/apply/Invoke-HostApply.ps1' -AssertOnly -WorkDirectory '{{WORK}}' -ExpectDrivers

# Prepared-media isolation (elevated, Source ISO, not in `just check`)
# Usage: just prepared-media-acceptance 'C:\path\Source.iso'
prepared-media-acceptance SOURCE_ISO:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/apply/Invoke-WarmMediaAcceptance.ps1' -SourceIso '{{SOURCE_ISO}}'

warm-media-acceptance SOURCE_ISO:
    just prepared-media-acceptance '{{SOURCE_ISO}}'

# Prepared-media Apply timings (elevated, Source ISO, not in `just check`)
# Usage: just bench-prepared-media 'C:\path\Source.iso' 'C:\path\to\baseline'
bench-prepared-media SOURCE_ISO BASELINE="":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/bench/Measure-WarmMedia.ps1' -SourceIso '{{SOURCE_ISO}}' -BaselineWorktree '{{BASELINE}}'

bench-warm-media SOURCE_ISO BASELINE="":
    just bench-prepared-media '{{SOURCE_ISO}}' '{{BASELINE}}'

# Wipe-lane assert only (fails on Test evidence).
primary-gate-assert WORK="":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/apply/Invoke-PrimaryGate.ps1' -AssertOnly -Work '{{WORK}}'

# Operator walkthrough for the Primary wipe path. Elevate to let it drive the gate.
primary-gate-wizard:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/apply/Invoke-PrimaryGateWizard.ps1'
