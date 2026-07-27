# M1 work backlog (canonical)

**Authority for stories:** [Smoke spec](specs/2026-07-27-smoke.md)  
**Authority for locks:** [DESIGN grill](DESIGN.md#decisions-locked-grill) · module designs under [design/](design/)  
**Schedule / order:** [ROADMAP](ROADMAP.md)  
**TDD seams:** [TDD](TDD.md)

## Implementation hold

**Status: HOLD — do not `/implement` product tickets yet.**  
Maintainer pause after Design Acceptance (quality/debloat of the plan pack). Scaffold may stay green; no BuildPlan/Servicing/Provisioning feature code until this hold is lifted in this file and [ROADMAP](ROADMAP.md).

| When hold lifts | First action |
|-----------------|--------------|
| Maintainer sets hold → **Released** below | File Issues 01–08 (if missing), then `/implement` **01** only |

**Hold:** **Active** (2026-07-28)

---

## Ticket index

| # | Title | Module | Stories | Blocked by | Ready when |
|---|--------|--------|---------|------------|------------|
| 01 | Profile + plan + Cli `validate`/`plan` | BuildPlan | 1–2 | — | Hold released |
| 02 | Servicing apply + Shell stamp + Cli `build`/`apply` | ImageServicing | 3 | 01 | 01 done |
| 03 | Machine setup stamps | ProvisioningSession | 4 | 02 | 02 done |
| 04 | Shell splash + status + evidence | ProvisioningSession | 5, 13 | 03 | 03 done **+ splash spike** |
| 05 | DMA settle | ProvisioningSession | 6–8 | 04 | 04 done |
| 06 | Stub jobs + unlock/timeout + reboot | ProvisioningSession | 9–12 | 05 | 05 done |
| 07 | `Test` lane on export | BuildPlan + ImageServicing | 14 | 02 | May parallel 03–06 |
| 08 | Hyper-V Smoke harness | Acceptance S4 | 15 | 06, 07 | 06+07 done |

**Non-ticket prerequisite:** splash prototype spike ([SPLASH](design/SPLASH.md)) before **04** is `ready-for-agent`.

---

## Ticket cards

### 01 — BuildPlan + Cli plan

- **Design:** [BUILDPLAN](design/BUILDPLAN.md) · **Seam:** S1  
- **Deliver:** Profile DTOs + source-gen; `TryParseProfile`/`Plan`; Cli `validate`/`plan`; freeze JSON field names; contract tests (password, DMA Ireland, opcodes, `Test` lane).  
- **Out:** elevation, DISM, splash, Servicing.  
- **DoD:** S1 tracers green; Local+autoLogon only; no `.ps1` paths in stages; `just check` green.

### 02 — ImageServicing + Cli build

- **Design:** [IMAGESERVICING](design/IMAGESERVICING.md) · **Seam:** S2  
- **Deliver:** `servicing/RunPlan.ps1` + thin kernels; one UAC `Apply`; offline Shell stamp; Cli `build`/`apply`.  
- **Out:** Profile branching in `.ps1`; guest FirstLogon.  
- **DoD:** Stage order + Shell stamp path; workdir preserved on failure; kernels param-only.

### 03 — Machine setup

- **Design:** [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) · **Seam:** S3  
- **Deliver:** `Run(MachineSetup)` — autologon stamp, Shell verify/restamp, secret wipe; SetupComplete non-zero on fail.  
- **Out:** splash, settle, jobs.  
- **DoD:** Fake-registry tests; never `defaultuser0`+AutoAdminLogon; logs under `%ProgramData%\WinMint\`.

### 04 — Shell splash + evidence

- **Design:** PROVISIONINGSESSION + [SPLASH](design/SPLASH.md) · **Seam:** S3  
- **Prerequisite:** splash spike appendix filled.  
- **Deliver:** First paint before settle; in-memory status; evidence projections (`evidence/v1`).  
- **Out:** hard input lock; real winget matrix.  
- **DoD:** Recording presenter shows paint-before-settle; evidence write-only.

### 05 — DMA settle

- **Design:** PROVISIONINGSESSION · **Seam:** S3  
- **Deliver:** Final-snapshot hard locale/GeoID/TZ; soft location-services warn+continue; fail path skips jobs.  
- **DoD:** Scripted snapshot tests; no sticky intermediate fails.

### 06 — Jobs + unlock + reboot

- **Design:** PROVISIONINGSESSION · **Seam:** S3  
- **Deliver:** Stub jobs; wall-clock timeout; failed dwell; checkpoint/reboot keeps Shell; stale heartbeat fail-open.  
- **DoD:** Policy defaults per [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md#smoke-defaults-grill-locked); ProgramData checkpoint+heartbeat.

### 07 — Test image-quality lane

- **Design:** BUILDPLAN + IMAGESERVICING · **Seams:** S1/S2  
- **Deliver:** `Test` vs `Release` → `ExportWim` params; manifest records lane.  
- **DoD:** Contract/integration asserts `cleanup=skip` on Test.

### 08 — Smoke acceptance

- **Design:** [CONTRACTS](design/CONTRACTS.md) · [SPLASH](design/SPLASH.md) · **Seam:** S4  
- **Deliver:** One pwsh entry under `tools/vm/`; Pro + DMA-on profile; evidence pull.  
- **DoD:** Shell tenure + splash before Explorer; DMA hard fields; unlock; lane marker; paint time recorded (warn if >2s).

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
