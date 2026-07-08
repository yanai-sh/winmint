# Codebase Concerns

Snapshot note: updated 2026-06-30 (team validation status). Focus: **VM smoke reliability** and **setup-shell OOBE path** risks.

## Core Sections (Required)

### 0) Current Validation State (team, 2026-06-30)

| Area | Status | Notes |
|------|--------|-------|
| VM smoke plumbing (ISO → Setup → FirstLogon, lean profile) | **Pass** | Confirmed without WinMint-specific additions beyond the baseline smoke path |
| Setup-shell OOBE UX fixes (exit, labels, explorer deferral) | **Implemented** | Code landed 2026-06-30; awaiting managed smoke sign-off |
| Setup-shell splash (`WinMintSetupShell.exe` OOBE path) | **Pending re-verify** | Prior gap; smoke with `-ForceBuild` after shell/staging edits |
| Setup-shell visual polish (layout, progress bar, tokens) | **Not confirmed** | Implementation exists; no visual sign-off yet |
| Removal drift gate (AppX/capabilities) | **Implemented** | `Test-WinMintGuestRemovalDrift.ps1` wired into smoke evidence |
| Release / alpha tag policy | **Out of scope** | Not a current decision surface |

### 1) Top Risks (Prioritized)

| Severity | Concern | Evidence | Impact | Suggested action |
|----------|---------|----------|--------|------------------|
| **High** | Setup-shell splash path pending VM re-verify | OOBE UX fixes landed 2026-06-30; prior status was unconfirmed | Default FirstLogon may still fail evidence gates until smoke passes | Managed smoke with `-ForceBuild`; collect `SetupShell.log`, control JSON, screenshot |
| **Med** | Reboot-phase shell could hang pre-fix | Fixed: `ShouldClose` treats `reboot` as terminal | Was 120s wait in `finalize-reboot-resume` | Keep contract + local harness; smoke reboot path if agent adds needsReboot |
| **Med** | Explorer reload under splash caused Start flash | Fixed: pins in `finalize-user-shell`, reload in `finalize-success` | Start menu opened on first desktop | VMConnect manual check after smoke |
| **High** | Setup-shell visual polish unsigned | Team status 2026-06-29; `apps/setup-shell/SetupShellHost.cs` | OOBE presentation may be functionally present but not shippable-quality | Iterate Direct2D layout/tokens; use `tests/setup-shell/Test-WinMintSetupShell.ps1` + VM screenshot evidence |
| **High** | VM smoke not in CI — regressions ship until manual run | `.github/workflows/ci.yml` has no Hyper-V step; `docs/VM-Acceptance.md` | Splash regressions undetected by merge | Manual smoke after shell changes; contract tests gate static design only |
| **Med** | Screenshot evidence flaky on guests | `Invoke-WinMintVmGuestSetupShellScreenshot` uses PrintWindow; smoke waives in `Test-WinMintSetupShellAcceptanceEvidence` | Harder to confirm splash visually even when logs pass | Treat screenshot as supplementary; prioritize logs + `control.phase=complete` for first splash green |
| **Med** | Headless push loop does not exercise splash | `Push-WinMintSetupScripts.ps1` uses `-AgentMode Headless` per `docs/VM-Acceptance.md` | FirstLogon iteration can pass while ISO splash path is broken | Re-run smoke ISO install after shell/staging changes |
| **Med** | `acceptance-result.json` has no JSON Schema | `docs/VM-Acceptance.md` ("intentionally not a formal schema yet") | Harness field drift undetected by contract tests | Add schema when repeated pain (roadmap Track B2/D4 deferral) |
| **Med** | Setup-shell binary must be pre-published | `SetupPayloadStaging.ps1` throws if `assets/runtime/setup/setup-shell/bin/<arch>/WinMintSetupShell.exe` missing | Build fails at staging | `Build-And-TestVm.ps1` auto-invokes `Build-WinMintSetupShell.ps1` when missing |
| **Low** | 90s smoke hold extends wait after agent done | `WinMint-VmConsole.ps1` `$WinMintVmSmokeFirstLogonMinElapsedSeconds = 90` | Slightly longer smoke runs | Intentional — protects OOBE poll window |

### 2) Technical Debt (focus areas)

| Debt item | Where | Risk if ignored |
|-----------|-------|-----------------|
| Dual verdict paths (plumbing vs evidence) | `Invoke-WinMintVmAcceptance.ps1`, `WinMint-VmConsole.ps1` | Confusion about smoke vs full green criteria |
| Post-hoc UI inference when live poll misses shell | Removed — smoke requires `liveUi` or `running` phase | Re-run managed smoke after harness edits |
| VM harness incremental growth | 15+ scripts under `tools/vm/` | Coupling; mitigated by shared `WinMint-VmConsole.ps1` |

### 3) Security Concerns (focus areas)

| Risk | Evidence | Mitigation |
|------|----------|------------|
| Smoke profile contains plaintext password | `tests/profiles/hyper-v-smoke-arm64.json` `identity.password` | Test fixture only; required for unattended VM invariant |
| PowerShell Direct requires credentialed local admin | VM acceptance scripts | Expected for Hyper-V automation |
| Desktop guard blocks Win keys during splash | `Enable-WinMintProvisioningGuard` | By design — released on shell exit |

### 4) Performance Concerns (focus areas)

| Concern | Evidence | Note |
|---------|----------|------|
| Full ISO rebuild on setup-shell source change | `Build-And-TestVm.ps1` hashes `apps\setup-shell` | Correctness over speed — use fingerprint cache when unchanged |
| Smoke target 15–30 min warm | `docs/VM-Acceptance.md` time budgets | `-FastImage` default in VM build |
| 90s extra wait on smoke | `WinMint-VmConsole.ps1` | Trade latency for setup-shell evidence |

### 5) Fragile/High-Churn Areas (focus)

| Area | Churn signal (90d scan) | Safe change strategy |
|------|-------------------------|----------------------|
| `StaticAssertions.ps1` | 33 commits | Update with any setup-shell or VM harness symbol change |
| `FirstLogon.Runtime.ps1` / `WinMintSetupShell.Status.ps1` | Active firstlogon refactor history | Contract tests + `tests/setup-shell/Test-WinMintSetupShell.ps1` |
| `WinMint-VmConsole.ps1` | New managed-run + OOBE evidence | Run smoke after harness edits |
| `apps/setup-shell/SetupShellHost.cs` | New component (5 C# files in scan) | Rebuild binaries; smoke with `-ForceBuild` |

### 6) Intent vs. Reality

| Stated intent | Observed in code / validation | Divergence |
|---------------|------------------------------|------------|
| Default FirstLogon feels like OOBE, not terminal | `Resolve-WinMintFirstLogonAgentMode` returns `SetupShell` for `Auto`; OOBE UX contract in `AGENTS.md` | **Aligned in code** — splash **pending VM re-verify** |
| VM smoke proves lean install plumbing | Team: baseline smoke passes (2026-06-29) | **Aligned** for ISO→Setup→FirstLogon without splash sign-off |
| VM smoke proves setup-shell splash | Harness scores `setupShell.*`; OOBE fixes landed 2026-06-30 | **Active gap** — re-run smoke to close |
| Setup-shell is shippable-quality UI | Team: visual polish not confirmed | **Active gap** — separate from plumbing proof |
| VM iteration should not block on UI | Push scripts use Headless | **Aligned** — splash requires ISO smoke, not push loop |
| Smoke skips real WSL | `Wsl.ps1` checks `profileName -eq 'Hyper-V Smoke'` | **Aligned** |
| No CI VM gate | CI workflow has contract tests only | **Aligned** — manual smoke required |

### 7) Recommended Next Step

1. **Re-run managed smoke with `-ForceBuild`** — target `setupShell.plumbingOk` + `host=native` + `control.phase=complete` + `removalDrift.ok` in evidence.
2. **VMConnect manual check** — fullscreen splash, Start closed on desktop reveal, no premature "Installing tools" label.
3. **Visual polish pass** — after plumbing green, finalize Direct2D layout/progress in `apps/setup-shell/` against `tokens.json`.

### 8) Evidence

- `tools/vm/WinMint-VmConsole.ps1` — evidence scoring, 90s hold, screenshot waive
- `tools/vm/Invoke-WinMintVmAcceptance.ps1` — tier verdict logic
- `docs/VM-Acceptance.md` — smoke vs full policy
- `tests/contract/ProfileInvariantTests/StaticAssertions.ps1` — setup-shell static gates
- `src/runtime/setup/FirstLogon.Host.ps1` — default SetupShell mode
- `docs/codebase/.codebase-scan.txt` — churn metrics
- `.github/workflows/ci.yml` — no VM steps
