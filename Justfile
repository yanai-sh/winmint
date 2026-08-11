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

# Pack no-clone toolkit zip + sha256 (win-arm64). Example: just pack-release v0.1.0
pack-release TAG:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/release/Pack-WinMintRelease.ps1' -Tag '{{TAG}}'

format-check:
    dotnet format --verify-no-changes

check: format-check build
    dotnet test --no-build -- --filter-not-trait "Category=S4" --filter-not-trait "Category=Metal"
    just analyze-servicing
    just bootstrap-contract

bootstrap-contract:
    pwsh -NoProfile -File '{{justfile_directory()}}/tests/contract/Test-BootstrapContract.ps1'

# Host-only: STACK promised PSScriptAnalyzer once servicing/ exists. Not a product NuGet.
# Install once: Install-Module -Name PSScriptAnalyzer -Scope CurrentUser
analyze-servicing:
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) { Write-Error 'PSScriptAnalyzer not installed. Run: Install-Module -Name PSScriptAnalyzer -Scope CurrentUser'; exit 1 }; $issues = Invoke-ScriptAnalyzer -Path '{{justfile_directory()}}/servicing' -Settings '{{justfile_directory()}}/servicing/PSScriptAnalyzerSettings.psd1' -Recurse; if ($issues) { $issues | Format-Table -AutoSize | Out-String | Write-Output; exit 1 }; Write-Output 'PSScriptAnalyzer: clean'

publish-provisioning:
    dotnet publish src/WinMint.Provisioning/WinMint.Provisioning.csproj -c Release -o artifacts/provisioning

# Host hygiene for maintainer Apply (admin). Speeds DISM commit; not a product dependency.
exclude-scratch ISO="":
    $scratch = Join-Path '{{justfile_directory()}}' '.scratch'; $servicing = Join-Path $env:ProgramData 'WinMint\Servicing'; New-Item -ItemType Directory -Force -Path $scratch, $servicing | Out-Null; $paths = @($scratch, $servicing); if ('{{ISO}}' -ne '') { $paths += '{{ISO}}' }; foreach ($p in $paths) { Add-MpPreference -ExclusionPath $p; Write-Host "Excluded: $p" }

# Artifact hygiene — matches the ~386 GB failure mode (stacked output ISOs + multiple full workdirs).
# Default: under .scratch keep 1 newest heavy workdir, 2 newest ISOs, purge disks >14d.
# Nuclear (what the cleanup session did): just wipe-scratch
# Flat v1-style output: just clean-artifacts root="C:/Users/yanai/Projects/winmint_v1/output" keep=1
clean-artifacts root=".scratch" keep="2" workdirs="1" days="14":
    $root = '{{root}}'; if (-not [System.IO.Path]::IsPathRooted($root)) { $root = Join-Path '{{justfile_directory()}}' $root }; pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-ArtifactHygiene.ps1' -Root $root -KeepIso {{keep}} -KeepWorkDirs {{workdirs}} -MaxAgeDays {{days}}

wipe-scratch:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-ArtifactHygiene.ps1' -Root (Join-Path '{{justfile_directory()}}' '.scratch') -Wipe

# Tail Apply progress (stage=opcode|done|failed:*). STALL_SUSPECT is Smoke-only (tools/vm).
watch-apply WORK=".scratch/sl7-build":
    Get-Content (Join-Path '{{WORK}}' 'apply-status.txt') -Wait

# Multi-hour DISM Apply. Cold first; later runs auto --reuse-media when marker exists.
# Prereq: just publish-provisioning. Watch: just watch-apply WORK=<dir>
# ponytail: recipe keeps Apply name (DISM loop); Cli verb is build only.
# INCLUDE_SMOKE_STUBS=true → --include-smoke-stubs (Smoke/acceptance only).
apply-maintainer ISO WORK PROFILE="samples/smoke.profile.json" INCLUDE_SMOKE_STUBS="false":
    Write-Host 'Maintainer Apply can take multiple hours (DISM I/O). Prefer just check day-to-day.'; $marker = Join-Path '{{WORK}}' 'media\sources\.winmint-single-index'; $reuse = @(); if (Test-Path -LiteralPath $marker) { Write-Host 'Found single-image marker — passing --reuse-media'; $reuse = @('--reuse-media') }; $stubs = @(); if ('{{INCLUDE_SMOKE_STUBS}}' -eq 'true') { $stubs = @('--include-smoke-stubs') }; Set-Location '{{justfile_directory()}}'; $args = @('build', '{{PROFILE}}', '--iso', '{{ISO}}', '--work', '{{WORK}}') + $stubs + $reuse; & pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-WinMintCli.ps1' -- @args; exit $LASTEXITCODE

# S4 Hyper-V Smoke — not part of `just check`. Needs admin + Hyper-V + user ISO.
# Assert-only (no VM): just smoke-assert tests/fixtures/smoke-evidence
# Reuse prior Apply ISO: pwsh tools/vm/Invoke-Smoke.ps1 -Iso … -SkipApply
# Attach in-progress VM:  … -ReuseVm
smoke ISO WORK=".scratch/smoke" PROFILE="samples/acceptance.profile.json":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/vm/Invoke-Smoke.ps1' -Iso '{{ISO}}' -Work '{{WORK}}' -Profile '{{PROFILE}}'

smoke-assert EVIDENCE:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/vm/Invoke-Smoke.ps1' -AssertOnly -EvidenceDir '{{EVIDENCE}}'

# S5 Metal — on-device Apply evidence (pre-wipe). No Hyper-V, no bare-metal install.
# Test metal ≠ Primary. Wipe ISO: just primary-gate ISO=…
# QUALITY=Release without PackageStrict is rejected — use primary-gate only.
# Full gate: just metal ISO=<source.iso>
# Reuse prior Apply: pwsh tools/metal/Invoke-MetalApply.ps1 -Iso … -SkipApply
# Assert only: just metal-assert .scratch/sl7-build
metal ISO WORK=".scratch/sl7-build" PROFILE="samples/sl7.profile.json" QUALITY="Test":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/metal/Invoke-MetalApply.ps1' -Iso '{{ISO}}' -Work '{{WORK}}' -Profile '{{PROFILE}}' -ImageQuality '{{QUALITY}}'

# Primary Gate B + wipe ISO: Release + package-strict.
# Workdir stays outside TEMP toolkit (survives ephemeral session cleanup).
# After success: flash WORK\out.iso (UEFI USB); check digests outputIso.sha256 in evidence.json; expect WinPE LaunchApply.
primary-gate ISO WORK="" PROFILE="samples/sl7.profile.json":
    pwsh -NoProfile -Command "$w='{{WORK}}'; if ([string]::IsNullOrWhiteSpace($w)) { $w = Join-Path $env:LOCALAPPDATA 'WinMint\work\sl7-primary' }; New-Item -ItemType Directory -Force -Path $w | Out-Null; & pwsh -NoProfile -File '{{justfile_directory()}}/tools/metal/Invoke-MetalApply.ps1' -Iso '{{ISO}}' -Work $w -Profile '{{PROFILE}}' -ImageQuality Release -PackageStrict -ExpectDrivers -RequireLane Release"

metal-assert WORK=".scratch/sl7-build":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/metal/Invoke-MetalApply.ps1' -AssertOnly -WorkDirectory '{{WORK}}' -ExpectDrivers

# Wipe-lane assert only (fails on Test evidence).
primary-gate-assert WORK="":
    pwsh -NoProfile -Command "$w='{{WORK}}'; if ([string]::IsNullOrWhiteSpace($w)) { $w = Join-Path $env:LOCALAPPDATA 'WinMint\work\sl7-primary' }; & pwsh -NoProfile -File '{{justfile_directory()}}/tools/metal/Invoke-MetalApply.ps1' -AssertOnly -WorkDirectory $w -ExpectDrivers -RequireLane Release"
