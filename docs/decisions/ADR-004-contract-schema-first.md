# ADR-004: JSON Schema-first contracts

**Status:** Accepted  
**Date:** 2026-07-07

### Context

WinMint passes data across UI, engine, ISO payloads, FirstLogon, agent, and VM harness. Multiple JSON files evolved (`BuildProfile`, `BuildManifest`, `BuildDelta`, `uiintent`, `setup-shell-control`, `setup-shell-status`, `state.json`).

### Options considered

| Option | Pros | Cons |
|--------|------|------|
| Ad hoc JSON + tests | Flexible | Drift, duplicate projections |
| **JSON Schema + fewer artifacts** | Validatable, documented | Migration cost |
| Protobuf/gRPC | Strong typing | Poor fit for file-based Windows setup |

### Decision

**JSON Schema** under `schemas/` is the contract source of truth. Target artifact count:

| Phase | Artifacts |
|-------|-----------|
| Authoring | `BuildProfile.json` (v4) |
| Build output | `BuildManifest.json` (includes embedded audit `records[]`; no standalone BuildDelta) |
| Live runtime | `runtime-state.json` (replaces control + status + folds agent display; agent resume stays in schema-backed steps) |

Retired `winmint.uiintent.schema.json`; the wizard persists `wizard-settings.json` and the bridge compiles BuildProfile v4.

Validate schemas in `tools/validation/Validate.ps1` and on critical runtime writes.

C# DTOs should codegen from schemas (Track 7) to avoid `JsonContracts.cs` drift.

### Consequences

- **Positive:** Fewer truths; easier VM evidence.
- **Negative:** Strangler migration for runtime-state (Track 3).
- **Follow-up:** Tracks 2–3, 7.

### Review trigger

After runtime-state migration + smoke green, delete deprecated schemas and legacy file paths.
