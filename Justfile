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

# Pack no-clone toolkit zip + sha256 (win-arm64). Requires a clean worktree and tag vMAJOR.MINOR.PATCH at HEAD.
pack-release TAG:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/release/Compress-WinMintRelease.ps1' -Tag '{{TAG}}'

format-check:
    dotnet format --verify-no-changes

check: format-check build
    dotnet test --no-build -- --filter-not-trait "Category=S4" --filter-not-trait "Category=S5"
    just analyze-servicing
    just contract-tests

# Discover tests/contract/Test-*.ps1 (WinPE / DISM / release helpers that cannot run on a live host).
contract-tests:
    pwsh -NoProfile -File '{{justfile_directory()}}/tests/contract/Invoke-ContractTests.ps1'

# Live winget/scoop prove → config/packages.proof.json. Not in `just check` (offline proof enforces freshness).
packages-check:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-WinMintCli.ps1' -- packages-check

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
analyze-servicing:
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) { Write-Error 'PSScriptAnalyzer not installed. Run: Install-Module -Name PSScriptAnalyzer -Scope CurrentUser'; exit 1 }; $issues = Invoke-ScriptAnalyzer -Path '{{justfile_directory()}}/servicing' -Settings '{{justfile_directory()}}/servicing/PSScriptAnalyzerSettings.psd1' -Recurse; if ($issues) { $issues | Format-Table -AutoSize | Out-String | Write-Output; exit 1 }; Write-Output 'PSScriptAnalyzer: clean'

publish-provisioning:
    dotnet publish src/WinMint.Provisioning/WinMint.Provisioning.csproj -c Release -o artifacts/provisioning

# Admin: Defender exclusions for DISM workdirs.
exclude-scratch ISO="":
    $scratch = Join-Path '{{justfile_directory()}}' '.scratch'; $servicing = Join-Path $env:ProgramData 'WinMint\Servicing'; New-Item -ItemType Directory -Force -Path $scratch, $servicing | Out-Null; $paths = @($scratch, $servicing); if ('{{ISO}}' -ne '') { $paths += '{{ISO}}' }; foreach ($p in $paths) { Add-MpPreference -ExclusionPath $p; Write-Host "Excluded: $p" }

# Artifact hygiene under .scratch (or root=…). Nuclear: just wipe-scratch
clean-artifacts root=".scratch" keep="2" workdirs="1" days="14":
    $root = '{{root}}'; if (-not [System.IO.Path]::IsPathRooted($root)) { $root = Join-Path '{{justfile_directory()}}' $root }; pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-ArtifactHygiene.ps1' -Root $root -KeepIso {{keep}} -KeepWorkDirs {{workdirs}} -MaxAgeDays {{days}}

wipe-scratch:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-ArtifactHygiene.ps1' -Root (Join-Path '{{justfile_directory()}}' '.scratch') -Wipe

# Tail apply-status.txt. Default WORK = Gate B (%LOCALAPPDATA%\WinMint\work\gate-b).
watch-apply WORK="":
    pwsh -NoProfile -Command ". '{{justfile_directory()}}/tools/host/WinMintPaths.ps1'; $w='{{WORK}}'; if ([string]::IsNullOrWhiteSpace($w)) { $w = Get-WinMintGateBWorkDirectory }; Get-Content -LiteralPath (Join-Path $w 'apply-status.txt') -Wait -Tail 40"

# Maintainer Apply (DISM hours). Cli verb is build.
# Prereq: just publish-provisioning. INCLUDE_SMOKE_STUBS=true → --include-smoke-stubs.
apply-maintainer ISO WORK PROFILE="samples/smoke.profile.json" INCLUDE_SMOKE_STUBS="false":
    Write-Host 'Maintainer Apply can take multiple hours (DISM I/O). Prefer just check day-to-day.'; $stubs = @(); if ('{{INCLUDE_SMOKE_STUBS}}' -eq 'true') { $stubs = @('--include-smoke-stubs') }; Set-Location '{{justfile_directory()}}'; $args = @('build', '{{PROFILE}}', '--iso', '{{ISO}}', '--work', '{{WORK}}') + $stubs; & pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-WinMintCli.ps1' -- @args; exit $LASTEXITCODE

# S4 Hyper-V Smoke — not in `just check`. Assert-only: just smoke-assert tests/fixtures/smoke-evidence
smoke ISO WORK=".scratch/smoke" PROFILE="samples/acceptance.profile.json":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/vm/Invoke-Smoke.ps1' -Iso '{{ISO}}' -Work '{{WORK}}' -Profile '{{PROFILE}}'

smoke-assert EVIDENCE:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/vm/Invoke-Smoke.ps1' -AssertOnly -EvidenceDir '{{EVIDENCE}}'

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
