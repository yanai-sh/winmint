# WinMint architecture

Greenfield product repo [`yanai-sh/winmint`](https://github.com/yanai-sh/winmint) — no WinMint v1 contract or CLI back-compat. Living rules: [DESIGN](DESIGN.md). Stack pins: [STACK](STACK.md). Glossary: [CONTEXT](../CONTEXT.md).

**Design stance:** prefer modern elegant solutions over v1 when they conflict. Smoke and Primary share Supervisor / settle / job executor / reboot / lock; differ in Profile job set and evidence bars only.

## Architectural style

**Pipeline orchestrator + ports & adapters** (hexagonal at **one** hard seam — elevated Servicing — and only when a second adapter justifies a port).

| Idea | How it shows up |
|------|-----------------|
| **Pipeline / orchestrator** | Unelevated C# sequences validate → plan → emit job/unattend → invoke Servicing → collect evidence |
| **Port** | “Run elevated imaging job” — only when prod `pwsh -File` and a test fake share a shape |
| **Adapter** | Thin `pwsh -File` kernels under `servicing/`; filesystem staging |
| **Deep modules** | Small interfaces; split fat files by kind/phase when they resist change — below |

**Do not use as the backbone:** Clean Architecture onion, tactical DDD packing, microservices, MediatR, or AutoMapper. One batch imaging pipeline + elevated Servicing helper. Do not invent Authoring / Planning product splits for ceremony.

## Deep modules

| Module | Lives in | Interface (intent) | Hides |
|--------|----------|--------------------|-------|
| **BuildPlan** | `WinMint.Orchestrator` | Profile + run options → plan artifacts — [design](design/BUILDPLAN.md) | Schema, DMA Ireland latch, password/autologon plan rules |
| **ImageServicing** | Orchestrator → `servicing/` | Apply plan to Source ISO → evidence — [design](design/IMAGESERVICING.md) | DISM/WIM/hive/oscdimg; opcode→script map |
| **ProvisioningSession** | `WinMint.Provisioning` | `--machine-setup` *or* Shell → `SessionResult` — [design](design/PROVISIONINGSESSION.md) | Splash, stamps, DMA settle, jobs, checkpoint |

**Front ends (not deep modules):** `WinMint.Cli` and Avalonia Wizard are thin clients of **HostCompile** (Profile → Plan → ImageServicing). The Wizard shell owns navigation and one `WizardSession`; Source, Account, Software, and Review views bind through stage-specific interfaces. Review is projected from one immutable `HostReview`, including effective package facts and Orchestrator-owned `PlanDiff`. `servicing/*.ps1` are ImageServicing adapters, not a second product CLI.

**Seam discipline:**

- One adapter = call through directly. Two adapters (prod + test fake) = real port type.
- Imaging **stages** Provisioning bits; it must not call live Provisioning APIs. Provisioning never mounts WIMs.
- Evidence JSON is a **projection** of in-memory Supervisor status — not a control-plane mailbox.
- If a new type does not sit behind one of these three modules, question it.
- “Deep module” means clear ownership — not one god file. Prefer thin files behind the module entrypoint.

**Test surfaces:** (1) BuildPlan contracts, (2) ProvisioningSession phase machine, (3) Hyper-V Smoke acceptance evidence.

## Ownership

| Layer | Owns | Must not own |
|-------|------|----------------|
| **Orchestrator** (C#) | BuildPlan; Profile validation; plan / unattend / job JSON; drives Servicing | In-process DISM / offline hive |
| **Servicing** (elevated `pwsh -File`) | Thin DISM/WIM/hive/export adapters | Product CLI, fat monolith, guest FirstLogon |
| **Provisioning Supervisor** (C# AOT) | ProvisioningSession | Offline imaging |
| **Cli** | Flags → HostCompile | Profile schema ownership, Servicing |
| **Wizard** (Avalonia) | Profile authoring UI → HostCompile | Servicing, ISO splash |

## Runtime shape

```
Unelevated C# CLI / Wizard / Orchestrator  →  elevated pwsh Servicing adapters
                                           →  stages Provisioning binary; stamps Shell offline

Guest:
  SetupComplete.cmd → Provisioning --machine-setup
  Winlogon Shell = same AOT binary
    → in-process splash → DMA settle → provisioning jobs
    → complete/failed/timeout → explorer.exe
    → reboot → checkpoint, keep Shell, resume
```

## v1 harvest rule

Sibling archive [`winmint_v1`](https://github.com/yanai-sh/winmint_v1) is **archaeology**, not topology to copy. **Why:** [V1-LESSONS](design/V1-LESSONS.md).

| Take | Leave |
|------|-------|
| Invariants (password-required local, DMA Ireland, lanes, Pro Smoke, fail-open unlock) | `src/runtime/{image,setup,firstlogon}` trees |
| Evidence / VM acceptance *ideas* | Peer Splash.exe + JSON mailbox |
| Behaviour notes mapped into BuildPlan / ProvisioningSession | Guest pwsh PreLock; `WinMint.ps1`; Shell↔RunOnce coupling |

## Standing invariants (guest path)

1. Servicing stamps Shell offline to Supervisor; Machine setup: autologon → fail-closed Shell verify/restamp → secret wipe. No jobs. Never `DefaultUserName=defaultuser0` with `AutoAdminLogon` for first interactive logon. MachineSetup Failed ⇒ non-zero exit.
2. Supervisor as Shell + splash = lock. Unlock = `explorer.exe` + exit. Fail-open on complete/failed/timeout. Reboot keeps Shell + checkpoint. Durable state: `%ProgramData%\WinMint\`.
3. DMA settle: final snapshot authoritative. Hard: locale / GeoID / TZ. Soft: location-services.
4. Splash: in-process Direct2D/GDI; paint before settle. Status in-memory; JSON = evidence only.
5. Jobs: child-process / delegated batch; `needsReboot` ⇒ checkpoint, keep Shell, reboot, resume. No guest pwsh product runtime.

## Image quality (run override)

| Lane | Export / cleanup | Use |
|------|------------------|-----|
| **Test** | Soft/no recompress; skip WinSxS cleanup | Smoke / iteration |
| **Release** | Hard recompress + `StartComponentCleanup` | Published compression bar |

**Package strictness is resolved at HostCompile:** Test is best-effort by default; Release is strict. `PackageStrictOverride` lets hosts preserve the lane default or explicitly force/suppress it, and the resolved bool is stamped into the guest bundle.

## Payload

Stage SetupComplete.cmd, Supervisor, job/bundle manifests, media. No v1 `WinMint.ps1`; no guest pwsh product runtime.
