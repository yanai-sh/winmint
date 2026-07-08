# Architecture

Snapshot note: updated 2026-06-30. Focus: **setup-shell OOBE-like FirstLogon** and **VM smoke acceptance** integration.

## Core Sections (Required)

### 1) Architectural Style

- **Primary style:** Layered pipeline — UI/CLI creates intent; engine performs offline servicing; Windows Setup runs machine scripts; FirstLogon finishes live-user setup with optional fullscreen presentation.
- **Setup-shell seam:** Presentation is split from work. `WinMintSetupShell.exe` (native AOT) is a read-only view + desktop guard; PowerShell owns orchestration, agent launch, and JSON status writes.
- **VM harness:** Thin script composition — not a framework. Orchestrator delegates to single-purpose `tools/vm/*.ps1` scripts (`docs/VM-Acceptance.md`).

### 2) System Flow (product)

```
User → CLI/GUI → BuildProfile.json
  → Engine (DISM/WIM, stage setup payloads incl. WinMintSetupShell.exe)
  → ISO → Windows Setup → SetupComplete.ps1
  → FirstLogon.ps1 (-AgentMode Auto → SetupShell)
      → Start-WinMintProvisioningHost (fullscreen splash)
      → Start-WinMintAgent.ps1 (headless package/shell work)
      → status pump: agent state.json → setup-shell-status.json
      → Set-WinMintSetupShellControl phase transitions → shell exits
  → Invoke-WinMintFirstLogonReloadExplorerShell (Start pins; after splash)
  → Desktop revealed
```

### 3) Setup-Shell OOBE-Like Presentation

#### Intent

Shipped ISOs default to a **fullscreen OOBE-like splash** during FirstLogon; desktop is hidden until finalize. Console (Windows Terminal) and Headless modes are explicit diagnostics/VM-loop opt-ins (`FirstLogon.Host.ps1`, `docs/VM-Acceptance.md`).

#### Agent mode resolution

`Resolve-WinMintFirstLogonAgentMode` (`FirstLogon.Host.ps1`):

| Input | Resolved mode |
|-------|----------------|
| `WINMINT_FIRSTLOGON_MODE=headless` | `Headless` |
| `WINMINT_FIRSTLOGON_MODE=console` | `Console` |
| `WINMINT_FIRSTLOGON_MODE=oobe` / `setupshell` / `ui` | `SetupShell` |
| `-AgentMode Auto` (default) | `SetupShell` |
| `-AgentMode UI` | `SetupShell` |

#### Runtime components

| Component | Path | Role |
|-----------|------|------|
| Native host | `apps/setup-shell/` → `WinMintSetupShell.exe` | Direct2D fullscreen window (`WinMintSetupShellWindow`), polls JSON |
| Status writer | `src/runtime/setup/WinMintSetupShell.Status.ps1` | `Get-WinMintProvisioningProjection`: pipeline `progressPct`, group `steps`, devlog `taskLabel` (event-log hints + segment fallbacks), `elapsedMs` |
| Orchestration | `src/runtime/setup/FirstLogon.Runtime.ps1` | Starts shell, launches agent, drives control phases |
| Transaction | `src/runtime/setup/FirstLogon.Transaction.ps1` | Pumps status while waiting on agent (`Invoke-WinMintSetupShellStatusPumpTick`) |
| Staging | `src/runtime/image/Private/Image/SetupPayloadStaging.ps1` | Copies exe + `tokens.json` + hero assets into `C:\Windows\Setup\Scripts\setup-shell\` |
| Publish | `tools/release/Build-WinMintSetupShell.ps1` | AOT publish to `assets/runtime/setup/setup-shell/bin/{x64,arm64}/` |

#### JSON contracts (on installed machine)

| File | Writer | Reader | Schema |
|------|--------|--------|--------|
| `%LOCALAPPDATA%\WinMint\setup-shell-control.json` | FirstLogon (`Set-WinMintSetupShellControl`) | `WinMintSetupShell.exe` | `schemas/winmint.setupshellcontrol.schema.json` |
| `%LOCALAPPDATA%\WinMint\setup-shell-status.json` | `Update-WinMintSetupShellStatus` | `WinMintSetupShell.exe` | `schemas/winmint.setupshellstatus.schema.json` |
| `%LOCALAPPDATA%\WinMint\state.json` | Agent | Status writer | `schemas/winmint.agentstate.schema.json` |

Control `phase` values: `running` → `finishing` → `complete` (or `failed` / `reboot`). Control also persists `preAgentStage` (`locked` → `region` → `defaults` → `agent`). Status uses `progressMode: indeterminate` before agent modules start.

#### Native host behavior (`SetupShellHost.cs`)

- Creates topmost popup covering primary monitor; opaque WNDCLASS brush before Direct2D init.
- Timer-driven poll reads control + status JSON (`AppOptions`: `--shell-root`, `--status`, `--control`, `--poll-ms`).
- Renders group label, task label, progress bar from status (`Vortice.Direct2D1`).
- Resizes/repaints on display and DPI changes; `OnTimer` re-applies fullscreen bounds.
- Closes on control `complete`, `failed`, or `reboot` after start/complete dwell; `_firstPaintAt` fallback when D2D never paints.
- Logs `host=native aot=<arch>` to `%LOCALAPPDATA%\WinMint\Logs\SetupShell.log` (`Program.cs`).
- `DesktopGuard` hides taskbar, dismisses Start, blocks Win keys while active; `ClearNoWinKeys` on native dispose mirrors PS guard disable.

#### FirstLogon phase coupling (`FirstLogon.Runtime.ps1`)

1. **Agent launch:** `Start-WinMintProvisioningHost` → control `running`; start status pump.
2. **While agent runs:** transaction step calls `Invoke-WinMintSetupShellStatusPumpTick`.
3. **Finalize user shell:** control `finishing`; write Start pins and terminal profiles (registry only — no explorer kill).
4. **Finalize success:** control `complete`; `Wait-WinMintSetupShellProcess`; disable desktop guard; `Invoke-WinMintFirstLogonReloadExplorerShell`.
5. **Reboot path:** control `reboot`; shell exits; autologon/retry preserved; explorer reload skipped until next sign-in.

### 4) VM Smoke Acceptance Architecture

#### Orchestrator decomposition

```
Invoke-WinMintVmAcceptance.ps1
  ├─ BuildBoot → Build-And-TestVm.ps1
  │     ├─ Test-WinMintHyperVProfile.ps1 (-Tier Smoke)
  │     ├─ WinMint-CLI.ps1 build (-FastImage default)
  │     ├─ Build-WinMintSetupShell.ps1 (if staged binary missing)
  │     └─ New-WinMintTestVm.ps1 (Gen2, Secure Boot, vTPM)
  ├─ Wait → PowerShell Direct poll
  │     ├─ guest state.json until terminal
  │     ├─ Register-WinMintVmSetupShellWatchSample (process + phase)
  │     ├─ Invoke-WinMintVmGuestSetupShellScreenshot (optional)
  │     └─ Smoke: hold 90s min FirstLogon activity before accepting terminal
  ├─ Inspect → Invoke-WinMintGuestPesterAcceptance.ps1
  └─ Evidence → pull logs + Test-WinMintSetupShellAcceptanceEvidence
```

#### Managed agent entry

```
Start-WinMintVmAcceptanceManaged.ps1
  → detached pwsh child (-ManagedRun)
  → output/vm-acceptance/managed-run.json
Get-WinMintVmAcceptanceStatus.ps1
  → reads managed-run.json + acceptance-result.json
```

Single-flight enforced: second start throws unless `-Force` kills prior process tree.

#### Smoke-specific agent behavior

- Profile name `Hyper-V Smoke` triggers WSL runtime **skip** in `Wsl.ps1` (lean gate).
- Acceptance tier inferred from `profileName` or `-Tier Smoke`.
- Verdict: plumbing pass sufficient; setup-shell screenshot may be waived (`WinMint-VmConsole.ps1`).

#### Evidence artifact layout

`output/vm-acceptance/<VMName>-<stamp>/`:

- `run.log` — tee'd transcript from first line
- `acceptance-result.json` — flat verdict record (no formal schema yet)
- `setup-shell-watch.json` — live poll samples
- Guest pulls: `FirstLogon.log`, `SetupShell.log`, `setup-shell-control.json`, `state.json`
- `oobe-splash.png` — host-side screenshot when capture succeeds

### 5) Layer/Module Responsibilities (focus areas)

| Module | Owns | Must not own |
|--------|------|--------------|
| `apps/setup-shell/` | Direct2D render, JSON poll loop, window lifecycle | Agent steps, package installs |
| `WinMintSetupShell.Status.ps1` | Status projection from agent state | DISM, WIM |
| `FirstLogon.Runtime.ps1` | Shell/agent lifecycle, control phases | Offline servicing |
| `tools/vm/` | Hyper-V orchestration, evidence scoring | Product defaults |
| `src/runtime/firstlogon/` | Idempotent live-user modules | Splash UI |

### 6) Reused Patterns

| Pattern | Where | Why |
|---------|-------|-----|
| JSON file IPC | control/status between PS and AOT exe | Simple cross-language contract |
| Status pump tick | `FirstLogon.Transaction.ps1` | UI updates while agent blocks |
| Composable VM phases | `-Phase BuildBoot|Wait|Inspect|Evidence` | Resume long runs without rework |
| Fingerprint-gated ISO reuse | `Build-And-TestVm.ps1` | Skip 30–60 min DISM when unchanged |
| PostSetup checkpoint | Hyper-V snapshot | Amortize Setup for FirstLogon iteration |
| Plumbing vs evidence verdict | Smoke vs Full tiers | Fast lean gate without brittle screenshot requirement |

### 7) Known Architectural Risks (focus areas)

- **Setup-shell splash plumbing pending VM sign-off** (2026-06-30) — OOBE UX fixes landed in code; managed smoke must confirm `setupShell.plumbingOk` + `control.phase=complete`.
- **Screenshot capture is best-effort** on VM guests; smoke waives when logs prove native shell.
- **Push/iteration paths use Headless** — they do not prove splash on ISO installs.
- **No formal schema for `acceptance-result.json`** — intentional per `docs/VM-Acceptance.md`.
- **VM acceptance is local-only** — no CI end-to-end install gate.

### 8) Evidence

- `AGENTS.md` — FirstLogon load order, `-AgentMode Auto` setup shell default
- `src/runtime/setup/FirstLogon.Host.ps1` — mode resolution
- `src/runtime/setup/FirstLogon.Runtime.ps1` — shell lifecycle
- `src/runtime/setup/WinMintSetupShell.Status.ps1` — status writer
- `apps/setup-shell/SetupShellHost.cs`, `Program.cs` — native host
- `src/runtime/image/Private/Image/SetupPayloadStaging.ps1` — ISO staging
- `tools/vm/Invoke-WinMintVmAcceptance.ps1`, `WinMint-VmConsole.ps1`
- `docs/VM-Acceptance.md`
- `schemas/winmint.setupshellstatus.schema.json`, `schemas/winmint.setupshellcontrol.schema.json`
