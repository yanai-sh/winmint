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
| 04 | Shell splash + status + evidence | ProvisioningSession | 5, 13 | 03 | 03 done **+ splash spike** |
| 05 | DMA settle | ProvisioningSession | 6–8 | 04 | 04 done |
| 06 | Stub jobs + child-process executor | ProvisioningSession | 9–10 | 05 | 05 done |
| 07 | Unlock + timeout + stale fail-open | ProvisioningSession | 12 + appearance | 06 | 06 done |
| 08 | Checkpoint reboot keeps Shell | ProvisioningSession | 11 | 07 | 07 done |
| 09 | `Test`/`Release` export lane | BuildPlan + ImageServicing | 14 | 02 | May parallel 03–08 |
| 10 | Hyper-V Smoke harness | Acceptance S4 | 15 | 08, 09 | 08+09 done |

**Non-ticket prerequisite:** splash prototype spike ([SPLASH](design/SPLASH.md)) before **04** is `ready-for-agent`. Spike bar: timing + ordering + one fresh-cycle replay in the appendix.

**Renumber note (2026-07-29):** old 06 (jobs+unlock+reboot) → **06 / 07 / 08**; old 07 (Test lane) → **09**; old 08 (Smoke harness) → **10**.

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

### 04 — Shell splash + status + evidence

- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) + [SPLASH](design/SPLASH.md) · **Seam:** S3 · **Stories:** 5, 13
- **Blocked by:** 03 · **Ready when:** 03 done **and** splash spike appendix has timing + ordering + one fresh-cycle replay
- **Deliver:**
  - First opaque splash frame before settle starts
  - In-memory splash status (not a file control plane)
  - Evidence projections: `winmint.provisioning.evidence/v1` (write-only)
  - Settle phase may be a **no-op/stub hook** until ticket **05** (enough to assert paint-before-settle order)
- **Out:** hard input lock; real winget matrix; Hyper-V / S4 harness; real DMA restore logic (ticket **05**)
- **DoD:**
  - Recording presenter asserts paint-before-settle **order** (not wall-clock OS latency)
  - Evidence is write-only; session never reads evidence JSON to decide the next phase
- **First red:** `Show` (or equivalent) recorded before settle poll begins (S3).

### 05 — DMA settle

- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) · **Seam:** S3 · **Stories:** 6–8
- **Blocked by:** 04 · **Ready when:** 04 done
- **Deliver:**
  - Bounded restore then **final snapshot** for hard locale / GeoID / TZ
  - Soft location-services: warn + continue (not a hard gate)
  - Hard settle failure skips jobs
- **Out:** real network location UX polish; metal-only settle forks; job executor details (ticket **06**)
- **DoD:**
  - Scripted region-snapshot tests: intermediate probe failures are **non-authoritative**
  - Only the final snapshot gates hard fields
  - Hard fail ⇒ jobs not started
- **First red:** Final hard GeoID mismatch ⇒ `Failed` path and no job start (S3).

### 06 — Stub jobs + child-process executor

- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) · **Seam:** S3 · **Stories:** 9–10
- **Blocked by:** 05 · **Ready when:** 05 done
- **Deliver:**
  - Smoke stub job set (no real WSL / browser matrix)
  - Supervisor runs jobs as child processes; one executor shape for Smoke and metal
- **Out:** unlock / timeout / stale policy (ticket **07**); checkpoint / reboot (ticket **08**); real package matrix
- **DoD:**
  - Stub jobs run via `Run` + process-host fakes
  - Jobs never start when prior hard settle failed
- **First red:** Stub job invoked as child process after green settle (S3).

### 07 — Unlock + timeout + stale fail-open

- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) · **Seam:** S3 · **Stories:** 12 (+ appearance from Implementation Decisions)
- **Blocked by:** 06 · **Ready when:** 06 done
- **Deliver:**
  - Wall-clock timeout → `Failed` + unlock; failed dwell before unlock
  - Stale / missing heartbeat past `StaleTenureThreshold` → fail-open `Failed` + unlock
  - Profile appearance applied **once** before Explorer unlock on success
  - Policy defaults per [smoke defaults](design/PROVISIONINGSESSION.md#smoke-defaults-grill-locked)
- **Out:** checkpoint / reboot-keeps-Shell (ticket **08**); hard input lock
- **DoD:**
  - `FakeTimeProvider`: timeout unlocks
  - Stale tenure → `Failed` + unlock
  - Success path: appearance applied once, then unlock
- **First red:** Wall-clock timeout yields unlock (S3).

### 08 — Checkpoint reboot keeps Shell

- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) · **Seam:** S3 · **Stories:** 11
- **Blocked by:** 07 · **Ready when:** 07 done
- **Deliver:**
  - Job `needsReboot` → durable checkpoint under `%ProgramData%\WinMint\` + keep Supervisor as Shell
  - Resume after reboot continues Shell tenure (no Explorer flash)
- **Out:** unlock-on-complete/failed (ticket **07**); real reboot-required package matrix
- **DoD:**
  - `Reboot` outcome does **not** unlock
  - Checkpoint written; Shell retained; resume continues tenure
- **First red:** `needsReboot` ⇒ `Reboot` + checkpoint + Shell kept (S3).

### 09 — `Test`/`Release` export lane

- **Design:** [BUILDPLAN](design/BUILDPLAN.md) + [IMAGESERVICING](design/IMAGESERVICING.md) · **Seams:** S1 / S2 · **Stories:** 14
- **Blocked by:** 02 · **Ready when:** 02 done (may parallel 03–08)
- **Deliver:**
  - `Test` vs `Release` → `ExportWim` params
  - Manifest / report records which lane ran
- **Out:** new Profile fields beyond lane; ISO byte asserts; guest behaviour
- **DoD:**
  - Test ⇒ fast compression + `cleanup=skip` (per [IMAGESERVICING](design/IMAGESERVICING.md))
  - Release ⇒ `compression=max` + `cleanup=full`
  - Manifest lane matches run options
- **First red:** Explicit `ImageQuality.Release` ⇒ export params differ from Test (BUILDPLAN tracer 5 / S1–S2).

### 10 — Hyper-V Smoke harness

- **Design:** [CONTRACTS](design/CONTRACTS.md) · [SPLASH](design/SPLASH.md) · **Seam:** S4 · **Stories:** 15 · **Speed:** [TDD](TDD.md#speed-rules)
- **Blocked by:** 08, 09 · **Ready when:** 08+09 done
- **Deliver:**
  - One pwsh entry under `tools/vm/` (“run Smoke → evidence”)
  - Pro + DMA-on acceptance Profile; evidence pull
- **Out:** metal / hardware acceptance; guest pwsh; peer Splash; multi-entrypoint harness forest; Hyper-V-only settle/executor fork
- **Optional later (harness only):** differencing VHD from parent base; ISO rebuild only on plan/payload digest change; careful servicing workdir reuse
- **DoD:**
  - Splash before Explorer; DMA hard fields green **or** failed DMA path with evidence + unlock
  - Unlock on complete/failed; lane marker present; paint time recorded (**warn** if > 2.0 s)
  - Stall fail-fast (Shell/OOBE/autologon hang) before burning `WallClockTimeout` (90 min)
  - Not part of `just check` (S4 / `just smoke` when gated)
- **First red:** Harness returns evidence folder with splash-before-Explorer marker (S4).

---

## Explicitly not in M1 backlog

Wizard, debloat matrix, BitLocker, hardware acceptance, guest pwsh, peer Splash, Home Smoke SKU, MicrosoftOobe, enterprise secrets, MediatR/Generic Host/Contracts project.

---

## Doc map (avoid duplicate backlogs)

| Need | Read |
|------|------|
| Why / locks | DESIGN, V1-LESSONS, ADRs |
| What to build (this file) | **TICKETS** |
| When / milestones | ROADMAP |
| How to run sessions | AGENTIC, TDD |
| Domain behaviour | Smoke spec, ARCHITECTURE, design/* |
