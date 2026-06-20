# Codebase Structure

Snapshot note: updated 2026-06-20. Onboarding/audit snapshot — not a continuous authoritative source.

## Core Sections (Required)

### 1) Top-Level Map

| Path | Purpose | Evidence |
|------|---------|----------|
| `WinMint-CLI.ps1` | CLI entry point — verb dispatcher (`build`/`new`/`validate`/`list`/`clean`) | `AGENTS.md` |
| `WinMint-GUI.ps1` | GUI launcher script — compiles and runs `apps/gui/` | `README.md` |
| `winmint.ps1` | Remote bootstrap: download, SHA256-verify, temp-extract, launch, cleanup | `AGENTS.md` |
| `apps/gui/` | Rust/GPUI desktop wizard (frontend only — no DISM, no servicing) | `apps/gui/Cargo.toml` |
| `src/runtime/image/` | PowerShell engine: WIM servicing, profile normalization, DISM, reporting | `src/runtime/image/WinMint.ps1` |
| `src/runtime/firstlogon/` | FirstLogon agent: live-user setup (editors, WSL, shell layers, retry state) | `AGENTS.md` |
| `src/runtime/setup/` | Windows Setup phases: SetupComplete, Specialize, DefaultUser, FirstLogon bootstrap | `src/runtime/setup/` |
| `src/runtime/modules/` | Thin public module wrappers (`WinMint.Bootstrap`, `WinMint.Profile`, `WinMint.Engine`) | `AGENTS.md` |
| `config/` | Product policy: packages, tweaks, autounattend template, build-profiles, release gates | `docs/Project-Structure.md` |
| `schemas/` | JSON Schema for `BuildProfile`, `BuildManifest`, `state.json` | `AGENTS.md` |
| `assets/brand/` | Product mark and editable brand source files | `docs/Project-Structure.md` |
| `assets/runtime/` | Payloads staged into the image: cursors, fonts, wallpaper, account picture, desktop shell configs | `docs/Project-Structure.md` |
| `assets/ui/` | GUI preview imagery (editors, desktop, WSL logos) | `docs/Project-Structure.md` |
| `tools/ui-bridge/` | Bridge scripts called by the Rust GUI (`Get-UiIsoMetadata.ps1`, `New-UiBuildProfile.ps1`, `Start-UiBuildFromProfile.ps1`) | `apps/gui/src/bridge.rs` |
| `tools/validation/` | Repo-wide syntax + contract validation tooling | `AGENTS.md` |
| `tools/vm/` | Hyper-V VM acceptance harnesses | `AGENTS.md` |
| `tools/release/` | Release bundle assembly and publishing helpers | `AGENTS.md` |
| `tests/contract/` | Smoke tests and profile invariant tests (no ISO required) | `AGENTS.md` |
| `tests/fixtures/` | Local ISO/driver fixture roots (gitignored payloads) | `docs/Project-Structure.md` |
| `cloudflare/winmint/` | Cloudflare Worker for `winmint.yanai.sh` bootstrap alias | `AGENTS.md` |
| `output/` | Build artifacts (ISOs, state, manifests) — gitignored | `docs/Project-Structure.md` |

### 2) Entry Points

- **CLI:** `WinMint-CLI.ps1` — dot-sources `src/runtime/image/WinMint.ps1` (which loads the full engine), then dispatches verbs. Verb implementations live in `src/runtime/image/Cli.ps1`.
- **GUI:** `WinMint-GUI.ps1` — launches compiled Rust binary `apps/gui/bin/WinMint-GUI.exe`; binary calls `tools/ui-bridge/*.ps1` via child process for all backend work.
- **Bootstrap:** `winmint.ps1` — ephemeral download/verify/run via `irm https://winmint.yanai.sh | iex`.
- **FirstLogon:** `src/runtime/firstlogon/Agent.Runtime.ps1` — started by Windows at first logon; loads all `Modules/*.ps1` at script scope before running steps.
- **Engine load order:** `src/runtime/image/WinMint.ps1` dot-sources ~35 private modules in a fixed declared order. Never call sub-files directly.

### 3) Module Boundaries

| Boundary | What belongs here | What must not be here |
|----------|-------------------|------------------------|
| `apps/gui/` (Rust/GPUI) | Wizard flow, ISO selection, option toggles, profile creation, bridge calls | DISM, WIM servicing, offline registry edits, setup orchestration, live-user installs |
| `apps/gui/src/core/` | Typed UI intent/options helpers (enums, structs) | DISM, registry hive edits, Windows Setup |
| `apps/gui/src/bridge.rs` | Spawning `tools/ui-bridge/*.ps1` as child processes, JSON I/O | View/render logic |
| `apps/gui/src/components.rs` | Stateless `pub fn` builder functions (aliased `ui::`) | Internal state (split to submodules only after ~500 lines or when state needed) |
| `src/runtime/image/` | ISO extraction, WIM servicing, drivers, staged setup files, output ISO | GUI, user interaction, live-user app installs |
| `src/runtime/firstlogon/` | Live-user setup, WSL, editors, shell layers, retry state | Offline image servicing, destructive disk choices |
| `src/runtime/setup/` | Machine-phase setup during Windows install | User prompts, package source policy |
| `tools/ui-bridge/` | Bridge scripts synchronously invoked by Rust GUI | Product runtime logic |
| `tests/contract/` | Smoke tests and profile invariants | Shipped setup payloads |

### 4) Naming and Organization Rules

- **PowerShell files:** `PascalCase` verb-noun for public entry points (`WinMint-CLI.ps1`, `Get-UiIsoMetadata.ps1`); numbered prefix (`NN-<id>.ps1`) for ordered tweak modules
- **Rust files:** `snake_case` module files (`bridge.rs`, `state.rs`, `components.rs`)
- **Directory organization:** layer-based at top level; feature-based within `firstlogon/Modules/`
- **JSON contracts:** PascalCase keys (enforced via `serde(rename_all = "PascalCase")` in bridge structs)
- **Import/load:** PowerShell uses dot-source via `WinMint.ps1`; Rust uses `mod` declarations in `main.rs`; `components as ui` alias in `main.rs` for call-site brevity

### 5) Evidence

- `docs/Project-Structure.md` — canonical layout contract
- `src/runtime/image/WinMint.ps1` — engine load order (dot-source sequence)
- `apps/gui/src/main.rs` — Rust entry point and module declarations
- `apps/gui/src/bridge.rs` — UI-to-backend bridge pattern
- `AGENTS.md` — module boundary rules
