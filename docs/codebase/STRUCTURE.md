# Codebase Structure

Snapshot note: updated 2026-06-29. Focus: **setup-shell assets** and **VM smoke harness** layout.

## Core Sections (Required)

### 1) Top-Level Map (focus paths)

| Path | Purpose |
|------|---------|
| `apps/setup-shell/` | C#/.NET 10 AOT source for `WinMintSetupShell.exe` (Direct2D fullscreen splash) |
| `assets/runtime/setup/setup-shell/` | Published binaries + wizard web assets staged into ISO (`bin/x64`, `bin/arm64`, `tokens.json`, `index.html`) |
| `src/runtime/setup/WinMintSetupShell.Status.ps1` | PowerShell status/control writer consumed by native shell |
| `schemas/winmint.setupshell*.schema.json` | JSON Schema for control + status files |
| `tests/fixtures/setup-shell/` | Golden JSON fixtures for contract tests + local harness |
| `tests/profiles/hyper-v-smoke-arm64.json` | Lean VM acceptance profile (`profileName: Hyper-V Smoke`) |
| `tools/vm/` | Hyper-V acceptance orchestration (smoke/full) |
| `tools/dev/Show-WinMintSplash.ps1` | Local fullscreen splash preview (one command) |
| `tests/setup-shell/` | Setup-shell integration tests + `SetupShell.TestSupport.ps1` |
| `tests/integration/Test-WinMintProvisioningLockPreview.ps1` | Provisioning-lock engage/release integration test |
| `tools/release/Build-WinMintSetupShell.ps1` | Publish native shell into `assets/runtime/setup/setup-shell/bin/` |
| `.agents/skills/vm-acceptance-orchestration/` | Agent skill for managed smoke runs |

See `docs/Project-Structure.md` for the full repo map.

### 2) Setup-Shell File Map

```
apps/setup-shell/
  Program.cs              # Entry; logs host=native
  SetupShellHost.cs       # Direct2D window + JSON poll loop
  AppOptions.cs           # CLI args (--shell-root, --status, --control)
  JsonContracts.cs        # Status/control DTOs
  NativeMethods.cs        # Win32 P/Invoke
  WinMintSetupShell.csproj

assets/runtime/setup/setup-shell/
  bin/x64/WinMintSetupShell.exe
  bin/arm64/WinMintSetupShell.exe
  tokens.json             # Design tokens for splash
  index.html, app.js, styles.css  # wizard assets

src/runtime/setup/
  WinMintSetupShell.Status.ps1   # Start/pump/stop shell; write status JSON
  FirstLogon.Host.ps1            # Resolve-WinMintFirstLogonAgentMode
  FirstLogon.Runtime.ps1         # Shell + agent lifecycle
  FirstLogon.Transaction.ps1     # Status pump during agent wait

src/runtime/image/Private/Image/SetupPayloadStaging.ps1
  Copy-WinMintSetupShellPayload   # ISO staging hook
```

Staged on ISO at: `C:\Windows\Setup\Scripts\setup-shell\` (exe + tokens + hero PNGs).

Runtime JSON on guest:

- `%LOCALAPPDATA%\WinMint\setup-shell-control.json`
- `%LOCALAPPDATA%\WinMint\setup-shell-status.json`
- `%LOCALAPPDATA%\WinMint\Logs\SetupShell.log`

### 3) VM Smoke Harness File Map

```
tools/vm/
  Invoke-WinMintVmAcceptance.ps1      # Main orchestrator (-Phase, -Tier, -ManagedRun)
  Start-WinMintVmAcceptanceManaged.ps1 # Detached agent entry
  Get-WinMintVmAcceptanceStatus.ps1   # Poll managed run
  WinMint-VmConsole.ps1               # OOBE poll, screenshot, evidence scoring, 90s smoke hold
  Build-And-TestVm.ps1                # Build fingerprint + ISO + VM boot
  New-WinMintTestVm.ps1               # Gen2 VM create/boot
  Test-WinMintHyperVProfile.ps1       # Profile invariant gate (-Tier Smoke|Full)
  New-WinMintHyperVProfile.ps1        # Author smoke/full profiles
  Push-WinMintSetupScripts.ps1        # Fast push (Headless — no splash)
  Invoke-WinMintVmCheckpoint.ps1      # PostSetup snapshot save/restore
  Invoke-WinMintGuestPesterAcceptance.ps1   # Live inspect signals (Pester)
  Test-WinMintOfflineImageRemovals.ps1      # Post-build offline WIM drift gate
  Warm-WinMintBuildCache.ps1

output/vm-acceptance/
  managed-run.json                    # Active managed run handle
  <VMName>-<stamp>/                   # Per-run evidence folder
    run.log
    acceptance-result.json
    setup-shell-watch.json
    oobe-splash.png                   # when capture succeeds
```

### 4) Entry Points (focus)

| Entry | Invocation |
|-------|------------|
| Shipped FirstLogon splash | `FirstLogon.ps1` → `-AgentMode Auto` → `SetupShell` |
| VM smoke (interactive) | `tools/vm/Invoke-WinMintVmAcceptance.ps1 -ProfilePath tests\profiles\hyper-v-smoke-arm64.json` |
| VM smoke (agent) | `Start-WinMintVmAcceptanceManaged.ps1` + `Get-WinMintVmAcceptanceStatus.ps1` |
| Local shell harness | `tests/setup-shell/Test-WinMintSetupShell.ps1` |
| Publish shell binary | `tools/release/Build-WinMintSetupShell.ps1` |

### 5) Module Boundaries (focus)

| Boundary | Owns | Must not own |
|----------|------|--------------|
| `apps/setup-shell/` | Render splash from JSON; desktop guard hooks | Agent modules, winget, DISM |
| `WinMintSetupShell.Status.ps1` | Status projection + process start/stop | Direct2D drawing |
| `tools/vm/` | Evidence collection, Hyper-V lifecycle | Product profile defaults |
| `Push-WinMintSetupScripts.ps1` | Push updated scripts to running guest | OOBE splash validation (uses Headless) |

### 6) Evidence

- `apps/setup-shell/WinMintSetupShell.csproj`
- `assets/runtime/setup/setup-shell/`
- `src/runtime/setup/WinMintSetupShell.Status.ps1`
- `tools/vm/WinMint-VmConsole.ps1`
- `tests/profiles/hyper-v-smoke-arm64.json`
- `docs/VM-Acceptance.md`
