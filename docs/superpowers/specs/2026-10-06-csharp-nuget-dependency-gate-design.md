# C# NuGet dependency gate

**Date:** 2026-10-06 · **Status:** accepted · **Build contract only** (ADR-014 — not living law)

Brainstorm + audit artifact. Standing bar lands as a short ADR-004 NuGet-tiers note; package versions stay in `.csproj`. Not about WinMint catalog package-ids.

## Goals

1. Standing gate: where PackageReferences may live, and “why not BCL?” for every add
2. Current-state verdict: keep the lean set; no prune-for-sport; no best-practice kit adds

## Non-goals

Central Package Management, deny/allowlist contract harness (optional later if Brain/ISO projects gain packages), removing Avalonia/CLI/CsWin32, catalog package-ids, PowerShell modules, guest Scoop/winget installs.

## Inventory (audit)

**8 unique direct PackageReferences:**

| Package | Project(s) | Role |
|---------|------------|------|
| `System.CommandLine` | Cli, Tests | Host CLI parse |
| `Avalonia` | Wizard | Host GUI |
| `Avalonia.Desktop` | Wizard | Host GUI |
| `Avalonia.Themes.Fluent` | Wizard | Host GUI |
| `CommunityToolkit.Mvvm` | Wizard | Wizard-only MVVM source-gen |
| `Microsoft.Windows.CsWin32` | Provisioning | Build-time Win32 (`PrivateAssets`) |
| `Microsoft.CodeAnalysis.BannedApiAnalyzers` | All via Directory.Build.props | Banned API analyzer (`PrivateAssets`) |
| `xunit.v3.mtp-v2` | Tests | Test runner |

**Zero PackageReferences:** Contracts, Orchestrator, WinPeApply. BCL for JSON/HTTP/process; hand-built winget YAML; thin custom `ILogger`s (no logging-provider package).

SDK auto-ref `Microsoft.NET.ILLink.Tasks` is not a product choice. Wizard Avalonia/Skia transitive graph stays host-only / off ISO.

## Tiers

| Tier | Projects | Rule |
|------|----------|------|
| **ISO / AOT** | Provisioning, WinPeApply | Prefer zero runtime NuGet. Build-only (`PrivateAssets`) Win32 generators OK when BCL/`LibraryImport` alone is worse. No UI, DI, logging-provider, or HTTP-stack packages. |
| **Brain** | Contracts, Orchestrator | Zero PackageReferences. |
| **Host adapters** | Cli, Wizard | Host UX only (CLI parse, Avalonia, Wizard MVVM). Must not become Orchestrator/ISO dependencies. |
| **Build/test** | Directory.Build.props analyzers, Tests | Analyzers `PrivateAssets`; test runner OK. No product runtime leak. |

**Gate for any new package:** one sentence “why not BCL (or inbox platform API)?” Prefer Microsoft-owned or packages already on the Wizard path (Avalonia / CommunityToolkit).

## Current-state verdict

| Package | Verdict |
|---------|---------|
| `System.CommandLine` | Keep |
| Avalonia trio + `CommunityToolkit.Mvvm` | Keep |
| `Microsoft.Windows.CsWin32` | Keep |
| `BannedApiAnalyzers` | Keep |
| `xunit.v3.mtp-v2` | Keep |

**Do not add now:** Serilog / `Microsoft.Extensions.Logging.Console`, DI containers, Polly, CliWrap, YamlDotNet, FluentAssertions/Moq, Newtonsoft.Json, Spectre.Console, CPM.

**Do not remove now:** Avalonia theme/desktop PackageReferences (transitive Skia graph unchanged); hand-rolled CLI parse or Win32 interop.

## ADR-004 shape (implementation)

Expand the existing one-liner (“NuGet is Microsoft-thin…”) into a short NuGet-tiers note matching the table above. No package id catalog or version pins in the ADR.

## Rejected

- Codify gate only as a living deps.md / allowlist file
- Approach 2 enforce-now contract harness (defer until Brain/ISO PackageReference creep)
- Approach 3 Central Package Management for an 8-package graph
- Shrinking NuGet count by dropping host surfaces or re-homing Win32 by hand

## Success

- ADR-004 states tiers + why-not-BCL
- Agents can answer “may I add X?” without inventing policy
- No PackageReference churn in the landing change set unless a later justified issue needs an add
