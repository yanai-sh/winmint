# Technology Stack

Snapshot note: updated 2026-06-20. Onboarding/audit snapshot — not a continuous authoritative source.

## Core Sections (Required)

### 1) Runtime Summary

| Area | Value | Evidence |
|------|-------|----------|
| Primary language (backend) | PowerShell 7.6.2+ | `AGENTS.md`, `src/runtime/image/WinMint.ps1` |
| Primary language (GUI) | Rust (stable) | `apps/gui/Cargo.toml`, `.github/workflows/ci.yml` |
| Primary language (bootstrap CDN) | JavaScript (ES module) | `cloudflare/winmint/src/index.js` |
| Runtime constraint | Windows 11 build host; Administrator elevation for real builds | `README.md` |
| Package manager (Rust) | Cargo workspace (`resolver = "2"`) | `Cargo.toml` |
| Build system | Cargo for Rust; PowerShell dot-source load order for backend | `Cargo.toml`, `src/runtime/image/WinMint.ps1` |

### 2) Production Frameworks and Dependencies

| Dependency | Version | Role in system | Evidence |
|------------|---------|----------------|----------|
| gpui | 0.2.2 | Native Windows GUI framework (Zed-derived retained-mode UI) | `Cargo.toml` |
| gpui-animation | 0.2.4 | State-driven hover/transition animations in the wizard | `Cargo.toml` |
| serde | 1.0 | JSON serialization for bridge data structs | `Cargo.toml` |
| serde_json | 1.0 | JSON de/serialization at bridge boundary | `Cargo.toml` |
| embed-resource | 3.0 (build-dep) | Embeds Windows `.rc` resource (icon, version manifest) into EXE | `apps/gui/Cargo.toml` |

> All Rust deps are GUI-only; the PowerShell engine has no external module dependencies beyond what ships with PowerShell 7.

### 3) Development Toolchain

| Tool | Purpose | Evidence |
|------|---------|----------|
| PSScriptAnalyzer | PowerShell static linting | `PSScriptAnalyzerSettings.psd1`, `AGENTS.md` |
| `tools/validation/Validate.ps1` | Repo-wide syntax + contract validation; `-RunAnalyzer` flag runs PSScriptAnalyzer | `AGENTS.md` |
| `tests/contract/Test-ProfileInvariants.ps1` | Profile schema + tweak parity smoke tests (no ISO required) | `AGENTS.md` |
| `cargo check` / `cargo test` | Rust type-check and unit tests for GUI crate | `.github/workflows/ci.yml` |
| GitHub Actions | CI on `main`, `architecture/**`, `codex/**` branches | `.github/workflows/ci.yml` |
| `tools/release/New-WinMintReleaseBundle.ps1` | Produces `dist/WinMint-<version>.zip` + `.sha256` | `AGENTS.md` |

### 4) Key Commands

```powershell
# Validate syntax and profile invariants (no ISO needed)
pwsh -NoProfile -File tools\validation\Validate.ps1 -RunAnalyzer
pwsh -NoProfile -File tests\contract\Test-ProfileInvariants.ps1

# Author a profile and dry-run a build
pwsh -NoProfile -File WinMint-CLI.ps1 new BuildProfile.json
pwsh -NoProfile -File WinMint-CLI.ps1 build BuildProfile.json -DryRun

# Launch GUI
pwsh -NoProfile -File WinMint-GUI.ps1

# Rust GUI (dev)
cargo check --manifest-path apps/gui/Cargo.toml
cargo test --manifest-path apps/gui/Cargo.toml

# Release bundle
pwsh -NoProfile -File tools\release\New-WinMintReleaseBundle.ps1 -Version v0.2.0
```

### 5) Environment and Config

- Config sources: `config/packages.json`, `config/tweaks.json`, `config/autounattend.xml`, `config/surface-drivers.json`, `config/release-manifest.json`, `config/release-readiness.json`, `config/hardware-acceptance.json`
- Required env vars: none persisted; build paths resolved at runtime from repo root
- Deployment/runtime constraints: Windows 11 host, PowerShell 7.6.2+, Administrator elevation for real DISM builds, `oscdimg.exe` from Windows ADK, DISM version ≥ source image build

### 6) Evidence

- `Cargo.toml` — workspace manifest
- `apps/gui/Cargo.toml` — GUI crate dependencies
- `.github/workflows/ci.yml` — CI toolchain
- `PSScriptAnalyzerSettings.psd1` — linter config
- `AGENTS.md` — coding contract and runtime requirements
