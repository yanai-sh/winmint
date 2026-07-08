# ADR-003: PowerShell as Windows imaging boundary

**Status:** Accepted  
**Date:** 2026-07-07

### Context

WinMint orchestrates DISM, WIM mount/servicing, offline registry, driver injection, and ISO creation. The engine grew to ~200 scripts with UI, agent, and reporting logic.

### Options considered

| Option | Pros | Cons |
|--------|------|------|
| All-in PowerShell | Native DISM cmdlets, no compile step for imaging | Weak typing, dot-source ambient scope |
| C#/Rust orchestration + PS scripts | Typed core | Reinventing Windows imaging glue |
| **PS for imaging boundary; typed hosts for UI** | Best fit per layer | Two languages |

### Decision

PowerShell 7.6.2+ owns **offline imaging and staging** (`src/runtime/image/`, `src/runtime/setup/` machine scripts). C# AOT hosts own **fullscreen presentation** only. UI invokes engine through `tools/ui-bridge/` or CLI — never loads DISM directly.

Engine entry: `WinMint.Engine` module dot-sources `WinMint.ps1` in fixed order. Do not split into parallel `.psm1` per area without real consumers.

Staged FirstLogon scripts target **pwsh 7** (autounattend path); align `#Requires -Version 7.6` on staged tree (Track 5).

### Consequences

- **Positive:** Imaging stays scriptable and Windows-native.
- **Negative:** Large dot-source graph; discipline required.
- **Follow-up:** Track 5 single-sources `WinMint.Runtime.Common.ps1`; bump staged PS version.

### Review trigger

If engine exceeds maintainability without ISO test coverage, consider extracting **compile-only** plan builder to C# — not DISM calls.
