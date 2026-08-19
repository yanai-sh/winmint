# WinMint — product stack

Pins and coding norms. Shape: [ARCHITECTURE](ARCHITECTURE.md). Rules: [DESIGN](DESIGN.md). Glossary: [CONTEXT](../CONTEXT.md).

## Languages

| Language | Role |
|----------|------|
| **C#** (`net11.0`, rolling .NET 11 preview) | CLI, Orchestrator (BuildPlan), Wizard, Provisioning Supervisor |
| **PowerShell 7.6 LTS** | Elevated **host Servicing** adapters only |

No guest **pwsh product runtime**. Inbox `powershell.exe` for Scoop bootstrap / narrow import wrappers is OK.

## Runtime pins

| Item | Pin |
|------|-----|
| TFM | `net11.0` |
| SDK | Rolling .NET 11 preview (`global.json` floor + `latestFeature` + `allowPrerelease`) |
| LangVersion | `preview` |
| Analyzers | `AnalysisLevel` `11-recommended` (not `preview-*`: this SDK maps `preview` to CA 12, and those configs are not shipped). Style: `11-recommended` + `EnforceCodeStyleInBuild` + `dotnet new editorconfig` (STACK: file-scoped namespaces, collection expressions, primary constructors). `GenerateDocumentationFile` on, CS1591 off. Compiler waves: `WarningLevel` 9999. |
| Runtime Async | Opt in with `<Features>runtime-async=on</Features>` (Learn .NET 11; NativeAOT-supported) |
| AOT | `PublishAot` on Provisioning and WinPeApply (Release); `IsAotCompatible` graph-wide |
| Build | Deterministic; `ContinuousIntegrationBuild` under GITHUB_ACTIONS |
| Host / CI | **ARM64** first (`windows-11-arm`) |

## Projects

| Path | Owns |
|------|------|
| `src/WinMint.Cli` | Thin CLI → Orchestrator |
| `src/WinMint.Contracts` | Tiny shared wire enums + `DmaSettleTarget` + guest bundle DTOs |
| `src/WinMint.Orchestrator` | BuildPlan; drives Servicing |
| `src/WinMint.Provisioning` | ProvisioningSession (AOT Supervisor) |
| `src/WinMint.WinPeApply` | WinPE apply host (`WinMintApply.exe`, AOT WinExe; winpeshl `[LaunchApp]`) |
| `src/WinMint.Wizard` | Avalonia BuildPlan front end |
| `servicing/` | ImageServicing `pwsh -File` adapters |
| `payload/winpe/` | Authoritative WinPE apply script (`LaunchApply.cmd`; byte-copied into every `boot.wim` index; launched hidden by `WinMintApply.exe`) |
| `payload/scripts/` | `SetupComplete.cmd` |
| `tools/` | Smoke / apply harness |

**Host maintenance (not guest runtime):** `PackagesProof` (C#) proves the shipped catalog — writes transient check request JSON, invokes native ARM64 `pwsh -File tools/host/Invoke-PackagesCheck.ps1`, reconciles outcome, atomically replaces `config/packages.proof.json`. `just check` validates that receipt offline.

No MediatR / Generic Host / AutoMapper. Shared wire types live in `WinMint.Contracts` only — not a product module with behavior.

## Coding

- File-scoped namespaces, primary constructors, `required`, collection expressions, patterns. Prefer BCL / .NET 11 APIs (`Process.Run` / `RunAndCaptureText*`, stream adapters) over hand-rolled equivalents.
- `System.Text.Json` **source generation** for contracts (AOT-safe), including Wizard probe JSON.
- Win32: `LibraryImport` only (hand-written or **CsWin32** from official win32metadata). Prefer `SafeHandle` over raw `HWND`/`HANDLE` `IntPtr`. Time: `TimeProvider`. WinRT AppX via projected `Windows.Management.Deployment.PackageManager` (async — no `GetResult`).
- **Async:** `CancellationToken` on I/O and process waits. Do not bridge with `GetAwaiter().GetResult()` — make the path async or use sync I/O end-to-end.
- **Errors:** expected validation / parse / unknown-key → typed `Result` (or session status) at **every** seam (Profile, catalog, bundle, plan, apply). Exceptions for bugs and true invariants only.
- **Job kinds:** closed set at the load boundary (enum today; C# 15 `union` after PublishAot/STJ spike). Wire JSON may stay string.
- NuGet: justify every package (“why not BCL”). Avalonia **12.x** Wizard. `xunit` v3 + MTP. Prefer `LoggerMessage` / const status codes over `.resx` i18n.
- Document deep-module entrypoints in source. `GenerateDocumentationFile` is on for IDE0005 (unused usings); CS1591 stays off until a shipped public API needs it.
- Warnings as errors + .NET 11 recommended CA and code-style catalogs + `EnforceCodeStyleInBuild` (`Directory.Build.props`). Banned APIs: `BannedSymbols.txt`. PowerShell: PSScriptAnalyzer on `servicing/`, `tools/`, `tests/contract/`, payload profile, and `winmint.ps1`.
