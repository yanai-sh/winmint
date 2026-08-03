# WinMint v2 — product stack

Pins and coding norms for M1 implementation. Shape: [ARCHITECTURE.md](ARCHITECTURE.md). Design: [DESIGN.md](DESIGN.md). Decision: [ADR-004](decisions/ADR-004-stack-and-guest-control-plane.md). Glossary: [CONTEXT.md](../CONTEXT.md).

## Languages

| Language | Role |
|----------|------|
| **C#** (`net11.0`, rolling .NET 11 preview) | CLI, Orchestrator (BuildPlan), Provisioning Supervisor (ProvisioningSession) |
| **PowerShell 7.6 LTS** | Elevated **host Servicing** adapters only (kernels by ticket) |

Guest is pwsh-free. Do not chase preview pwsh to match `net11.0`.

## Runtime pins

| Item | Pin |
|------|-----|
| TFM | `net11.0` |
| SDK | Rolling .NET 11 preview (`global.json` floor `11.0.100-preview.1` + `latestFeature` + `allowPrerelease`; CI `11.0.x`) |
| LangVersion | `preview` as needed |
| AOT | `PublishAot` on Provisioning (Release); `IsAotCompatible` graph-wide |
| Build | Deterministic; `ContinuousIntegrationBuild` under GITHUB_ACTIONS |
| Host / CI | **ARM64** first (`windows-11-arm`) |

## Projects (day one)

| Path | Owns |
|------|------|
| `src/WinMint.Cli` | Thin CLI host → ProjectReference Orchestrator |
| `src/WinMint.Orchestrator` | BuildPlan (Profile / plan / unattend / job JSON); drives Servicing |
| `src/WinMint.Provisioning` | ProvisioningSession (guest Supervisor, AOT) |
| `payload/scripts/` | `SetupComplete.cmd` → `%WINDIR%\Setup\Scripts\` |

**By ticket later:** `servicing/` (ImageServicing adapters), `schemas/`, `payload/media`, `tools/` (one Smoke acceptance harness interface preferred), Avalonia Wizard.

Do not add a shared Contracts project, Servicing port interface, MediatR, or Generic Host until a second real consumer forces them.

## Coding (when types arrive)

- File-scoped namespaces, primary constructors, `required`, collection expressions, patterns.
- `System.Text.Json` **source generation** for contracts (AOT-safe). Records/DTOs; C# unions only if preview surface stays stable — else discriminated records.
- Win32: `LibraryImport` only. Time: `TimeProvider` (settle / unlock). Async: `CancellationToken` on I/O and process waits.
- Domain/validation → typed results at BuildPlan seam; exceptions for bugs/invariants.
- Microsoft-thin: BCL + source-gen JSON; `System.CommandLine` when flags land.
- Warnings as errors + analyzers (`Directory.Build.props`). XML docs / enforce-style-on-build later.

## NuGet

Day one: `xunit.v3.mtp-v2` only. Justify every package. Avalonia **12.1.x** later for host wizard.

## External tools (when needed)

DISM / oscdimg (host), winget/Scoop/wsl (guest jobs), Hyper-V (acceptance), Just, **PSScriptAnalyzer** (`just analyze-servicing`; also run from `just check`). Install once: `Install-Module -Name PSScriptAnalyzer -Scope CurrentUser`. Servicing scripts are **UTF-8 without BOM** (pwsh-native); `servicing/PSScriptAnalyzerSettings.psd1` excludes only legacy `PSUseBOMForUnicodeEncodedFile`.
