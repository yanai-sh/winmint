# WinMint — product stack

Pins and coding norms. Shape: [ARCHITECTURE](ARCHITECTURE.md). Rules: [DESIGN](DESIGN.md). Glossary: [CONTEXT](../CONTEXT.md).

## Languages

| Language | Role |
|----------|------|
| **C#** (`net11.0`, rolling .NET 11 preview) | CLI, Orchestrator (BuildPlan), Wizard, Provisioning Supervisor (ProvisioningSession) |
| **PowerShell 7.6 LTS** | Elevated **host Servicing** adapters only |

No guest **pwsh product runtime**. Inbox `powershell.exe` for Scoop bootstrap / narrow import wrappers is OK. Do not chase preview pwsh to match `net11.0`.

## Runtime pins

| Item | Pin |
|------|-----|
| TFM | `net11.0` |
| SDK | Rolling .NET 11 preview (`global.json` floor `11.0.100-preview.1` + `latestFeature` + `allowPrerelease`; CI `11.0.x`) |
| LangVersion | `preview` as needed |
| AOT | `PublishAot` on Provisioning (Release); `IsAotCompatible` graph-wide |
| Build | Deterministic; `ContinuousIntegrationBuild` under GITHUB_ACTIONS |
| Host / CI | **ARM64** first (`windows-11-arm`) |

## Projects

| Path | Owns |
|------|------|
| `src/WinMint.Cli` | Thin CLI host → Orchestrator |
| `src/WinMint.Orchestrator` | BuildPlan; drives Servicing |
| `src/WinMint.Provisioning` | ProvisioningSession (guest Supervisor, AOT) |
| `src/WinMint.Wizard` | Avalonia BuildPlan host |
| `servicing/` | ImageServicing `pwsh -File` adapters |
| `payload/scripts/` | `SetupComplete.cmd` → `%WINDIR%\Setup\Scripts\` |
| `tools/` | Smoke / metal harness |

Do not add a shared Contracts project, Servicing port interface, MediatR, or Generic Host until a second real consumer forces them.

## Coding

- File-scoped namespaces, primary constructors, `required`, collection expressions, patterns.
- `System.Text.Json` **source generation** for contracts (AOT-safe).
- Win32: `LibraryImport` only. Time: `TimeProvider`. Async: `CancellationToken` on I/O and process waits.
- Domain/validation → typed results at BuildPlan seam; exceptions for bugs/invariants.
- Microsoft-thin NuGet. Warnings as errors + analyzers (`Directory.Build.props`).

## NuGet

Justify every package. Avalonia **12.x** for host Wizard. `xunit` for tests.

## External tools

DISM / oscdimg (host), winget/Scoop/wsl (guest jobs), Hyper-V (acceptance), Just, **PSScriptAnalyzer** (`just analyze-servicing`; also from `just check`). Install once: `Install-Module -Name PSScriptAnalyzer -Scope CurrentUser`. Servicing scripts are **UTF-8 without BOM**; `servicing/PSScriptAnalyzerSettings.psd1` excludes only legacy `PSUseBOMForUnicodeEncodedFile`.
