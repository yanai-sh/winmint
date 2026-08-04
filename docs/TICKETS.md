# M1 work backlog (canonical)

**Authority for stories:** [Smoke spec](specs/2026-07-27-smoke.md)  
**Authority for locks:** [DESIGN grill](DESIGN.md#decisions-locked-grill) · module designs under [design/](design/)  
**Schedule / order:** [ROADMAP](ROADMAP.md)  
**TDD seams:** [TDD](TDD.md)

## Implementation hold

**Status: Released** (2026-07-29).  
`/implement` may proceed from this backlog — one ticket per session, starting at **01**. Do not label `ready-for-agent` until starting that ticket.

| When hold lifts | First action |
|-----------------|--------------|
| Maintainer sets hold → **Released** below | File Issues 01–10 (if missing), then `/implement` **01** only |

**Hold:** **Released** (2026-07-29)

**Before hold → Released:** pointer sync done (01–10); splash spike bar met ([SPLASH](design/SPLASH.md) appendix); `just check` green; then file Issues 01–10 (no `ready-for-agent` until starting **01**). ✓ met 2026-07-29

**GitHub Issues (filed 2026-07-29):** ticket **01→#3** … **10→#12** (titles `01`–`10`; label `enhancement` only — apply `ready-for-agent` only when starting that ticket).

---

## Ticket index

| # | Title | Module | Stories | Blocked by | Ready when |
|---|--------|--------|---------|------------|------------|
| 01 | Profile + plan + Cli `validate`/`plan` | BuildPlan | 1–2 | — | Released — start here |
| 02 | Servicing apply + Shell stamp + Cli `build`/`apply` | ImageServicing | 3 | 01 | 01 done — **done** |
| 03 | Machine setup stamps | ProvisioningSession | 4 | 02 | 02 done — **done** |
| 04 | Shell splash + status + evidence | ProvisioningSession | 5, 13 | 03 | 03 done **+ splash spike** — **done** |
| 05 | DMA settle | ProvisioningSession | 6–8 | 04 | 04 done — **done** |
| 06 | Stub jobs + child-process executor | ProvisioningSession | 9–10 | 05 | 05 done — **done** |
| 07 | Unlock + timeout + stale fail-open | ProvisioningSession | 12 + appearance | 06 | 06 done — **done** |
| 08 | Checkpoint reboot keeps Shell | ProvisioningSession | 11 | 07 | 07 done — **done** |
| 09 | `Test`/`Release` export lane | BuildPlan + ImageServicing | 14 | 02 | May parallel 03–08 — **done** |
| 10 | Hyper-V Smoke harness | Acceptance S4 | 15 | 08, 09 | 08+09 done — **done** |

**Non-ticket prerequisite:** splash prototype spike ([SPLASH](design/SPLASH.md)) before **04** is `ready-for-agent`. Spike bar: timing + ordering + one fresh-cycle replay in the appendix.

**Renumber note (2026-07-29):** old 06 (jobs+unlock+reboot) → **06 / 07 / 08**; old 07 (Test lane) → **09**; old 08 (Smoke harness) → **10**.

**Carry / ponytail (2026-08-03):** [ponytail audit](research/2026-08-03-ponytail-audit.md) — fold into the owning ticket below; do **not** open a separate cleanup epic. Keep wipe, both Cli `build`/`apply`, and image digests. Do **not** pull keep-flag / debloat product code into M1 (wayfinder [#13](https://github.com/yanai-sh/winmint/issues/13) is design-only until **10** is green).

---

## Ticket cards

### 01 — Profile + plan + Cli `validate`/`plan`

- **Design:** [BUILDPLAN](design/BUILDPLAN.md) · **Seam:** S1 · **Stories:** 1–2
- **Blocked by:** — · **Ready when:** Released — start here
- **Deliver:**
  - Profile DTOs + source-gen; freeze JSON field names / `schemaVersion` (`winmint.profile/v1`)
  - `TryParseProfile` / `Plan`; Cli `validate` / `plan`
  - Emit plan artifacts: unattend, job JSON (`winmint.jobs/v1`), payload manifest, servicing stage list (opcodes + params, not `.ps1` paths), `DmaContract`, build manifest
  - Password required for Local+autoLogon; DMA Ireland latch in unattend + settle targets
  - Default image-quality **lane name** = `Test` (field parses; no export param ownership)
- **Out:** elevation; DISM; splash; Servicing; **`ExportWim` compression/cleanup params** (ticket **09**)
- **DoD:**
  - [BUILDPLAN tracers 1–4](design/BUILDPLAN.md#ticket-01-tdd-tracers-first-vertical-slices) green ✓
  - Local+autoLogon only; stages contain opcodes, not repo-relative `.ps1` paths ✓
  - `just check` green ✓
- **First red:** Empty/invalid JSON → document error (S1 tracer 1).
- **Done:** 2026-07-29 (issue #3)

### 02 — Servicing apply + Shell stamp + Cli `build`/`apply`

- **Design:** [IMAGESERVICING](design/IMAGESERVICING.md) · **Seam:** S2 · **Stories:** 3
- **Blocked by:** 01 · **Ready when:** 01 done
- **Deliver:**
  - `servicing/RunPlan.ps1` + thin param-only kernels
  - One UAC `Apply`; offline Shell stamp of Supervisor
  - `StagePayload`: published Supervisor (AOT), SetupComplete.cmd, provisioning bundle (`winmint.provisioning.bundle/v1`)
  - Produce `ImageEvidence` (`winmint.image.evidence/v1`) on success
  - Cli `build` / `apply`
  - One Orchestrator path that calls elevated `pwsh -File` (enough for this ticket)
- **Out:** Profile `if` branching in kernels; guest FirstLogon; **full `IElevatedPlanRunner` port** unless introduced in the same PR as its test fake
- **DoD:**
  - Stage order asserted; Shell stamp path param present ✓
  - Workdir preserved on failure; kernels param-only ✓
  - `just check` green ✓
- **First red:** Fake or scripted runner asserts stage order for a minimal plan (S2).
- **Done:** 2026-08-02 (issue #4)
- **Carry (post-DoD):** Real DISM/oscdimg Apply + `ImageEvidence.Digests` (ISO/WIM SHA-256) landed after stub DoD — keep digests; keep both Cli verbs. SetupComplete single source: Materialize copies `payload/scripts/SetupComplete.cmd` (no embedded here-string).

### 03 — Machine setup stamps

- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) · **Seam:** S3 · **Stories:** 4
- **Blocked by:** 02 · **Ready when:** 02 done
- **Deliver:**
  - `Run(MachineSetup)`: autologon stamp; Shell verify/restamp (fail-closed); secret wipe
  - SetupComplete / `--machine-setup` exits non-zero on fail
- **Out:** splash; DMA settle; jobs; unlock/reboot tenure
- **DoD:**
  - Fake-registry tests for stamp + Shell verify fail/success ✓
  - Never `defaultuser0` + AutoAdminLogon ✓
  - Fail path: non-zero exit; diagnosable logs under `%ProgramData%\WinMint\` ✓
- **First red:** Autologon stamp rejects `defaultuser0` + AutoAdminLogon (S3).
- **Done:** 2026-08-03 (issue #5)
- **Carry:** Secret **wipe behavior** stays (lab hygiene after stamp). `ISecretScrubber` / `FileSecretScrubber` is judgement debt — prefer inline JSON redact (or DTO rewrite) when next editing Machine setup; do not drop wipe. Empty `SessionEnvironment` ports for 04–08 are judgement debt — **fill on the owning ticket**, do not leave `Unsupported*` once that ticket ships.

### 04 — Shell splash + status + evidence

- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) + [SPLASH](design/SPLASH.md) · **Seam:** S3 · **Stories:** 5, 13
- **Blocked by:** 03 · **Ready when:** 03 done **and** splash spike appendix has timing + ordering + one fresh-cycle replay
- **Deliver:**
  - First opaque splash frame before settle starts
  - In-memory splash status (not a file control plane)
  - Evidence projections: `winmint.provisioning.evidence/v1` (write-only)
  - Settle phase may be a **no-op/stub hook** until ticket **05** (enough to assert paint-before-settle order)
  - Replace `UnsupportedSplashPresenter` with a real `ISplashPresenter` (recording fake in tests + production presenter); ship a real write-only `IEvidenceSink` (no longer `null` / empty marker)
- **Out:** hard input lock; real winget matrix; Hyper-V / S4 harness; real DMA restore logic (ticket **05**); thinning unrelated empty ports for 05–08
- **DoD:**
  - Recording presenter asserts paint-before-settle **order** (not wall-clock OS latency) ✓
  - Evidence is write-only; session never reads evidence JSON to decide the next phase ✓
  - No `UnsupportedSplashPresenter` left in production `Program` wiring for Shell tenure ✓
- **First red:** `Show` (or equivalent) recorded before settle poll begins (S3).
- **Done:** 2026-08-03 (issue #6)
- **Carry:** Settle filled by ticket **05**. Jobs / unlock / checkpoint remain 06–08. GDI solid fill presenter — D2D if S4 FirstPaintBudget slips. Shell fail-closes if `Evidence` is null (MachineSetup may omit).

### 05 — DMA settle

- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) · **Seam:** S3 · **Stories:** 6–8
- **Blocked by:** 04 · **Ready when:** 04 done
- **Deliver:**
  - Bounded restore then **final snapshot** for hard locale / GeoID / TZ
  - Soft location-services: warn + continue (not a hard gate)
  - Hard settle failure skips jobs
  - Real `IRegionSnapshot` (+ tests that script intermediate vs final); start using `TimeProvider` / settle deadline fields from `SessionPolicy` as needed
  - Replace settle stub with private `RunSettle` (or equivalent) inside `ProvisioningSession` — same `Run` seam; **no** Settling project/package
  - New status codes only from [CONTRACTS](design/CONTRACTS.md) dotted `area.token` dialect
- **Out:** real network location UX polish; metal-only settle forks; job executor details (ticket **06**); pre-splitting ProvisioningSession into folders
- **DoD:**
  - Scripted region-snapshot tests: intermediate probe failures are **non-authoritative** ✓
  - Only the final snapshot gates hard fields ✓
  - Hard fail ⇒ jobs not started ✓
  - No `UnsupportedRegionSnapshot` left once settle ships ✓
  - Settle logic lives as private phase method(s) behind `ProvisioningSession.Run` ✓
- **First red:** Final hard GeoID mismatch ⇒ `Failed` path and no job start (S3).
- **Done:** 2026-08-03 (issue #7)
- **Carry:** Jobs / unlock / checkpoint remain 06–08. Soft location warn continues without hard-failing jobs. `Task.Delay(span, TimeProvider, ct)` drives settle poll (no `TimeProvider.Delay`).

### 06 — Stub jobs + child-process executor

- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) · **Seam:** S3 · **Stories:** 9–10
- **Blocked by:** 05 · **Ready when:** 05 done
- **Deliver:**
  - Smoke stub job set (no real WSL / browser matrix) — reuse BuildPlan’s existing `smoke.stub.*` ids if still emitted; do not invent a second stub catalog
  - Supervisor runs jobs as child processes; one executor shape for Smoke and metal
  - Real `IProcessHost` (test fake + production); drop `UnsupportedProcessHost`
- **Out:** unlock / timeout / stale policy (ticket **07**); checkpoint / reboot (ticket **08**); real package matrix
- **DoD:**
  - Stub jobs run via `Run` + process-host fakes
  - Jobs never start when prior hard settle failed
- **First red:** Stub job invoked as child process after green settle (S3).
- **Done:** 2026-08-03 (issue #8)
- **Carry:** Unlock / timeout / stale / appearance remain ticket **07**; checkpoint reboot **08**. Stub `Kind` maps to `cmd.exe /c exit 0` via `IProcessHost` — metal kinds fail closed until a later matrix ticket.

### 07 — Unlock + timeout + stale fail-open

- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) · **Seam:** S3 · **Stories:** 12 (+ appearance from Implementation Decisions)
- **Blocked by:** 06 · **Ready when:** 06 done
- **Deliver:**
  - Wall-clock timeout → `Failed` + unlock; failed dwell before unlock
  - Stale / missing heartbeat past `StaleTenureThreshold` → fail-open `Failed` + unlock
  - Profile appearance applied **once** before Explorer unlock on success (`AppearanceOnce` earns its keep here)
  - Policy defaults per [smoke defaults](design/PROVISIONINGSESSION.md#smoke-defaults-grill-locked) — `SessionPolicy` + `TimeProvider` must drive behavior (not dead fields)
- **Out:** checkpoint / reboot-keeps-Shell (ticket **08**); hard input lock
- **DoD:**
  - `FakeTimeProvider`: timeout unlocks ✓
  - Stale tenure → `Failed` + unlock ✓
  - Success path: appearance applied once, then unlock ✓
- **First red:** Wall-clock timeout yields unlock (S3).
- **Done:** 2026-08-04 (issue #9)
- **Carry:** Checkpoint write/clear + `Reboot` keep-Shell remain ticket **08** (`FileCheckpointStore` heartbeat/tenure read shipped; write path still 08). Profile→bundle appearance field not staged yet — `AppearanceOnce` on bundle is consumed when present. → **08 done** (write/clear + resume shipped).
### 08 — Checkpoint reboot keeps Shell

- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) · **Seam:** S3 · **Stories:** 11
- **Blocked by:** 07 · **Ready when:** 07 done
- **Deliver:**
  - Job `needsReboot` → durable checkpoint under `%ProgramData%\WinMint\` + keep Supervisor as Shell
  - Resume after reboot continues Shell tenure (no Explorer flash)
  - Real `ICheckpointStore`; `SessionOutcome.Reboot` + `CheckpointState` earn their keep; drop `UnsupportedCheckpointStore`
- **Out:** unlock-on-complete/failed (ticket **07**); real reboot-required package matrix
- **DoD:**
  - `Reboot` outcome does **not** unlock ✓
  - Checkpoint written; Shell retained; resume continues tenure ✓
- **First red:** `needsReboot` ⇒ `Reboot` + checkpoint + Shell kept (S3).
- **Done:** 2026-08-04 (issue #10)
- **Carry:** OS reboot trigger / metal reboot-required matrix still out. `ProvisionJob.NeedsReboot` is the S3 flag (no separate job catalog).

### 09 — `Test`/`Release` export lane

- **Design:** [BUILDPLAN](design/BUILDPLAN.md) + [IMAGESERVICING](design/IMAGESERVICING.md) · **Seams:** S1 / S2 · **Stories:** 14
- **Blocked by:** 02 · **Ready when:** 02 done (may parallel 03–08)
- **Deliver:**
  - `Test` vs `Release` → `ExportWim` params
  - Manifest / report records which lane ran
- **Out:** new Profile fields beyond lane; ISO byte asserts; guest behaviour
- **DoD:**
  - Test ⇒ fast compression + `cleanup=skip` (per [IMAGESERVICING](design/IMAGESERVICING.md)) ✓
  - Release ⇒ `compression=max` + `cleanup=full` ✓
  - Manifest lane matches run options ✓
- **First red:** Explicit `ImageQuality.Release` ⇒ export params differ from Test (BUILDPLAN tracer 5 / S1–S2).
- **Note:** Plan already emits lane/compression/cleanup params from ticket 01 — this ticket owns verifying ExportWim **honors** Release vs Test end-to-end (not inventing a second lane model).
- **Done:** 2026-08-04 (issue #11)
- **Carry:** `Apply` fail-closes on ExportWim↔manifest mismatch; `evidence.json` records `lane`; Cli `--image-quality Test|Release`.

### 10 — Hyper-V Smoke harness

- **Design:** [CONTRACTS](design/CONTRACTS.md) · [SPLASH](design/SPLASH.md) · **Seam:** S4 · **Stories:** 15 · **Speed:** [TDD](TDD.md#speed-rules)
- **Blocked by:** 08, 09 · **Ready when:** 08+09 done
- **Deliver:**
  - One pwsh entry under `tools/vm/` (“run Smoke → evidence”)
  - Pro + DMA-on acceptance Profile; evidence pull
- **Out:** metal / hardware acceptance; guest pwsh; peer Splash; multi-entrypoint harness forest; Hyper-V-only settle/executor fork
- **Optional later (harness only):** differencing VHD from parent base; ISO rebuild only on plan/payload digest change (`ImageEvidence.Digests` already available); careful servicing workdir reuse
- **DoD:**
  - Splash before Explorer; DMA hard fields green **or** failed DMA path with evidence + unlock ✓ (phase proxy; Explorer-first probe is harness observation)
  - Unlock on complete/failed; lane marker present; paint time recorded (**warn** if > 2.0 s) ✓
  - Stall fail-fast (Shell/OOBE/autologon hang) before burning `WallClockTimeout` (90 min) ✓
  - Not part of `just check` (S4 / `just smoke` when gated) ✓
- **First red:** Harness returns evidence folder with splash-before-Explorer marker (S4).
- **Done:** 2026-08-04 (issue #12)
- **Carry:** Full Hyper-V path is maintainer-gated (`just smoke ISO=…`); S4 fixture tests use `Category=S4` and are excluded from `just check`. Diff VHD / digest-gated ISO rebuild still optional. Explorer-first UI probe remains observational (phases + unlock outcome).

---

## Explicitly not in M1 backlog

BitLocker, Home Smoke SKU, MicrosoftOobe, enterprise secrets, MediatR/Generic Host/Contracts project, guest pwsh, peer Splash. (Wizard / hardware / metal / keep-flag expand shipped post-M1 — see cards **14–30**.)

Keep-flag **design** is accepted ([KEEPFLAG](design/KEEPFLAG.md), [ADR-005](decisions/ADR-005-keep-flag-matrix.md), [ADR-007](decisions/ADR-007-cdm-not-primary.md)). AppX **11–13** + capabilities **19–20** done. Sequencing [ADR-006](decisions/ADR-006-post-keepflag-sequencing.md) **met**.
---

## Post-M1 — keep-flag matrix

Blocked by: M1 ticket **10** done. Design: [KEEPFLAG](design/KEEPFLAG.md).

| # | Title | Module | Ready when |
|---|--------|--------|------------|
| 11 | Profile remove-list + static AppX catalog + plan validate | BuildPlan | **10** done — **done** |
| 12 | Offline RemoveProvisionedAppx stage + Deprovisioned stamps + evidence | ImageServicing | **11** done — **done** |
| 13 | FirstLogon PackageManager safety-net job (narrow) | ProvisioningSession | **12** done — **done** |

### 11 — Profile remove-list + catalog + plan validate

- **Design:** [KEEPFLAG](design/KEEPFLAG.md) · [BUILDPLAN](design/BUILDPLAN.md)
- **Deliver:** optional `debloat.removeProvisionedAppx` on `winmint.profile/v1` (default empty); static in-repo catalog; plan ⊆ catalog; emit servicing opcode params (no `.ps1` paths)
- **Out:** capabilities/features; Profile presets; `v2` schema bump; Servicing execution
- **DoD:** empty list ⇒ no remove stages; unknown id ⇒ plan failure; `just check` green
- **Done:** 2026-08-04 (issue #22)

### 12 — Offline provisioned AppX remove

- **Design:** [KEEPFLAG](design/KEEPFLAG.md) · [IMAGESERVICING](design/IMAGESERVICING.md)
- **Deliver:** opaque remove opcode + param-only kernel; `Remove-AppxProvisionedPackage` / DISM `/Image`; optional `Deprovisioned` hive stamps; re-inventory evidence
- **Out:** FirstLogon PackageManager; capabilities/features; Profile branching in kernels
- **DoD:** listed present packages gone from provisioned inventory; absent-id policy freeze documented; workdir logs on failure
- **Done:** 2026-08-04 (issue #23)

### 13 — FirstLogon AppX safety net

- **Design:** [KEEPFLAG](design/KEEPFLAG.md) · [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md)
- **Deliver:** optional job when remove-list non-empty — `PackageManager.RemovePackageAsync`; live deprovision only if still provisioned
- **Out:** BCU; UI Automation; CDM primary policy; guest pwsh
- **DoD:** fake PackageManager tests for remove / still-provisioned deprovision paths
- **Done:** 2026-08-04 (issue #24)

---

## Post-13 stubs — sequencing ([ADR-006](decisions/ADR-006-post-keepflag-sequencing.md))

Do not label `ready-for-agent` until starting that card. **Next:** none — backlog through **30** done 2026-08-05; maintainer pick or new rescope. Lasting policy: [DESIGN](DESIGN.md#decisions-locked-grill).

| # | Title | Module | Ready when |
|---|--------|--------|------------|
| 14 | Maintainer Hyper-V Smoke prove-out (real Source ISO) | Acceptance S4 | **13** done — **done** |
| 15 | Wizard = second BuildPlan host (presets → remove-list) | BuildPlan host | **14** done — **done** |
| 16 | First metal job kind `winget` | ProvisioningSession | After **15** — **done** (guest-proven) |
| 17 | Profile `needsReboot` + Hyper-V reboot-resume | ProvisioningSession | After **16** — **done** |
| 18 | Scoop job kind (`packages.scoop`) | ProvisioningSession | After **17** — **done** (metal exit) |
| 19 | Keep-flag capabilities / features matrix spike | Design | After **18** — **done** |
| 20 | Offline ImageServicing capabilities from Profile | ImageServicing | After **19** — **done** |
| 21 | Israel DMA sample + monotonic settle deadlines | ProvisioningSession + harness | After **20** — **done** |
| 22 | Wizard packages UI (winget + Scoop lists) | BuildPlan host | After **21** — **done** |

### 14 — Maintainer Smoke prove-out

- **Issue:** [#26](https://github.com/yanai-sh/winmint/issues/26)
- **Design:** [Smoke](specs/2026-07-27-smoke.md) · [TDD](TDD.md) S4 · harness `tools/vm/` · [ADR-006](decisions/ADR-006-post-keepflag-sequencing.md)
- **Deliver:** one green `just smoke` on a real Source ISO; acceptance Profile includes pinned keep-flag remove-list (`Microsoft.BingNews`, `Microsoft.BingWeather` in [samples/acceptance.profile.json](../samples/acceptance.profile.json) — re-pinned from `GamingApp` after 25H2 ARM64 English media had no provisioned GamingApp)
- **Out:** Wizard; capabilities matrix; Diff VHD / digest-gated rebuild as required DoD (optional maintainer opt); leftover confidence; CDM-as-primary
- **DoD:** Splash before Explorer; DMA hard fields; unlock; lane marker; paint time recorded; **pinned AppX families absent** from provisioned inventory / FirstLogon evidence as applicable; not only fixture S4
- **Carry:** S4 assert requires apply digests `removed.appx.<id>=absent` for pinned ids (`Assert-SmokeEvidence.ps1`); fixture + S4 tests green.
- **Done:** 2026-08-04 — maintainer Hyper-V Smoke green on 25H2 ARM64 English ISO (`outcome=Complete`, `settle.location_warn`, unlock `explorer.exe`, keep-flag digests absent); issue #26

### 15 — Wizard (Avalonia second BuildPlan host)

- **Issue:** [#27](https://github.com/yanai-sh/winmint/issues/27)
- **Design:** [ARCHITECTURE](ARCHITECTURE.md) · [BUILDPLAN](design/BUILDPLAN.md) · [KEEPFLAG](design/KEEPFLAG.md) · [STACK](STACK.md) · [ADR-006](decisions/ADR-006-post-keepflag-sequencing.md)
- **Deliver:** second BuildPlan host; UI presets expand to Profile remove-list (no presets in Profile JSON)
- **Out:** second planning brain; capabilities matrix; schema `v2`; full Wizard polish; elevating Wizard for Servicing
- **DoD:**
  - `src/WinMint.Wizard/` Avalonia **12.1.x** WinExe references Orchestrator; in [WinMint.slnx](../WinMint.slnx)
  - Host-side `KeepFlagPresets` (`empty` / `acceptance` → catalog ids; unknown → `keepflag.preset.unknown`); `WizardProfileComposer` writes `winmint.profile/v1` UTF-8 (no preset field)
  - Minimal Avalonia UI: account/DMA fields + preset → Validate/Plan via BuildPlan → Save Profile JSON; show plan errors
  - Tests (S1b): expand + compose→Plan; unknown fails — `KeepFlagPresetTests`
  - `just check` green
- **Done:** 2026-08-04 — thin vertical host + presets; issue #27

### 16 — Metal `winget` job

- **Issue:** [#28](https://github.com/yanai-sh/winmint/issues/28)
- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) · [ADR-006](decisions/ADR-006-post-keepflag-sequencing.md) · [BUILDPLAN](design/BUILDPLAN.md)
- **Deliver:** first non-stub job kind `winget`; fail-closed other metal kinds until ticketed; OS reboot on `NeedsReboot` via `ISystemReboot`
- **Out:** Scoop/WSL matrix; guest pwsh; Wizard packages UI
- **DoD:**
  - Profile optional `packages.winget: string[]` on `winmint.profile/v1` (no schema bump) ✓
  - BuildPlan emits `kind: "winget"` jobs (`id` = `winget.<packageId>`, `packageId` wire field); stubs still when packages empty / Smoke ✓
  - Supervisor spawns `winget install --id … --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity` via `IProcessHost` ✓
  - Unknown kinds remain `jobs.kind.unsupported` ✓
  - `NeedsReboot` ⇒ checkpoint + evidence + `ISystemReboot.RequestReboot` (`shutdown.exe /r /t 0 /f`) ✓
  - S1 + S3 tests green; `just check` green ✓
  - **Guest Hyper-V prove-out** (post-close): Smoke with `packages.winget` (`jqlang.jq`) → `outcome=Complete` / `jobs.ok` after MachineSetup `takeown`+`icacls` FullControl on UI.Xaml/VCLibs frameworks; Prefer-DiskBoot on setup reboot; OOBE `defaultuser0` removed in MachineSetup ✓
- **Done:** 2026-08-04 — issue #28; guest path proven same day (harness Prefer-DiskBoot; AppInstaller ACL repair; `defaultuser0` delete)
- **Carry into 17–18:** Profile-driven `needsReboot` for packages (job flag only until **17**); Scoop (**18**); ExitWindowsEx if `shutdown.exe` flakes; WSL deferred

### 17 — Profile `needsReboot` + Hyper-V reboot-resume

- **Issue:** [#29](https://github.com/yanai-sh/winmint/issues/29)
- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) · [ADR-006](decisions/ADR-006-post-keepflag-sequencing.md)
- **Deliver:** Profile marks packages that need reboot; BuildPlan emits `needsReboot` on jobs; Hyper-V prove-out of checkpoint → OS reboot → Shell tenure resume → Complete
- **Out:** ExitWindowsEx fallback (unless prove-out forces it); Scoop; WSL
- **DoD:** Profile wire (`packages.wingetNeedsReboot: string[]` subset of `packages.winget`) → Plan emit; S1/S3 green; Hyper-V prove-out with forced reboot job before Done
- **Done:** 2026-08-04 — issue #29; Profile `wingetNeedsReboot` fail-closed subset; Plan emits `needsReboot`; Hyper-V prove-out: jq + needsReboot → `jobs.reboot` checkpoint → OS reboot → `checkpoint.resume` + `settle.resume_skip` → `Complete`/`jobs.ok` (skip re-settle on resume — Hyper-V IC/NTP clock jump otherwise blew wall-clock during settle)

### 18 — Scoop metal job

- **Issue:** [#30](https://github.com/yanai-sh/winmint/issues/30)
- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) · [BUILDPLAN](design/BUILDPLAN.md) · [research](research/2026-08-04-scoop-firstlogon-bootstrap.md)
- **Deliver:** job kind `scoop`; Profile `packages.scoop: string[]`; official FirstLogon bootstrap (network; fail closed offline) unless research spike overturns; Hyper-V prove-out
- **Out:** WSL; Wizard Scoop UI; offline-staged Scoop on ISO unless spike requires it
- **DoD:** bootstrap research note; Plan emit; Supervisor spawn; tests + Hyper-V with one small Scoop package — **metal milestone exit**
- **Done:** 2026-08-04 — issue #30; research note; Profile `scoop`/`scoopNeedsReboot`; Supervisor inbox `powershell.exe` admin bootstrap + `scoop.cmd install`; Hyper-V prove-out green (`scoop install curl` → `outcome=Complete`/`jobs.ok`; guest has `scoop.cmd` + curl/7zip)

### 19 — Keep-flag capabilities / features matrix spike

- **Issue:** [#31](https://github.com/yanai-sh/winmint/issues/31)
- **Design:** [KEEPFLAG](design/KEEPFLAG.md) · [ADR-005](decisions/ADR-005-keep-flag-matrix.md) · [ADR-006](decisions/ADR-006-post-keepflag-sequencing.md)
- **Deliver:** research note pinning target media (25H2 ARM64 English); DISM capability/feature id matrix; thin acceptance pin list — **no** product-default recommended set
- **Out:** implement adapters (ticket **20**); leftover confidence; CDM-as-primary; Profile presets; schema `v2`
- **Done:** 2026-08-04 — issue #31; [research note](research/2026-08-04-capabilities-features-matrix.md); pins `App.StepsRecorder~~~~0.0.1.0`, `WMIC~~~~`, `WorkFolders-Client`; Profile fields `removeCapabilities` / `disableOptionalFeatures`

### 20 — Offline ImageServicing capabilities from Profile

- **Issue:** [#32](https://github.com/yanai-sh/winmint/issues/32)
- **Design:** [IMAGESERVICING](design/IMAGESERVICING.md) · [KEEPFLAG](design/KEEPFLAG.md) · spike from **19**
- **Deliver:** Profile field → BuildPlan → offline servicing adapter; digests as applicable; FirstLogon not required
- **Out:** live FirstLogon feature flips; product-default recommended set
- **Done:** 2026-08-04 — issue #32; `debloat.removeCapabilities` / `disableOptionalFeatures`; catalogs; opcodes + DISM kernels; digests; S1/S2 tests; Apply-path digests (RunPlan side-car merge covered by `CapabilityPlanTests.RunPlan_merges_capability_and_feature_side_digests_into_evidence`; acceptance Profile + S4 assert pins capability/feature digests)

### 21 — Israel DMA sample + monotonic settle deadlines

- **Issue:** [#33](https://github.com/yanai-sh/winmint/issues/33)
- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) · [ADR-003](decisions/ADR-003-dma-interop.md)
- **Deliver:** `samples/israel.profile.json` (en-US / GeoId 117 / `Israel Standard Time` / location on; Local+autoLogon; no package matrix); tenure + settle deadlines via monotonic `TimeProvider` timestamps; Smoke harness disables Hyper-V Time Synchronization IC; Hyper-V prove-out
- **Out:** Hebrew UI; replace acceptance/smoke UK restore; package matrix; re-settle after reboot; ExitWindowsEx; WSL; Wizard packages UI
- **DoD:** S3 fake UTC +3h jump during settle does not false-timeout; `just check` green; Hyper-V israel Profile hard settle fields green
- **Done:** 2026-08-05 — issue #33; monotonic tenure/settle deadlines; IC Time Synchronization off in harness; `samples/israel.profile.json`; Hyper-V prove-out green (`outcome=Complete`, `settle.location_warn`, Time Synchronization disabled)

### 22 — Wizard packages UI

- **Issue:** [#34](https://github.com/yanai-sh/winmint/issues/34)
- **Design:** [ARCHITECTURE](ARCHITECTURE.md) · [BUILDPLAN](design/BUILDPLAN.md) · [CONTEXT](../CONTEXT.md) Wizard · [ADR-006](decisions/ADR-006-post-keepflag-sequencing.md)
- **Blocked by:** — · **Ready when:** **21** done — start here (apply `ready-for-agent` when starting)
- **Deliver:** Wizard authors `packages.winget` / `wingetNeedsReboot` / `packages.scoop` / `scoopNeedsReboot` as raw newline-separated id lists (empty default); `WizardProfileComposer` emits Profile wire (omit empty `packages` / empty sibling arrays); Validate/Plan/Save via existing BuildPlan; S1b compose→Plan tests
- **Out:** WSL; live winget/Scoop search; package presets catalog; capabilities UI; schema `v2`; elevating Wizard; full polish; Hyper-V Smoke DoD
- **DoD:**
  - Four lists in Wizard UI; composer + Plan fail-closed on reboot-subset errors
  - S1b tests green; `just check` green
  - No schema bump; no second planning brain
- **Done:** 2026-08-05 — issue #34; `WizardProfileComposer` packages + `ParseIdList`; Avalonia four lists; S1b `WizardPackagesTests`

---

## Deferred backlog (tickets 23–30)

Post-**22** polish and close-out. Do not label `ready-for-agent` until starting that card.

| # | Title | Module | Issue | Ready when |
|---|--------|--------|-------|------------|
| 23 | Metal `wsl` job kind | ProvisioningSession | [#35](https://github.com/yanai-sh/winmint/issues/35) | **22** done — **done** |
| 24 | ExitWindowsEx reboot fallback | ProvisioningSession | [#36](https://github.com/yanai-sh/winmint/issues/36) | **23** done — **done** |
| 25 | Wizard polish (caps/features + WSL + Israel DMA) | BuildPlan host | [#37](https://github.com/yanai-sh/winmint/issues/37) | **24** done — **done** |
| 26 | Leftover confidence spike | Design / research | [#38](https://github.com/yanai-sh/winmint/issues/38) | **25** done — **done** |
| 27 | CDM-as-primary decision | ADR | [#39](https://github.com/yanai-sh/winmint/issues/39) | **26** done — **done** |
| 28 | DPAPI metal secrets (best-effort wipe) | ProvisioningSession | [#40](https://github.com/yanai-sh/winmint/issues/40) | **27** done — **done** |
| 29 | Proactive GDI splash status text | ProvisioningSession | [#41](https://github.com/yanai-sh/winmint/issues/41) | **28** done — **done** |
| 30 | Hardware M4 evidence bars | Acceptance S4 | [#42](https://github.com/yanai-sh/winmint/issues/42) | **29** done — **done** |

### 23 — Metal `wsl` job kind

- **Issue:** [#35](https://github.com/yanai-sh/winmint/issues/35)
- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) · [ADR-006](decisions/ADR-006-post-keepflag-sequencing.md)
- **Deliver:** Profile `packages.wsl` / `wslNeedsReboot`; Plan emit `kind: wsl`; Supervisor spawns `wsl.exe --install -d … --no-launch`
- **Out:** offline-staged distros; guest pwsh
- **DoD:** S1 Plan + S3 argv tests; fail-closed subset; unknown kinds unchanged
- **Done:** 2026-08-05 — issue #35; `WslJobsTests`; Wizard WSL lists (**25**)

### 24 — ExitWindowsEx reboot fallback

- **Issue:** [#36](https://github.com/yanai-sh/winmint/issues/36)
- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md)
- **Deliver:** `Win32SystemReboot` tries `ExitWindowsEx(EWX_REBOOT|EWX_FORCE)` with `SeShutdownPrivilege`; fall back to `shutdown.exe /r /t 0 /f`
- **Out:** guest pwsh; WSL
- **DoD:** primary path wired; fallback on refusal; existing reboot-resume tests green
- **Done:** 2026-08-05 — issue #36; `Win32SystemReboot.cs`

### 25 — Wizard polish (caps/features + WSL + Israel DMA)

- **Issue:** [#37](https://github.com/yanai-sh/winmint/issues/37)
- **Design:** [BUILDPLAN](design/BUILDPLAN.md) · [ARCHITECTURE](ARCHITECTURE.md) · [KEEPFLAG](design/KEEPFLAG.md)
- **Deliver:** Wizard authors capability/feature lists (empty ⇒ Acceptance preset pins); `packages.wsl` / `wslNeedsReboot`; Israel DMA quick-fill; Validate/Plan/Save unchanged brain
- **Out:** live distro/package search; schema `v2`; elevating Wizard; full UX polish
- **DoD:** package lists (winget + scoop + wsl) + caps/features; Acceptance preset expands AppX+caps+features; compose→Plan tests; `just check` green
- **Done:** 2026-08-05 — issue #37; `MainWindow` / `KeepFlagPresets` / composer
### 26 — Leftover confidence spike

- **Issue:** [#38](https://github.com/yanai-sh/winmint/issues/38)
- **Design:** [KEEPFLAG](design/KEEPFLAG.md) · [ADR-005](decisions/ADR-005-keep-flag-matrix.md)
- **Deliver:** research note — deferred product code; catalog+exclude ideas from BCU without shipping BCU; offline digests + FirstLogon safety-net remain primary; no CDM-as-primary until **27**
- **Out:** implement leftover confidence; product-default recommended set; schema `v2`; Profile presets
- **DoD:** [research note](research/2026-08-05-leftover-confidence.md) cites existing notes; ≤ ~80 lines
- **Done:** 2026-08-05 — issue #38

### 27 — CDM-as-primary decision

- **Issue:** [#39](https://github.com/yanai-sh/winmint/issues/39)
- **Design:** [KEEPFLAG](design/KEEPFLAG.md) · spike **26**
- **Deliver:** ADR — offline ImageServicing + FirstLogon safety-net primary; CDM not keep-flag control plane for M1/M2
- **Out:** CDM Supervisor job; Profile CDM fields
- **DoD:** [ADR-007](decisions/ADR-007-cdm-not-primary.md) Accepted
- **Done:** 2026-08-05 — issue #39

### 28 — DPAPI metal secrets (best-effort wipe)

- **Issue:** [#40](https://github.com/yanai-sh/winmint/issues/40)
- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md#secrets-smoke)
- **Deliver:** `FileSecretScrubber` overwrites previous bundle bytes with random before redacted JSON rewrite; comment that full DPAPI host→guest channel stays future
- **Out:** full DPAPI staging channel; cryptographic in-process scrub
- **DoD:** unit test asserts password empty on disk after `Wipe`; `just check` green
- **Done:** 2026-08-05 — issue #40; `FileSecretScrubberTests`

### 29 — Proactive GDI splash status text

- **Issue:** [#41](https://github.com/yanai-sh/winmint/issues/41)
- **Design:** [SPLASH](design/SPLASH.md) · [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md)
- **Deliver:** `GdiSplashPresenter` draws status via `TextOutW` on opaque fill; ponytail comment — full ID2D1Factory only if S4 FirstPaintBudget still fails
- **Out:** D2D COM; new NuGet; file status control plane
- **DoD:** AOT-safe `LibraryImport` only; first paint shows in-memory status
- **Done:** 2026-08-05 — issue #41; `GdiSplashPresenter.cs`

### 30 — Hardware M4 evidence bars

- **Issue:** [#42](https://github.com/yanai-sh/winmint/issues/42)
- **Design:** [Smoke](specs/2026-07-27-smoke.md) · harness `tools/vm/`
- **Deliver:** `Assert-SmokeEvidence.ps1` optional `-HardwareM4` or `WINMINT_M4=1` — `firstPaintMs` ≤ budget **fail** (not warn); phases require `settle.ok` or `settle.location_warn`
- **Out:** Hyper-V hardware harness fork; default Smoke path unchanged (M4 off)
- **DoD:** script comment documents M4; fixture S4 assert path unchanged with M4 off
- **Done:** 2026-08-05 — issue #42; `Assert-SmokeEvidence.ps1`

**Still out (policy — no ticket):** Profile presets-in-JSON; product-default recommended remove-list; schema `v2` without a break; leftover-confidence *product* cleanup; full DPAPI host→guest channel; full D2D splash; full Wizard UX polish beyond list authoring. See [DESIGN](DESIGN.md#decisions-locked-grill).

---

## Doc map (avoid duplicate backlogs)

| Need | Read |
|------|------|
| Why / locks | DESIGN, V1-LESSONS, ADRs |
| What to build (this file) | **TICKETS** |
| When / milestones | ROADMAP |
| How to run sessions | AGENTIC, TDD |
| Domain behaviour | Smoke spec, ARCHITECTURE, design/* |
