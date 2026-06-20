# Architecture

Snapshot note: updated 2026-06-20. Onboarding/audit snapshot — not a continuous authoritative source.

## Core Sections (Required)

### 1) Architectural Style

- **Primary style:** Layered pipeline with strict boundary enforcement between intent authoring (UI/CLI), offline servicing (engine), Windows Setup phases, and live-user FirstLogon.
- **Why:** AGENTS.md explicitly classifies boundary violations as "architectural bugs." Each layer communicates only via JSON contracts (`BuildProfile.json`, `BuildManifest.json`, `state.json`) — never by calling into another layer's internals.
- **Primary constraints:**
  1. UI creates intent only — never performs DISM, WIM, or offline registry operations
  2. Engine builds from a profile without GUI code loaded — headless by design
  3. FirstLogon resumes after interruption via `%LOCALAPPDATA%\WinMint\state.json` — every step is idempotent

### 2) System Flow

```
User
  → WinMint-GUI.ps1 or WinMint-CLI.ps1 new
  → BuildProfile.json (written to output/)
  → WinMint-CLI.ps1 build <profile>
      → src/runtime/image/WinMint.ps1 (dot-sources full engine)
          → DISM mounts install.wim
          → Tweaks (registry), AppX removal, AI removal, drivers, packages
          → autounattend.xml + setup/firstlogon payloads staged
          → oscdimg.exe assembles bootable ISO
  → Windows Setup consumes ISO → installs Windows
  → SetupComplete.ps1 (machine-phase cleanup: power, toolchain, hygiene)
  → FirstLogon.ps1 bootstraps Agent.Runtime.ps1
      → Modules/* run in order (PackageManagers, Editors, WSL, TilingDesktop…)
      → state.json updated before/after each step
  → System Restore point "WinMint post-install complete"
```

### 3) Layer/Module Responsibilities

| Layer or module | Owns | Must not own | Evidence |
|-----------------|------|--------------|----------|
| `apps/gui/` (Rust/GPUI) | Wizard flow, ISO selection, option toggles, profile creation, bridge invocation | DISM, WIM, offline registry, setup orchestration | `AGENTS.md` |
| `apps/gui/src/bridge.rs` | Spawning `tools/ui-bridge/*.ps1`, parsing JSON output | Rendering, wizard state | `apps/gui/src/bridge.rs` |
| `src/runtime/image/Engine.ps1` | Pipeline orchestration, ISO extraction, WIM servicing | GUI, live-user installs | `AGENTS.md` |
| `src/runtime/image/Private/Config/Profile.ps1` | Profile normalization, defaults, schema validation | Mounting images, installing packages | `AGENTS.md` |
| `src/runtime/image/Private/Image/Tweaks/` | Registry tweak definitions + `appliesTo` predicates; numbered ordering | Ad-hoc registry writes elsewhere in engine | `AGENTS.md` |
| `src/runtime/image/Reports.ps1` | `BuildManifest.json` + `BuildDelta.json` generation | Business logic | `AGENTS.md` |
| `src/runtime/setup/` | Machine-phase setup during Windows install | User prompts, package policy | `AGENTS.md` |
| `src/runtime/firstlogon/` | Live-user setup, idempotent module execution, `state.json` retry | Offline image servicing, disk ops | `AGENTS.md` |
| `config/` | Policy inputs (packages, tweaks metadata, autounattend template) | Generated state or execution logic | `docs/Project-Structure.md` |
| `schemas/` | JSON Schema for BuildProfile, BuildManifest, AgentState | Runtime logic | `AGENTS.md` |

### 4) Reused Patterns

| Pattern | Where found | Why it exists |
|---------|-------------|---------------|
| Dot-source load order (single file controls sequence) | `src/runtime/image/WinMint.ps1` | Guarantees all private modules loaded before any caller; no partial loads |
| JSON contract as inter-layer interface | `BuildProfile.json`, `BuildManifest.json`, `state.json` | Headless operation, auditability, resume-after-failure |
| Numbered module files | `src/runtime/image/Private/Image/Tweaks/NN-<id>.ps1` | Explicit deterministic execution order without coordination logic |
| Idempotent step model | `src/runtime/firstlogon/Modules/*.ps1` | Safe interrupt/resume at any point during FirstLogon |
| Background executor + detach | `apps/gui/src/main.rs` (`probe_source`, `run_dry_build`) | Keeps GPUI render loop responsive during long PowerShell invocations |
| Generation counter for stale result cancellation | `apps/gui/src/main.rs` (`source.generation`) | Discards probe results from a previous ISO selection if user picks a new one |
| `config/tweaks.json` mirrors tweak module metadata | `src/runtime/image/Private/Image/Tweaks/` + `config/tweaks.json` | Static contract test (`StaticAssertions.ps1`) verifies parity |

### 5) Known Architectural Risks

- **GUI bridge is a blocking child-process spawn:** `bridge::run_source_probe` and `bridge::start_build_from_profile` block on `pwsh`. A hung child (e.g. ADK not installed) has no timeout or cancellation path today.
- **`config/tweaks.json` parity is manually maintained:** the static contract test catches drift, but keeping two representations in sync is permanent toil. Single-source generation would eliminate the risk.
- **DISM version is validated at runtime, not at profile authoring:** a mismatch (host DISM older than source image) causes a late build abort rather than a preflight error when the profile is authored.

### 6) Evidence

- `AGENTS.md` — architecture invariants and layer contract table
- `src/runtime/image/WinMint.ps1` — engine dot-source load order
- `apps/gui/src/main.rs` — wizard state machine, background executor pattern
- `apps/gui/src/bridge.rs` — bridge invocation and JSON parsing
- `tests/contract/Test-ProfileInvariants.ps1` — invariant validation harness
