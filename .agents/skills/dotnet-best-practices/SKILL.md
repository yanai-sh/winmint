---
name: dotnet-best-practices
description: Ensure .NET/C# code meets WinMint / net11.0 practices (not generic enterprise templates).
---

# WinMint .NET / C# practices

Apply to `${selection}`. Authority: [AGENTS.md](../../../AGENTS.md) (map), [CONTEXT.md](../../../CONTEXT.md) (words), [docs/decisions/](../../../docs/decisions/) (why). Behaviour in `src/` / `tests/` — not living design docs ([ADR-014](../../../docs/decisions/ADR-014-docs-are-not-living-law.md)). NuGet tiers: [ADR-004](../../../docs/decisions/ADR-004-stack-and-guest-control-plane.md).

## Project baseline

- TFM `net11.0`, `LangVersion` preview, nullable, analyzers, `TreatWarningsAsErrors`
- Namespaces: `WinMint.{Orchestrator|Cli|Wizard|Provisioning|Contracts|WinPeApply}` (+ `.ViewModels` / `.Views`)
- AOT: `IsAotCompatible`; Provisioning Release `PublishAot`
- STJ **source generation** for JSON contracts; no AutoMapper / Mapster
- Win32: `LibraryImport` only; time via `TimeProvider`
- Tests: **xUnit v3** + Microsoft.Testing.Platform; hand fakes OK
- **No** Central Package Management

## Do

- Records / `IReadOnly*` for domain; small value objects as `readonly record struct` when value-identity fits
- Expected validation → `Result<TOk,TErr>` (or session status) at every seam — Profile, catalog, bundle, plan, apply
- `CancellationToken` on I/O and process waits; prefer `Process.Run` / `RunAndCaptureText*` over Start+WaitForExit
- Async paths: await — no `GetAwaiter().GetResult()` bridges
- Closed job `Kind` at load (enum)
- Primary constructors on instance adapters; composition via ports (`SessionEnvironment`)
- `LoggerMessage` / const status codes for messages (not `.resx` i18n)
- XML docs on deep-module entrypoints when touching them

## Don’t

- MediatR / CommandHandler / Generic Host / DI container theater
- AutoMapper / Mapster / reflection JSON where a `JsonSerializerContext` exists
- MSTest; ResourceManager `.resx` for EN-only tooling
- `Core|Console|App|Service` namespace rename
- Semantic Kernel / ASP.NET / EF / MAUI unless the product surface needs them
- Excusing sync-over-async or open string `Kind` as “intentional forever”

## Async & errors

- Library / Supervisor: `ConfigureAwait(false)` when awaiting
- Wizard UI: capture sync context as Avalonia requires
- Exceptions for bugs/invariants only — not unknown catalog keys or bad bundle schema
