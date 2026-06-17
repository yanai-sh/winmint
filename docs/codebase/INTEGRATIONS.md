# External Integrations

Snapshot note: this document reflects the current development state of the repo as scanned on 2026-06-17. It is an onboarding/audit snapshot, not a continuous authoritative source of truth.

## Core Sections (Required)

### 1) Integration Inventory

| System | Type (API/DB/Queue/etc) | Purpose | Auth model | Criticality | Evidence |
|--------|---------------------------|---------|------------|-------------|----------|
| Windows DISM / Storage / registry / Setup APIs | Host OS tooling | Mount source ISO, inspect WIM metadata, service images, edit offline/live registry, run setup phases. | Local administrator token. | High | `tools/ui-bridge/Get-UiIsoMetadata.ps1`, `src/runtime/image/Private/Image/Staging.ps1`, `src/runtime/image/Private/Image/Unattend.ps1`, `src/runtime/setup/SetupComplete.ps1` |
| GitHub Releases API | HTTPS API | Bootstrap release lookup and build-time latest release asset lookup for payloads such as PowerShell/ViveTool/Cascadia/winget assets; thide is installed from its upstream release when selected. | Public API with `User-Agent`; no repo secret in code. | High | `winmint.ps1`, `src/runtime/image/Private/PayloadStore.ps1`, `src/runtime/image/Private/Image/Packages.ps1`, `src/runtime/image/Private/Image/Staging.ps1`, `src/runtime/firstlogon/Modules/TilingDesktop.ps1` |
| Microsoft Update Catalog | HTTPS web endpoint | Resolve and download stable 25H2 update payloads with SHA256 metadata. | Public Microsoft endpoint. | High when `Stable25H2` is selected | `src/runtime/image/Private/UpdatePayloads.ps1`, `README.md` |
| Microsoft Defender definition endpoint | HTTPS endpoint | Acquire Defender offline image update payloads. | Public Microsoft endpoint. | Medium | `src/runtime/image/Private/UpdatePayloads.ps1` |
| Microsoft Download Center (Surface driver catalog) | HTTPS web endpoint | Resolve and download the official Surface driver/firmware MSI for a `SurfaceCatalog` device id, then run the safe offline classification path. | Public Microsoft endpoint; host allowlist restricted to `download.microsoft.com`/`www.microsoft.com`, ownership/signature evidence verified before injection. | High when `-DriverSource SurfaceCatalog` is selected | `config/surface-drivers.json`, `src/runtime/image/Private/Image/Drivers.ps1`, `README.md` |
| winget / msstore | Package manager sources | Install GUI/system apps, Store-backed Raycast, amd64 Everything Beta, PowerShell/Terminal fallback, and runtime tools. | User/package agreement flags; no app secrets. | High for FirstLogon modules | `config/packages.json`, `src/runtime/firstlogon/Agent.Runtime.ps1`, `src/runtime/setup/SetupComplete/Toolchain.ps1` |
| voidtools direct installer | HTTPS download | Install the pinned native Everything 1.5 ARM64 backend when Raycast is selected on ARM64 media. | Public upstream installer; SHA256 verified before execution. | Medium for ARM64 Raycast builds | `config/packages.json`, `src/runtime/firstlogon/Agent.Runtime.ps1`, `src/runtime/firstlogon/Modules/Raycast.ps1` |
| Raycast extension URL scheme | Local app protocol | Request curated Raycast extensions during FirstLogon after Raycast is installed. | User-context app protocol; no API keys. | Medium when Raycast selected | `src/runtime/firstlogon/Modules/Raycast.ps1`, `src/runtime/image/Private/InstallPlan.ps1` |
| Scoop | Package manager | Install user-local developer CLIs such as MinGit, Starship, and Neovim. | Official installer download; no app secrets. | High for developer baseline | `config/packages.json`, `src/runtime/firstlogon/Agent.Runtime.ps1`, `src/runtime/firstlogon/Modules/PackageManagers.ps1` |
| Cloudflare Workers | Edge runtime | Serve `winmint.yanai.sh` bootstrap and `/cli` wrapper. | Wrangler/Cloudflare deployment credentials outside repo. | Medium | `cloudflare/winmint/src/index.js`, `cloudflare/winmint/wrangler.jsonc`, `cloudflare/winmint/README.md` |
| Hyper-V | Host virtualization | Build/test VM acceptance profiles and guest acceptance checks. | Local administrator token / PowerShell Direct. | Medium for acceptance testing | `tools/vm/Build-And-TestVm.ps1`, `tools/vm/New-WinMintTestVm.ps1`, `tests/profiles/hyper-v-install-arm64.json` |
| UEFI:NTFS helper image | GitHub raw asset | Boot UEFI-only NTFS USB installer media. | Public raw GitHub URL; SHA256 checked in code. | Medium when `-WriteUsb` is used | `src/runtime/image/Private/UsbMedia.ps1`, `README.md` |
| Windhawk mod source | HTTPS endpoint | Download/restore selected Windhawk mod source and DLL assets during setup. | Public endpoint. | Medium when Windhawk selected | `src/runtime/setup/WindhawkBootstrap.ps1`, `src/runtime/setup/WindhawkBootstrap.Helpers.ps1` |

### 2) Data Stores

| Store | Role | Access layer | Key risk | Evidence |
|-------|------|--------------|----------|----------|
| `BuildProfile.json` | Build intent consumed by engine/setup/agent. | `src/runtime/image/Private/Config/Profile.ps1`, `tools/ui-bridge/New-UiBuildProfile.ps1` | Contract drift between GUI, CLI, schema, and setup consumers. | `schemas/winmint.buildprofile.schema.json`, `apps/gui/src/core/profile.rs` |
| `BuildManifest.json` / report artifacts | Machine-readable build outcome, payload facts, recovery/tweak audit outputs. | `src/runtime/image/Private/Manifest.ps1`, `src/runtime/image/Reports.ps1` | Unsupported claims if facts are inferred outside manifest helpers or install-plan facts. | `schemas/winmint.buildmanifest.schema.json`, `src/runtime/image/Private/Manifest.ps1`, `src/runtime/image/Reports.ps1` |
| `BuildDelta.json` | Normalized backend audit of intended changes (phase/kind/default/requires/suppressedBy/changes/artifacts/reversible/source) consumed by GUI review, CLI summaries, and reports. | `src/runtime/image/Private/Audit.ps1` (`New-WinMintBuildDeltaCatalog`, `Save-WinMintBuildDeltaCatalog`). | Delta records drift from actual servicing if contributors bypass the catalog helpers. | `schemas/winmint.builddelta.schema.json`, `src/runtime/image/Private/Audit.ps1`, `output/WinMint-BuildDelta.json` |
| `%LOCALAPPDATA%\WinMint\state.json` | FirstLogon retry/resume state. | `src/runtime/firstlogon/Agent.Runtime.ps1` | Partial state or stale step status across failed/rebooted runs. | `schemas/winmint.agentstate.schema.json`, `src/runtime/firstlogon/Start-WinMintAgent.ps1` |
| `%LOCALAPPDATA%\WinMint\Logs` | FirstLogon event and command logs. | `src/runtime/firstlogon/Start-WinMintAgent.ps1`, `src/runtime/firstlogon/Agent.Console.ps1` | Logs can contain installer output; redaction policy is `[TODO]`. | `src/runtime/firstlogon/Start-WinMintAgent.ps1`, `src/runtime/firstlogon/Agent.Runtime.ps1` |
| `%TEMP%\Win11ISO_dependency_cache` and output work dirs | Cached downloads, staged ISO/intermediate build state. | `src/runtime/image/Private/Runtime.ps1`, `src/runtime/image/Private/IsoStageCache.ps1`, `src/runtime/image/Private/IntermediatesCache.ps1` | Cache invalidation/fingerprint mistakes can reuse stale payloads. | `src/runtime/image/Private/Runtime.ps1`, `src/runtime/image/Private/IntermediatesCache.ps1` |

### 3) Secrets and Credentials Handling

- Credential sources: CLI local-account password via `-Password`, `-PasswordPath`, or `-PasswordEnvVar`; GitHub Actions uses `${{ github.token }}` for release publishing; Cloudflare deploy credentials are outside repo and not represented in `wrangler.jsonc`.
- Hardcoding checks: package IDs, generic Windows setup keys, public URLs, and SHA256 constants are checked in; no API tokens or Cloudflare secrets were found in source files inspected.
- Rotation or lifecycle notes: release publishing token lifecycle is managed by GitHub Actions; Cloudflare credential lifecycle is `[ASK USER]`; local-account password cleanup is implemented in setup/FirstLogon code paths but an end-to-end redaction policy is `[ASK USER]`.

### 4) Reliability and Failure Behavior

- Retry/backoff behavior: FirstLogon records per-step attempts and skips completed `ok` steps unless `-Force`; WSL virtualization errors can return retry/reboot state; package install failures are generally recorded rather than always blocking setup.
- Release-channel policy: external payload acquisition should prefer latest stable releases unless a product contract names an exception. Current exception: Raycast file search uses `voidtools.Everything.Beta` on amd64/x86-64, and a pinned SHA256-verified upstream `Everything-1.5.0.1415b.ARM64.en-US-Setup.exe` on ARM64 because the winget beta package has no ARM64 installer.
- Timeout policy: GitHub API reachability preflight uses `-TimeoutSec`; many package/download operations rely on platform/tool defaults, so a repo-wide timeout policy is `[ASK USER]`.
- Circuit-breaker or fallback behavior: bootstrap refuses releases without a `.sha256`; update payload downloads verify hashes/signatures where implemented; `SetupComplete` skips winget toolchain when outbound HTTPS to Microsoft is unavailable; oscdimg can be located from installed/downloaded ADK sources.

### 5) Observability for Integrations

- Logging around external calls: engine logs through console helpers and manifests; FirstLogon writes command stdout/stderr logs and JSONL events; Cloudflare Worker returns plain-text status codes.
- Metrics/tracing coverage: no central metrics, tracing, APM, or monitoring config was found.
- Missing visibility gaps: remote package-manager reliability, Worker health, and download latency/error trends are `[TODO]`.

### 6) Evidence

- `winmint.ps1`
- `config/packages.json`
- `src/runtime/image/Private/Manifest.ps1`
- `src/runtime/image/Private/UpdatePayloads.ps1`
- `src/runtime/image/Private/PayloadStore.ps1`
- `src/runtime/image/Private/Image/Drivers.ps1`
- `config/surface-drivers.json`
- `src/runtime/image/Private/UsbMedia.ps1`
- `src/runtime/firstlogon/Agent.Runtime.ps1`
- `src/runtime/firstlogon/Modules/Wsl.ps1`
- `src/runtime/setup/SetupComplete/Toolchain.ps1`
- `cloudflare/winmint/src/index.js`
- `.github/workflows/release.yml`
