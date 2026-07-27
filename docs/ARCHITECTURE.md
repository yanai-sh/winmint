# WinMint v2 architecture (locked)

Greenfield product repo [`yanai-sh/winmint`](https://github.com/yanai-sh/winmint) — no WinMint v1 contract or CLI back-compat. Decisions: [ADR-002](decisions/ADR-002-v2-architecture.md), [ADR-004](decisions/ADR-004-stack-and-guest-control-plane.md). Stack pins: [STACK.md](STACK.md). Glossary: [CONTEXT.md](../CONTEXT.md). Smoke: [specs/2026-07-27-smoke.md](specs/2026-07-27-smoke.md).

**Phase:** gate + hold: [ROADMAP](ROADMAP.md#design-acceptance) · [TICKETS](TICKETS.md). Canonical: [DESIGN](DESIGN.md) · [ROADMAP](ROADMAP.md) · [TDD](TDD.md) · [design/](design/) · [AGENTIC](agents/AGENTIC.md).

**Design stance:** prefer modern elegant solutions over v1 when they conflict. Smoke and metal share Supervisor / settle / job executor / reboot / lock; differ in Profile job set and evidence bars only. Grill: [DESIGN](DESIGN.md#decisions-locked-grill).


## Architectural style

**Use: pipeline orchestrator + ports & adapters** (hexagonal at **one** hard seam — elevated Servicing — and only when a second adapter justifies a port).

| Idea | How it shows up here |
|------|----------------------|
| **Pipeline / orchestrator** | Unelevated C# sequences validate → plan → emit job/unattend → invoke Servicing → collect evidence |
| **Port** | Small surface for “run elevated imaging job” — introduce only when prod `pwsh -File` and a test fake share a shape (not day-one) |
| **Adapter** | Thin `pwsh -File` kernels under `servicing/` (DISM, hive, oscdimg); filesystem staging |
| **Deep modules** | Fat behaviour behind small interfaces — see below |

**Do not use as the backbone:** Clean Architecture onion, tactical DDD / bounded-context packing, or microservices. This is one batch imaging pipeline + elevated Servicing helper. Do not pre-split Orchestrator into Authoring / Planning / Contracts projects.

## Deep modules (product seams)

Three modules carry the product. Projects and scripts are hosts/adapters around them — not parallel brains.

| Module | Lives in | Interface (intent) | Hides |
|--------|----------|--------------------|-------|
| **BuildPlan** | `WinMint.Orchestrator` | Profile + run options → plan artifacts (opcodes, not script paths) — [design](design/BUILDPLAN.md) | Schema details, DMA Ireland latch, password/autologon plan rules |
| **ImageServicing** | Orchestrator call-out → `servicing/` | Apply plan to Source ISO → image evidence — [design](design/IMAGESERVICING.md) | DISM/WIM/hive/oscdimg; opcode→script map |
| **ProvisioningSession** | `WinMint.Provisioning` | `--machine-setup` *or* Shell → `SessionResult` — [design](design/PROVISIONINGSESSION.md) | Splash, stamps, DMA settle, jobs, checkpoint |

**Hosts (not deep modules):** `WinMint.Cli` and later Avalonia Wizard are thin clients of **BuildPlan**. `servicing/*.ps1` are adapters of **ImageServicing**, not a second product CLI.

**Seam discipline:**

- One adapter = call through directly (e.g. Orchestrator invokes `pwsh -File`). Two adapters (prod + test fake) = real port type.
- Imaging **stages** Provisioning bits; it must not call live Provisioning APIs. Provisioning never mounts WIMs.
- Evidence JSON is a **projection** of in-memory Supervisor status — not a control-plane mailbox (reject v1 setup-shell status/control file pairs as architecture).
- If a new type does not sit behind one of these three modules, question it (YAGNI).

**Test surfaces (same as module interfaces):** (1) BuildPlan contracts, (2) ProvisioningSession phase machine, (3) Hyper-V Smoke acceptance evidence (highest product seam).

## Ownership

| Layer | Owns | Must not own |
|-------|------|----------------|
| **Orchestrator** (C#) | BuildPlan; Profile validation; plan / unattend / job JSON; drives Servicing | In-process DISM / offline hive |
| **Servicing** (elevated `pwsh -File`) | Thin DISM/WIM/hive/export adapters | Product CLI, fat monolith, guest FirstLogon |
| **Provisioning Supervisor** (C# AOT) | ProvisioningSession: Machine setup, Shell tenure, splash, DMA settle, jobs, evidence snapshots, unlock | Offline imaging |
| **Cli** | Flags → BuildPlan | Profile schema ownership, Servicing |
| **Wizard** (Avalonia, later) | Profile authoring UI → same BuildPlan | Servicing, ISO splash |

## Runtime shape

```
Unelevated C# CLI / Orchestrator  →  elevated pwsh Servicing adapters
                                 →  stages Provisioning binary; stamps Shell offline
Avalonia wizard (later)          →  same BuildPlan (Orchestrator)

Guest:
  SetupComplete.cmd → Provisioning --machine-setup
  Winlogon Shell = same AOT binary
    → in-process splash → DMA settle → provisioning jobs
    → complete/failed/timeout → explorer.exe
    → reboot → checkpoint, keep Shell, resume
```

## v1 harvest rule

Sibling archive [`winmint_v1`](https://github.com/yanai-sh/winmint_v1) and media shelf `winmint_v2_future-assets/` are **archaeology**, not topology to copy. **Why greenfield:** [design/V1-LESSONS.md](design/V1-LESSONS.md) (FirstLogon multi-process + JSON mailbox + hard-to-test ambient engine).

| Take | Leave |
|------|-------|
| Invariants (password-required local, DMA Ireland, image-quality lanes, Hyper-V Smoke = Pro, fail-open unlock) | `src/runtime/{image,setup,firstlogon}` folder trees |
| Evidence / VM acceptance *ideas* | Peer Splash.exe + JSON status/control mailbox |
| Behaviour notes mapped into BuildPlan / ProvisioningSession | Guest pwsh PreLock / agent module catalog as control plane |
| | `tools/ui-bridge`, wrapping `WinMint.ps1`, dual ISO hosts; Shell↔RunOnce coupling |

## First vertical: Smoke

Stories, constraints, tracer map: [Smoke spec](specs/2026-07-27-smoke.md). Backlog/hold: [TICKETS](TICKETS.md).

Standing architecture invariants (also in grill locks):

### Machine setup + Autologon / Shell

1. Servicing stamps Shell offline to Supervisor path.
2. Machine setup: autologon stamp → fail-closed Shell verify/restamp → secret wipe. No jobs.
3. Never `DefaultUserName=defaultuser0` with `AutoAdminLogon` for first interactive logon.
4. MachineSetup `Failed` ⇒ non-zero exit from Supervisor/SetupComplete.

### Shell tenure

Supervisor as Shell + splash = provisioning lock. Unlock = `explorer.exe` + exit. Fail-open on complete/failed/timeout (failed dwell). `reboot` keeps Shell + checkpoint. Stale heartbeat ⇒ fail-open on next start. Durable state: `%ProgramData%\WinMint\`.

### DMA settle

Final snapshot authoritative. Hard: locale / GeoID / TZ. Soft: location-services (warn, continue). Same policy Smoke and metal.

### Splash and status

In-process Direct2D/GDI; paint before settle; appearance once before unlock. In-memory status; JSON = evidence projection only.

### Jobs + reboot

Child-process executor; Smoke stub set vs metal set. `needsReboot` ⇒ checkpoint, keep Shell, reboot, resume.

## Image quality (run override, not Profile)

| Lane | Export / cleanup | Use |
|------|------------------|-----|
| **Test** | Soft/no recompress; skip WinSxS cleanup | Smoke / iteration |
| **Release** | Hard recompress + `StartComponentCleanup` | Published / metal ISOs |

Manifest records lane. Harness caching remains harness concern.

## Payload strategy

Stage SetupComplete.cmd, Supervisor, job/bundle manifests, media. No v1 `WinMint.ps1`; no guest pwsh. [Harvest rule](#v1-harvest-rule).

## Scaffold / hold rules

- **Implement hold:** [TICKETS](TICKETS.md) — no feature tickets until released.
- Honor [grill locks](DESIGN.md#decisions-locked-grill).
- No empty trees ahead of tickets; no hypothetical Servicing ports; no MediatR/Generic Host/Contracts project by default.
- Ticket 08: one pwsh entry under `tools/vm/`. Ticket 04: splash spike first.

