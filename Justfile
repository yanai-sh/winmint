# WinMint v2 — host tasks (winget install Casey.Just)

set windows-shell := ["pwsh.exe", "-NoProfile", "-Command"]

default:
    @just --list

restore:
    dotnet restore

build: restore
    dotnet build --no-restore

format-check:
    dotnet format --verify-no-changes

check: format-check build
    dotnet test --no-build -- --filter-not-trait "Category=S4" --filter-not-trait "Category=Metal"
    just analyze-servicing

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

# Multi-hour DISM Apply. Cold first; later runs auto --reuse-media when marker exists.
# Prereq: just publish-provisioning. Watch: Get-Content <WORK>\apply-status.txt -Wait
# ponytail: recipe keeps Apply name (DISM loop); Cli verb is build only.
apply-maintainer ISO WORK PROFILE="samples/smoke.profile.json":
    Write-Host 'Maintainer Apply can take multiple hours (DISM I/O). Prefer just check day-to-day.'; $marker = Join-Path '{{WORK}}' 'media\sources\.winmint-single-index'; $reuse = @(); if (Test-Path -LiteralPath $marker) { Write-Host 'Found single-image marker — passing --reuse-media'; $reuse = @('--reuse-media') }; Set-Location '{{justfile_directory()}}'; & dotnet run --project src/WinMint.Cli -- build '{{PROFILE}}' --iso '{{ISO}}' --work '{{WORK}}' @reuse; exit $LASTEXITCODE

# S4 Hyper-V Smoke — not part of `just check`. Needs admin + Hyper-V + user ISO.
# Assert-only (no VM): just smoke-assert tests/fixtures/smoke-evidence
# Reuse prior Apply ISO: pwsh tools/vm/Invoke-Smoke.ps1 -Iso … -SkipApply
# Attach in-progress VM:  … -ReuseVm
smoke ISO WORK=".scratch/smoke" PROFILE="samples/acceptance.profile.json":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/vm/Invoke-Smoke.ps1' -Iso '{{ISO}}' -Work '{{WORK}}' -Profile '{{PROFILE}}'

smoke-assert EVIDENCE:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/vm/Invoke-Smoke.ps1' -AssertOnly -EvidenceDir '{{EVIDENCE}}'

# S5 Metal — on-device Apply evidence (pre-wipe). No Hyper-V, no bare-metal install.
# Full gate: just metal ISO=<source.iso>
# Reuse prior Apply: pwsh tools/metal/Invoke-MetalApply.ps1 -Iso … -SkipApply
# Assert only: just metal-assert .scratch/sl7-build
metal ISO WORK=".scratch/sl7-build" PROFILE="samples/sl7.profile.json" QUALITY="Test":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/metal/Invoke-MetalApply.ps1' -Iso '{{ISO}}' -Work '{{WORK}}' -Profile '{{PROFILE}}' -ImageQuality '{{QUALITY}}'

metal-assert WORK=".scratch/sl7-build":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/metal/Invoke-MetalApply.ps1' -AssertOnly -WorkDirectory '{{WORK}}' -ExpectDrivers
