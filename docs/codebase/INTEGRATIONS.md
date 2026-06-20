# External Integrations

Snapshot note: updated 2026-06-20. Onboarding/audit snapshot — not a continuous authoritative source.

## Core Sections (Required)

### 1) External APIs and Services

| Service | How accessed | Purpose | Evidence |
|---------|-------------|---------|----------|
| Windows DISM (`dism.exe`) | CLI invocation | Mount/unmount/commit `install.wim`; apply drivers, packages, tweaks | `src/runtime/image/Engine.ps1` |
| Windows ADK (`oscdimg.exe`) | CLI invocation | Assemble bootable ISO from staged WIM + setup files | `README.md`, `AGENTS.md` |
| winget | CLI invocation at FirstLogon | Install GUI apps, Microsoft apps, signed installers, Store-backed packages | `src/runtime/firstlogon/Modules/PackageManagers.ps1` |
| Scoop | CLI invocation at FirstLogon | Install user-local developer CLI tools (MinGit, Starship, Neovim) | `src/runtime/firstlogon/Modules/PackageManagers.ps1` |
| Microsoft Update Catalog | HTTP download (engine, opt-in only) | Cumulative/checkpoint update MSUs for `Stable25H2` offline pre-update path | `README.md` |
| Microsoft Download Center | HTTP download (engine, Surface catalog) | Official Surface driver MSI packages when `SurfaceCatalog` driver source used | `AGENTS.md` |
| GitHub Releases | HTTP download (bootstrap) | `winmint.ps1` downloads release `.zip` + `.sha256` for SHA256 verification | `AGENTS.md` |
| Cloudflare Workers | HTTP request handler | `winmint.yanai.sh` redirects `irm ... | iex` to latest release zip | `cloudflare/winmint/src/index.js` |
| Microsoft Store / msstore winget source | winget CLI | Store-backed packages (Raycast, PowerShell 7, etc.) | `AGENTS.md`, `config/packages.json` |
| GitHub Direct Download (narrow exception) | HTTP download | SHA256-verified native Everything 1.5 ARM64 installer for Raycast backend | `AGENTS.md` |
| Hyper-V (`New-VM`, `Start-VM`, etc.) | PowerShell cmdlets | VM acceptance test harness | `tools/vm/` |

### 2) Credentials and Secrets

- No credentials are stored in the repo.
- Build profile may contain a `password` field for unattended local-account builds; supplied via `-Password`, `-PasswordPath`, or `-PasswordEnvVar` at `new` time — never committed.
- Cloudflare Worker deployment uses `wrangler` with account credentials external to this repo.
- Surface catalog downloads are verified against Microsoft-owned URLs and signature evidence; no API keys required.

### 3) Databases and Storage

- No database. State is file-based JSON:
  - `BuildProfile.json` — build intent (per build, in `output/`)
  - `BuildManifest.json` — engine output record (per build, in `output/`)
  - `BuildDelta.json` — audit of what WinMint intends to change (per build, in `output/`)
  - `state.json` — FirstLogon agent retry state (`%LOCALAPPDATA%\WinMint\state.json` on the installed machine)
  - `output/.state/*.json` — build run state snapshots

### 4) Monitoring and Observability

- No external APM or logging pipeline.
- Build progress is streamed via structured JSON events (`BridgeProgressEvent` — `Time`, `Stage`, `Level`, `Message`) captured from PowerShell stdout by the Rust GUI bridge.
- VM acceptance runs produce a `run.log` (teed live) and `acceptance-result.json` in `output/vm-acceptance/`.
- `WinMint-DriverInventory.json` records driver include/defer decisions for Surface injection.

### 5) Evidence

- `AGENTS.md` — package source policy, Surface catalog, download constraints
- `apps/gui/src/bridge.rs` — bridge invocation and progress event parsing
- `cloudflare/winmint/src/index.js` — Cloudflare Worker source
- `config/packages.json` — winget/Store/Scoop package catalog
- `config/surface-drivers.json` — Surface device ID catalog
- `README.md` — external tool requirements (DISM, oscdimg, ADK)
