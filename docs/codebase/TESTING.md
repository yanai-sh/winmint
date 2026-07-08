# Testing Patterns

Snapshot note: updated 2026-06-30. Focus: **VM smoke automation** and **setup-shell (OOBE-like) FirstLogon** validation.

## Core Sections (Required)

### 1) Test Stack and Commands

| Layer | Runner | Command |
|-------|--------|---------|
| Contract (PowerShell) | Custom `Add-SmokeFailure` harness + optional Pester 5 | `pwsh -NoProfile -File tools\dev\Invoke-WinMintPesterContract.ps1` or `tests\contract\Test-ProfileInvariants.ps1` |
| Syntax / analyzer | `tools/validation/Validate.ps1` | `pwsh -NoProfile -File tools\validation\Validate.ps1 -RunAnalyzer` |
| Setup shell splash (local preview) | `tools/dev/Show-WinMintSplash.ps1` | `-Wizard` (default) opens WebView2 wizard; `-Native` runs Direct2D host |
| Setup shell integration test | `tests/setup-shell/Test-WinMintSetupShell.ps1` | Direct2D render + golden status sequence |
| Provisioning lock integration | `tests/integration/Test-WinMintProvisioningLockPreview.ps1` | Guard + pump + stage demo (manual) |
| VM smoke (Hyper-V, elevated) | `tools/vm/*` orchestrator | See §5 |
| CI | GitHub Actions | Contract + analyzer + setup-shell publish — **no VM** |

```powershell
# Contract gate (includes setup-shell + VM harness static assertions)
pwsh -NoProfile -File tools\dev\Invoke-WinMintPesterContract.ps1

# Local setup-shell splash preview
pwsh -NoProfile -File tools\dev\Show-WinMintSplash.ps1

# Setup-shell integration test (headless render; add -SkipLaunch:$false for fullscreen on desktop)
pwsh -NoProfile -File tests\setup-shell\Test-WinMintSetupShell.ps1 -SkipLaunch

# Interactive maintainer — smoke VM (elevated, repo root)
pwsh -NoProfile -File tools\vm\Invoke-WinMintVmAcceptance.ps1 `
    -ProfilePath .\tests\profiles\hyper-v-smoke-arm64.json

# Agent/Cursor — detached managed smoke
pwsh -NoProfile -File tools\vm\Start-WinMintVmAcceptanceManaged.ps1 `
    -ProfilePath .\tests\profiles\hyper-v-smoke-arm64.json
pwsh -NoProfile -File tools\vm\Get-WinMintVmAcceptanceStatus.ps1
```

### 2) Test Layout

| Area | Path | Role |
|------|------|------|
| Contract suite | `tests/contract/` | Profile/schema/staging invariants; setup-shell design gates in `StaticAssertions.ps1` |
| Pester entry | `tests/contract/WinMint.Contract.Tests.ps1` | Pester 5 wrapper; setup-shell fixture assertions |
| Setup-shell fixtures | `tests/fixtures/setup-shell/*.json` | Status/control JSON golden files |
| VM profiles | `tests/profiles/hyper-v-smoke-arm64.json`, `hyper-v-install-arm64.json` | Acceptance profile fixtures |
| VM harness | `tools/vm/*.ps1` | Build, boot, wait, inspect, evidence |
| Agent skill | `.agents/skills/vm-acceptance-orchestration/SKILL.md` | Subagent workflow for managed runs |

Naming: contract files are `Test-<Area>.ps1`; VM tools are `Verb-WinMint*.ps1`.

### 3) Test Scope Matrix

| Scope | Covered? | Target | Notes |
|-------|----------|--------|-------|
| Unit | Partial | isolated PS helpers, C# render self-test | No broad PS unit framework |
| Contract | Yes | Profile, install plan, setup-shell staging, VM harness symbols | No ISO/DISM |
| Integration | Partial | `Test-Integration.ps1`, push-to-guest scripts | Running Windows guest required |
| E2E (VM smoke) | Yes (local) | ISO → Setup → FirstLogon → **native setup shell** | Hyper-V + real ISO + elevation; not in CI |
| E2E (VM full) | Yes (local) | Smoke + heavy agent work + stricter evidence | `hyper-v-install-arm64.json` |
| Setup shell UI | Local harness + static contract | Direct2D exe + JSON status pump; `finishing` label gate in `StaticAssertions.ps1` | `Test-WinMintSetupShell.ps1`; full path needs VM |
| Removal drift | Smoke Evidence phase | Guest AppX/capability regressions vs profile removals | `Test-WinMintGuestRemovalDrift.ps1` |

### 4) Mocking and Isolation Strategy

- **No mock framework** for PowerShell; tests dot-source engine internals and use inline stubs.
- **Hyper-V Smoke WSL skip:** `diagnostics.wslRuntimeValidation = skip` on smoke profiles (injected by VM harness overlay) skips real WSL runtime work in nested Hyper-V guests.
- **VM iteration bypasses splash:** `Push-WinMintSetupScripts.ps1` uses `-AgentMode Headless` / `WINMINT_FIRSTLOGON_MODE=headless` by default so automation is not blocked by fullscreen UI (`docs/VM-Acceptance.md`). ISO installs with `-AgentMode Auto` defer explorer reload until after the splash exits — push loops that only rerun FirstLogon will not exercise that ordering unless they use `-AgentMode Auto`.
- **ISO fixture:** `tests/fixtures/iso/official-win11-25h2-english-arm64-v2.iso` — local only; CI uses empty stub.

### 5) VM Smoke Automation (deep dive)

#### Pyramid position

Smoke sits above contract tests and below full VM acceptance (`docs/VM-Acceptance.md`):

- Proves: ISO build → unattended Setup → FirstLogon agent → **OOBE-like setup shell** (`WinMintSetupShell.exe`).
- Does **not** prove: full product matrix, real WSL distro installs, shell layers (windhawk/komorebi/thide).

#### Profile fixture (`hyper-v-smoke-arm64.json`)

| Invariant | Value | Enforced by |
|-----------|-------|-------------|
| `profileName` | `Hyper-V Smoke` | `Test-WinMintHyperVProfile.ps1 -Tier Smoke`, `StaticAssertions.ps1` |
| Edition | Windows 11 Pro + Pro generic key | VM Test Invariant (`AGENTS.md`) |
| Account | Local + password + autologon | PowerShell Direct sign-in |
| Desktop | `standard` only | Smoke tier validation |
| Browsers/editors/distros | Empty | Smoke tier validation |
| WSL | `enabled: true`, `distros: []` | Baseline on; runtime skipped in agent |

#### Orchestrator phases

`Invoke-WinMintVmAcceptance.ps1` `-Phase`:

| Phase | Action |
|-------|--------|
| `All` (default) | BuildBoot → Wait → Inspect → Evidence |
| `BuildBoot` | Fingerprint-gated ISO + Gen2 VM boot |
| `Wait` | Poll guest `state.json` until terminal; **setup-shell watch** |
| `Inspect` | Live desktop signals (best-effort) |
| `Evidence` | Pull logs, score `acceptance-result.json` |

Smoke defaults: **35 min** timeout, **30 min** time budget (`Invoke-WinMintVmAcceptance.ps1` when tier is Smoke).

#### Managed run (agents)

| File | Purpose |
|------|---------|
| `Start-WinMintVmAcceptanceManaged.ps1` | Detached child; writes `output/vm-acceptance/managed-run.json` |
| `Get-WinMintVmAcceptanceStatus.ps1` | Poll `complete`, `status`, `verdict`, `observePid`, log tail |
| `Start-WinMintVmObserve.ps1` | Attach Basic VMConnect to a running VM (passive end-user view) |
| `WinMint-VmConsole.ps1` | Shared: repo root, OOBE poll, VMConnect Basic observe, evidence scoring |

**Green contract:** `complete = true`, `status = passed`, `verdict = pass`, and `acceptance-result.json` → `setupShell` plumbing OK (`.agents/skills/vm-acceptance-orchestration/SKILL.md`).

#### Smoke wait hold (90s)

`WinMint-VmConsole.ps1` defines `$WinMintVmSmokeFirstLogonMinElapsedSeconds = 90`. After FirstLogon reaches terminal `run.status`, smoke **continues polling** until FirstLogon activity is at least 90s old so setup-shell OOBE evidence is not cut short (`Test-WinMintVmSmokeFirstLogonActivityMinElapsed`).

#### Build fingerprint / reuse

`Build-And-TestVm.ps1` fingerprints profile + `src/runtime` + ISO identity + **`apps/setup-shell` sources** so native shell changes invalidate cached ISOs. `-ForceBuild` bypasses cache; `-UseCheckpoint` restores `PostSetup` snapshot to skip Windows Setup.

#### Verdict model (`acceptance-result.json`)

| Field | Smoke | Full |
|-------|-------|------|
| `plumbingVerdict` | Must pass | Must pass |
| `evidenceVerdict` | Warnings only | Must pass |
| `verdict` | Plumbing alone | Plumbing + evidence |
| `setupShell` | Required plumbing evidence | Stricter screenshot/desktop-guard |
| `removalDrift` | Must pass (expected removals absent) | Same gate |

Plumbing failures exit **1**; smoke evidence gaps go to `warnings`.

#### Setup-shell evidence checks (`Test-WinMintSetupShellAcceptanceEvidence`)

Scored in `WinMint-VmConsole.ps1` during Evidence phase:

| Check | Plumbing | Evidence |
|-------|----------|----------|
| Live UI poll saw `running`/`finishing` | Yes | — |
| `FirstLogon.log` contains `Started WinMint setup shell` | Yes | — |
| Not `AgentMode=Headless` | Yes | — |
| `SetupShell.log` contains `host=native` | Yes | — |
| `setup-shell-control.json` → `phase=complete` | Yes | — |
| Desktop guard observed | — | Yes (Full); optional warn path |
| `oobe-splash.png` screenshot | — | Yes (Full); **waived on Smoke** when native logs + control complete + live UI |

Screenshot capture: PowerShell Direct runs inline C# `PrintWindow` against class `WinMintSetupShellWindow` (`Invoke-WinMintVmGuestSetupShellScreenshot`).

#### Failure layers (diagnosis)

`start` · `build` · `install` · `firstlogon` · `setupshell` · `strict` · `timeout` — see `.agents/skills/vm-acceptance-orchestration/references/failure-taxonomy.md`.

#### FirstLogon iteration (no reinstall)

```powershell
pwsh -NoProfile -File tools\vm\Invoke-WinMintVmCheckpoint.ps1 -Action Restore -Name PostSetup
pwsh -NoProfile -File tools\vm\Push-WinMintSetupScripts.ps1 -RerunFirstLogon -WaitForAgent
```

Uses headless agent — **does not** re-validate setup-shell splash path.

### 6) Setup-Shell Contract Tests (no VM)

`StaticAssertions.ps1` → `Assert-SetupShellNativeDesign` and `Assert-FirstLogonDefaultsToSetupShell`:

- `Resolve-WinMintFirstLogonAgentMode` defaults `Auto` → `SetupShell` (`FirstLogon.Host.ps1`).
- No WebView2 / legacy `Start-WinMintSetupShell.ps1` host.
- Staged payload includes `WinMintSetupShell.exe`, `tokens.json`, hero PNGs (`SetupPayloadStaging.ps1`).
- Published binaries under `assets/runtime/setup/setup-shell/bin/{x64,arm64}/` size gate (&lt; 10 MB).
- Transaction plan pumps status via `Invoke-WinMintSetupShellStatusPumpTick` while agent runs.
- VM harness must reference `Test-WinMintSetupShellAcceptanceEvidence`, smoke min-elapsed helper.

`WinMint.Contract.Tests.ps1` + fixtures under `tests/fixtures/setup-shell/` validate status JSON shape against schemas:

- `schemas/winmint.setupshellstatus.schema.json`
- `schemas/winmint.setupshellcontrol.schema.json`

### 7) Coverage and Quality Signals

- **No coverage threshold** enforced.
- **CI** does not run VM acceptance (`.github/workflows/ci.yml`).
- **Evidence output** is gitignored under `output/vm-acceptance/` — no checked-in `acceptance-result.json` in repo.
- **Known flaky area:** PrintWindow screenshot capture on headless/session guests; smoke tier waives screenshot when other plumbing passes.

**Team validation state (2026-06-29):**

| Check | Status |
|-------|--------|
| Baseline VM smoke (lean profile, ISO → Setup → FirstLogon plumbing) | Pass |
| Setup-shell splash path (`setupShell` evidence / `WinMintSetupShell.exe`) | **Not confirmed** |
| Setup-shell visual polish | **Not confirmed** |

### 8) Recommended Test Sequence (setup-shell / smoke changes)

| Step | When | Action |
|------|------|--------|
| 1 | Any edit | `Invoke-WinMintPesterContract.ps1` or `Test-ProfileInvariants.ps1` |
| 2 | `apps/setup-shell/` or `WinMintSetupShell.Status.ps1` | `Show-WinMintSplash.ps1` or `tests\setup-shell\Test-WinMintSetupShell.ps1`; rebuild via `tools/release/Build-WinMintSetupShell.ps1` if binaries missing |
| 3 | Engine staging / autounattend | Managed smoke with `-ForceBuild` |
| 4 | FirstLogon agent only | Checkpoint + `Push-WinMintSetupScripts.ps1 -RerunFirstLogon -WaitForAgent` (headless — not splash) |
| 5 | Pre-release | Full `hyper-v-install-arm64.json` |

### 9) Evidence

- `docs/VM-Acceptance.md` — runbook, verdict fields, time budgets
- `tests/profiles/hyper-v-smoke-arm64.json` — smoke profile fixture
- `tools/vm/Invoke-WinMintVmAcceptance.ps1` — orchestrator
- `tools/vm/WinMint-VmConsole.ps1` — smoke 90s hold, setup-shell evidence
- `tools/vm/Start-WinMintVmAcceptanceManaged.ps1`, `Get-WinMintVmAcceptanceStatus.ps1`
- `tests/contract/ProfileInvariantTests/StaticAssertions.ps1` — `Assert-SetupShellNativeDesign`
- `tests/contract/WinMint.Contract.Tests.ps1`
- `tests/setup-shell/Test-WinMintSetupShell.ps1`
- `tools/dev/Show-WinMintSplash.ps1`
- `src/runtime/firstlogon/Modules/Wsl.ps1` — Hyper-V Smoke skip
- `.agents/skills/vm-acceptance-orchestration/SKILL.md`
