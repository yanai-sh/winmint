# External Integrations

Snapshot note: updated 2026-06-29. Onboarding/audit snapshot — not a continuous authoritative source.

## Core Sections (Required)

### 1) External APIs and Services

| Service | How accessed | Purpose | Evidence |
|---------|-------------|---------|----------|
| Windows DISM (`dism.exe`) | CLI invocation | Mount/unmount/commit `install.wim`; apply drivers, packages, tweaks | `src/runtime/image/Engine.ps1` |
| Windows ADK (`oscdimg.exe`) | CLI invocation | Assemble bootable ISO | `README.md`, `config/release-readiness.json` |
| winget | CLI at FirstLogon | GUI apps, Microsoft apps, Store-backed packages | `src/runtime/firstlogon/Modules/PackageManagers.ps1`, `config/packages.json` |
| Scoop | CLI at FirstLogon | User-local developer CLI tools (MinGit, Starship, Neovim) | `src/runtime/firstlogon/Modules/PackageManagers.ps1` |
| winget Coreutils | CLI at FirstLogon | Baseline native UNIX-style host CLI (`Microsoft.Coreutils`) | `src/runtime/firstlogon/Modules/PackageManagers.ps1` |
| Microsoft Update Catalog | HTTP (opt-in `-UpdateImage Stable25H2`) | Offline cumulative/checkpoint MSUs | `README.md` |
| Microsoft Download Center | HTTP (`SurfaceCatalog` driver source) | Official Surface driver MSI packages | `config/surface-drivers.json`, `AGENTS.md` |
| GitHub Releases | HTTP (bootstrap) | Release `.zip` + `.sha256` verification | `winmint.ps1`, `AGENTS.md` |
| Cloudflare Workers | HTTP handler | `winmint.yanai.sh` bootstrap alias | `cloudflare/winmint/src/index.js` |
| Microsoft Store / msstore winget | winget CLI | PowerShell 7 and other Store-backed apps | `config/packages.json` |
| Direct download | HTTP (narrow exception) | Reserved; no approved pinned payloads currently | `AGENTS.md` |
| Hyper-V | PowerShell cmdlets (`Get-VM`, checkpoints) | VM acceptance harness | `tools/vm/Invoke-WinMintVmAcceptance.ps1` |
| Hyper-V PowerShell Direct | `Invoke-Command` to guest | Poll `state.json`, pull logs, OOBE screenshot | `tools/vm/lib/VmGuest.ps1` |
| Direct2D (Vortice.Direct2D1) | .NET AOT in `apps/setup-shell/` | Fullscreen setup-shell splash during FirstLogon | `apps/setup-shell/WinMintSetupShell.csproj` |
| Win32 user32/gdi32 | P/Invoke in VM screenshot helper | `PrintWindow` capture of `WinMintSetupShellWindow` | `tools/vm/lib/VmEvidence.ps1` |

### 2) Credentials and Secrets

- No credentials stored in the repo.
- Build profile may contain a `password` field for unattended local-account builds; supplied at `new` time — never committed.
- Cloudflare Worker deployment uses external `wrangler` credentials.
- Surface catalog downloads verified against Microsoft-owned URLs; no API keys.

### 3) Databases and Storage

- No database. File-based JSON contracts:
  - `BuildProfile.json`, `BuildManifest.json` (embedded audit records) — per build in `output/`
  - `state.json` — FirstLogon agent retry state on installed machine
  - `runtime-state.json` — unified provisioning projection on guest (strangler over legacy control/status files)
  - `acceptance-result.json` — VM acceptance verdict in `output/vm-acceptance/` (gitignored)
  - `setup-shell-control.json`, `setup-shell-status.json` — legacy FirstLogon splash IPC on guest
  - `managed-run.json` — active agent-managed VM run handle (`output/vm-acceptance/`)
  - `config/hardware-acceptance.json` — machine inventory and required checks (not runtime state)

### 4) Monitoring and Observability

- No external APM or logging pipeline.
- Build progress: structured JSON events from PowerShell stdout via the WebView2 wizard bridge.
- VM acceptance: live-teed `run.log` + `acceptance-result.json` per run.
- Agent diagnostics: `WinMintAgent-events.jsonl` (diagnostic-only JSONL in agent logs).

### 5) Evidence

- `AGENTS.md` — package source policy, download constraints
- `apps/setup-shell-web/WizardBridge.cs` — wizard host bridge
- `cloudflare/winmint/src/index.js`
- `config/packages.json`, `config/surface-drivers.json`, `config/hardware-acceptance.json`
- `tools/vm/WinMint-VmConsole.ps1` — PowerShell Direct + OOBE screenshot
- `docs/VM-Acceptance.md`
