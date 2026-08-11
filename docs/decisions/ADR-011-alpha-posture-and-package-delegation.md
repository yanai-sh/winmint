# ADR-011: Alpha posture — requirement tiers and package delegation

**Status:** Accepted  
**Date:** 2026-08-06  
**Supersedes (partial):** readings of [ADR-004](ADR-004-stack-and-guest-control-plane.md) that forbid all guest PowerShell and require one C# spawn per package; default runtime native audit in [ADR-010](ADR-010-arm64-package-policy.md)  
**Related:** [DESIGN](../DESIGN.md), [package catalog spec](../specs/2026-08-05-package-catalog-arm64.md)

### Context

WinMint is an **alpha** product. Grill locks and ticket-sequence decisions helped ship M1–M3, but some are now **negative drag**: they block simpler paths (batch winget/scoop, catalog-time arch verification) while exceptions already exist (Scoop bootstrap via inbox `powershell.exe`).

Maintainers may adopt a net-positive alternative without treating every grill line as immutable law.

### Requirement tiers

| Tier | Meaning | Change bar |
|------|---------|------------|
| **Invariant** | Product identity / safety — do not slip casually | New ADR + maintainer sign-off |
| **Default** | Current shipped behaviour — change when a spike proves net-positive | ADR amendment or issue with spike evidence |
| **Guideline** | Agent/harness convenience | Issue or doc edit |

**Invariants (keep):**

- User-supplied Source ISO ([ADR-001](ADR-001-source-iso-legal.md))
- **Provisioning Supervisor** owns the FirstLogon phase machine: splash-before-Explorer, DMA settle, unlock/reboot checkpoint, in-process splash
- No v1 **`WinMint.ps1`** guest monolith or guest **pwsh product runtime**
- Host Servicing: elevated **`pwsh -File`** kernels only ([ADR-004](ADR-004-stack-and-guest-control-plane.md))
- Residual self-erase after Shell Complete ([ADR-008](ADR-008-residual-minimization.md))
- Remove-list keep-flag polarity ([ADR-005](ADR-005-keep-flag-matrix.md)); CDM not primary ([ADR-007](ADR-007-cdm-not-primary.md))

**Defaults (revisable in alpha):**

- **Package install shape:** per-job `winget` / `scoop` / `wsl` vs batch/delegated install (below)
- **Fail-closed scope:** all jobs vs **invariants fail-closed, packages best-effort + evidence**
- **Architecture truth:** runtime PE audit vs **catalog-time verification** (`just packages-check` / `packages.proof.json` — winget download + scoop manifest download) in maintainer CI
- Job granularity, metal evidence strictness, Wizard UX details

**Guidelines:** NuGet choices, doc wording, harness switches, `*Dto` rename timing.

### Package layer

1. **`config/packages.json`** remains the single human-edited catalog. Plan may **generate** derived artifacts (`winget import` JSON, optional configure YAML, staged scoop bucket list) — not a second source of truth.
2. **Supervisor** stays the orchestrator: phases, splash status, checkpoints, evidence. It may **delegate** the package slice to platform tools:
   - `winget import` or `winget configure` (one phase/job)
   - `scoop bucket add …` + `scoop install a b c`
   - Existing per-id jobs remain valid until a spike retires them
3. **Allowed guest subprocesses:** `winget.exe`, `wsl.exe`, `scoop.cmd`, inbox **`powershell.exe`** for Scoop bootstrap or narrow configure/import wrappers — not a general guest pwsh control plane.
4. **ARM64:** prefer **`--architecture arm64`** (or import `InitialOverrideArguments`) from catalog metadata verified at catalog time. **`package.auditNative`** is optional metal/regression evidence, not default product policy.
5. **Scoop buckets:** catalog may declare **`scoopBucket`** (e.g. `extras` for komorebi/whkd); bootstrap adds required buckets before install.

### Fail-closed vs best-effort

| Layer | Posture |
|-------|---------|
| Machine setup stamp, Shell registration, DMA hard fields, unlock invariant | Fail-closed |
| Debloat / keep-flag / offline policy digests | Fail-closed |
| Curated package installs (winget/scoop/wsl) | **Default best-effort** with splash summary + `%ProgramData%\WinMint\evidence\`; strict fail-closed only when explicitly requested (metal/CI) |

Smoke acceptance may keep strict package asserts; product FirstLogon may relax as alpha learns.

### Consequences

- Spikes before large refactors: e.g. Plan → `winget import` on ARM64 metal vs per-job loop (time, failure surface, reboot).
- Living I/D list lives in [DESIGN](../DESIGN.md); do not treat spent ticket sequencing as immutable law.
- [ADR-004](ADR-004-stack-and-guest-control-plane.md) item 1 read as **no guest pwsh runtime**, not “never spawn powershell.exe.”

### Review trigger

Configure/import delegation regresses splash-before-Explorer or makes FirstLogon nondeterministic in Smoke without an explicit harness switch — revert to per-job default.
