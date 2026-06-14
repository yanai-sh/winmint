# External Integrations

## 1) Integration Inventory

| System | Type | Purpose | Auth model | Criticality | Evidence |
|--------|------|---------|------------|-------------|----------|
| GitHub Releases API | HTTPS API | Bootstrap release lookup; build-time payload discovery for PowerShell, Cascadia Code, winget-cli, and ViVeTool. | Public API with `User-Agent`; no token observed in product scripts. | High | `winmint.ps1`, `src/runtime/image/Private/Image/Packages.ps1`, `src/runtime/image/Private/Image/Assets.ps1` |
| GitHub release assets / raw GitHub | HTTPS downloads | Download release zip/checksum and upstream payload archives. | Public HTTPS. | High | `winmint.ps1`, `docs/Distribution.md`, `cloudflare/winmint/wrangler.jsonc` |
| Cloudflare Workers | Edge Worker | Serves `winmint.yanai.sh` bootstrap and `/cli` wrapper. | Cloudflare deployment via Wrangler; runtime requests are unauthenticated GET/HEAD. | Medium | `cloudflare/winmint/src/index.js`, `cloudflare/winmint/wrangler.jsonc` |
| Windows DISM / Imaging APIs | OS tooling/API | Mount, inspect, and service Windows WIM/ESD images. | Local Administrator. | High | `src/runtime/image/Private/Image/Staging.ps1`, `tools/ui-bridge/Get-UiIsoMetadata.ps1` |
| Windows Storage APIs | OS tooling/API | Mount/dismount source ISOs. | Local Administrator. | High | `src/runtime/image/Private/Pipeline.ps1`, `tools/ui-bridge/Get-UiIsoMetadata.ps1` |
| Windows ADK `oscdimg.exe` | Local external tool | Assemble bootable ISO output. | Local executable; may be installed/downloaded through winget/ADK. | High | `src/runtime/image/Private/Image/Packages.ps1`, `README.md` |
| winget / msstore | Package manager | Install GUI/system apps and Store-backed packages during FirstLogon or generate handoff. | User/system package manager agreements; no repo secret. | High | `config/packages.json`, `src/runtime/firstlogon/Agent.Runtime.ps1`, `src/runtime/image/Reports.ps1` |
| Scoop | Package manager | Install user-local developer CLI tools such as MinGit, Starship, and Neovim. | Official install script from `https://get.scoop.sh`; no repo secret. | High | `config/packages.json`, `src/runtime/firstlogon/Agent.Runtime.ps1` |
| Microsoft Store / AppX | OS package platform | AppX deprovisioning, Desktop App Installer/winget provisioning, Store source installs. | Local Windows APIs and package manager. | High | `src/runtime/image/Private/Image/Staging.ps1`, `src/runtime/image/Private/Image/Assets.ps1`, `config/packages.json` |
| Hyper-V PowerShell | Local OS API | VM test harnesses and guest acceptance helpers. | Local Administrator. | Low for product, high for VM tests | `tools/vm/Build-And-TestVm.ps1`, `tools/vm/New-WinMintTestVm.ps1` |
| GitHub CLI (`gh`) | CLI API client | Release workflow creates/uploads GitHub release assets. | `GH_TOKEN` from GitHub Actions. | Medium | `.github/workflows/release.yml` |

## 2) Data Stores

| Store | Role | Access layer | Key risk | Evidence |
|-------|------|--------------|----------|----------|
| JSON files in `config/` | Package, removal, tweak, unattend, and release policy catalogs. | Engine/profile/setup/reporting scripts. | Schema or catalog drift changes shipped behavior. | `config/packages.json`, `config/appx-removal.json`, `config/tweaks.json` |
| JSON schemas in `schemas/` | Build profile, build manifest, and agent state contracts. | Validation modules and contract tests. | Contract mismatch between UI, engine, and setup/agent. | `schemas/*.json`, `tools/validation/Modules/Schemas.ps1` |
| `%LOCALAPPDATA%\WinMint\state.json` | FirstLogon agent retry/resume state. | `src/runtime/firstlogon/Agent.Runtime.ps1` | Corrupt or stale state can affect idempotent reruns. | `src/runtime/firstlogon/Agent.Runtime.ps1`, `schemas/winmint.agentstate.schema.json` |
| `output/` | Local build reports, manifests, dry-run artifacts, ISO outputs, and headless state. | Engine/reporting/headless modules. | Generated artifacts can contain sensitive install material if ACLs fail. | `src/runtime/image/Reports.ps1`, `src/runtime/image/Private/Headless.ps1`, `.gitignore` |
| `%LOCALAPPDATA%\WinMint\versions\<version>` | Bootstrap-installed release bundles. | `winmint.ps1` | Missing marker or required files triggers reinstall. | `winmint.ps1` |
| `C:\ProgramData\WinMint\Logs` | SetupComplete and FirstLogon machine logs. | `src/runtime/setup/SetupComplete.ps1`, `src/runtime/setup/FirstLogon.ps1` | Logs may reveal operational details; location is Administrators-readable per comments. | `src/runtime/setup/SetupComplete.ps1` |

The repository has no configured database, queue, cache server, ORM, or service mesh.

## 3) Secrets and Credentials Handling

- Credential sources: CLI supports `-Password`, `-PasswordPath`, and `-PasswordEnvVar`; build profiles may include a password only when `identity.passwordIncluded` is true; GitHub release workflow uses `GH_TOKEN`.
- Hardcoding checks: generic Windows setup product keys are intentional in `src/runtime/image/Private/Config/Profile.ps1`; no committed `.env.example` or secret template exists.
- Lifecycle notes: public build-profile artifacts remove password and autologon state; SetupComplete deletes `C:\Windows\Panther\unattend*.xml`; FirstLogon clears autologon credentials on success.
- Rotation/lifecycle for external deployment credentials is [TODO].

## 4) Reliability and Failure Behavior

- Retry/backoff behavior: FirstLogon agent records step attempts and statuses in `state.json`; bootstrap reuses completed install markers and reinstalls incomplete/mismatched bundles; winget/Scoop path discovery waits in loops.
- Timeout policy: GitHub API reachability preflight uses a 5-second timeout; broader download and package install timeouts are [TODO].
- Fallback behavior: winget/PowerShell/font payload lookup falls back to cached files in several engine paths; CLI can self-elevate when `-AllowElevate` is passed; UI ISO probe can relaunch elevated and return JSON through a relay file.
- Circuit breaker: no explicit circuit-breaker abstraction appears in the scanned files.

## 5) Observability for Integrations

- Logging around external calls: bootstrap logs release queries/downloads/hash verification; engine logs payload staging and records payload hashes in `BuildManifest`; FirstLogon records command stdout/stderr files and JSONL events.
- Metrics/tracing: no metrics or distributed tracing config appears in the repo.
- Missing visibility gaps: package-manager install failures are logged, but central telemetry/monitoring is absent; deployment health for Cloudflare Worker is [TODO].

## 6) Evidence

- `winmint.ps1`
- `cloudflare/winmint/src/index.js`
- `cloudflare/winmint/wrangler.jsonc`
- `.github/workflows/release.yml`
- `config/packages.json`
- `src/runtime/image/Private/Image/Staging.ps1`
- `src/runtime/image/Private/Image/Packages.ps1`
- `src/runtime/image/Private/Image/Assets.ps1`
- `src/runtime/firstlogon/Agent.Runtime.ps1`
- `tools/ui-bridge/Get-UiIsoMetadata.ps1`
