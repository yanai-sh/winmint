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
    dotnet test --no-build -- --filter-not-trait "Category=S4"
    just analyze-servicing

# Host-only: STACK promised PSScriptAnalyzer once servicing/ exists. Not a product NuGet.
# Install once: Install-Module -Name PSScriptAnalyzer -Scope CurrentUser
analyze-servicing:
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) { Write-Error 'PSScriptAnalyzer not installed. Run: Install-Module -Name PSScriptAnalyzer -Scope CurrentUser'; exit 1 }; $issues = Invoke-ScriptAnalyzer -Path '{{justfile_directory()}}/servicing' -Settings '{{justfile_directory()}}/servicing/PSScriptAnalyzerSettings.psd1' -Recurse; if ($issues) { $issues | Format-Table -AutoSize | Out-String | Write-Output; exit 1 }; Write-Output 'PSScriptAnalyzer: clean'

publish-provisioning:
    dotnet publish src/WinMint.Provisioning/WinMint.Provisioning.csproj -c Release -o artifacts/provisioning

# Host hygiene for maintainer Apply (admin). Speeds DISM commit; not a product dependency.
exclude-scratch ISO="":
    $scratch = Join-Path '{{justfile_directory()}}' '.scratch'; New-Item -ItemType Directory -Force -Path $scratch | Out-Null; $paths = @($scratch); if ('{{ISO}}' -ne '') { $paths += '{{ISO}}' }; foreach ($p in $paths) { Add-MpPreference -ExclusionPath $p; Write-Host "Excluded: $p" }

# Multi-hour DISM Apply. Cold first; later runs auto --reuse-media when marker exists.
# Prereq: just publish-provisioning. Watch: Get-Content <WORK>\apply-status.txt -Wait
apply-maintainer ISO WORK PROFILE="samples/smoke.profile.json":
    Write-Host 'Maintainer Apply can take multiple hours (DISM I/O). Prefer just check day-to-day.'; $marker = Join-Path '{{WORK}}' 'media\sources\.winmint-single-index'; $reuse = @(); if (Test-Path -LiteralPath $marker) { Write-Host 'Found single-image marker — passing --reuse-media'; $reuse = @('--reuse-media') }; Set-Location '{{justfile_directory()}}'; & dotnet run --project src/WinMint.Cli -- apply '{{PROFILE}}' --iso '{{ISO}}' --work '{{WORK}}' @reuse; exit $LASTEXITCODE

# S4 Hyper-V Smoke — not part of `just check`. Needs admin + Hyper-V + user ISO.
# Assert-only (no VM): just smoke-assert tests/fixtures/smoke-evidence
smoke ISO WORK=".scratch/smoke" PROFILE="samples/acceptance.profile.json":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/vm/Invoke-Smoke.ps1' -Iso '{{ISO}}' -Work '{{WORK}}' -Profile '{{PROFILE}}'

smoke-assert EVIDENCE:
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/vm/Invoke-Smoke.ps1' -AssertOnly -EvidenceDir '{{EVIDENCE}}'
