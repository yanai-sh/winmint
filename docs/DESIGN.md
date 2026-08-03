# WinMint v2 — Design plan (canonical)

**Phase:** gate + hold: [ROADMAP](ROADMAP.md#design-acceptance) · [TICKETS](TICKETS.md).  
**Product:** Windows 11 ISO builder (greenfield). Host ARM64-first. Guest = C# Supervisor only.

## Read order

1. [CONTEXT](../CONTEXT.md) · [V1-LESSONS](design/V1-LESSONS.md)  
2. [ARCHITECTURE](ARCHITECTURE.md)  
3. This file + [design/](design/)  
4. [TICKETS](TICKETS.md) (backlog + hold) · [ROADMAP](ROADMAP.md)  
5. [Smoke](specs/2026-07-27-smoke.md) · [TDD](TDD.md) · [AGENTIC](agents/AGENTIC.md)

## Modules (accepted)

| Module | Doc |
|--------|-----|
| BuildPlan | [BUILDPLAN](design/BUILDPLAN.md) |
| ImageServicing | [IMAGESERVICING](design/IMAGESERVICING.md) |
| ProvisioningSession | [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) |

## Cross-cutting (accepted)

[CONTRACTS](design/CONTRACTS.md) · [SECRETS](design/SECRETS.md) · [SPLASH](design/SPLASH.md) · [V1-LESSONS](design/V1-LESSONS.md) · [KEEPFLAG](design/KEEPFLAG.md) (post-M1; design accepted)

## ADRs

[001](decisions/ADR-001-source-iso-legal.md) · [002](decisions/ADR-002-v2-architecture.md) · [003](decisions/ADR-003-dma-interop.md) · [004](decisions/ADR-004-stack-and-guest-control-plane.md) · [005](decisions/ADR-005-keep-flag-matrix.md) · [006](decisions/ADR-006-post-keepflag-sequencing.md)

## Decisions locked (grill)

Batch-grill rounds 1–4; shared understanding 2026-07-28. Post–keep-flag grill 2026-08-04 ([ADR-006](decisions/ADR-006-post-keepflag-sequencing.md)). Full table retained for agents:

| Topic | Lock |
|-------|------|
| Gate scope | Smoke M1 design; M2–M4 stubs |
| Modules | As written in design/* |
| Cross-cutting | CONTRACTS + SECRETS + SPLASH required |
| Sign-off | ROADMAP table only |
| Splash spike | Waived for gate; **required before ticket 04**; may run during hold (throwaway) |
| First paint | ≤ 2.0 s target; S3 order; S4 measure |
| Secrets | Lab honesty; fixtures inline OK; prefer path/env in Cli |
| Scaffold | Keep `src/` + `just check` |
| Profile fields | Freeze at ticket **01** |
| SessionPolicy | Smoke defaults per [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md#smoke-defaults-grill-locked) |
| Guest paths | `%ProgramData%\WinMint\` |
| MachineSetup fail | Non-zero exit; fail closed |
| S4 harness | Thin pwsh `tools/vm/` |
| Issues | File at release from hold / gate |
| Lanes | `Test` \| `Release` |
| Stale | Heartbeat + checkpoint ⇒ fail-open |
| Smoke accounts | Local+autoLogon only |
| Soft location | Location-services on/off; warn, continue |
| Cli | 01 `validate`/`plan`; 02 `build`/`apply` |
| DMA off | Schema OK; acceptance Profile = on |
| Hyper-V Smoke | Pro only |
| WIM commit | Single-image only — Mount exports edition; Export fail-closes if multi-index ([IMAGESERVICING](design/IMAGESERVICING.md#invariants) §7) |
| Post-13 sequencing | **M1 maintainer Smoke green before Wizard or keep-flag expansion** ([ADR-006](decisions/ADR-006-post-keepflag-sequencing.md)) |
| Post-13 tickets | Thin cards **14+**; no mega-epic; carry folds into owning card |
| Keep-flag expand | Capabilities/features, `v2`, Profile presets, leftover confidence, CDM-as-primary — **defer past Wizard** |
| Acceptance remove-list | Smoke **acceptance** Profile pins a **small frozen** remove-list (E2E keep-flag on M1 exit); schema default elsewhere remains empty; **no** product-default / opt-out recommended set |
| Schema | Stay on `winmint.profile/v1` until a breaking change forces `v2` |
| Metal jobs | After Wizard (**15**); first kind = `winget` only |
| OS reboot | Supervisor Win32 reboot on `NeedsReboot`; metal reboot matrix with metal jobs |
| AppearanceOnce | Optional bundle field until a Profile appearance story is grilled |
| Secrets hardening | Smoke plaintext+wipe; metal secrets later; inline JSON redact when next editing Machine setup |
| Splash D2D | Only if S4 FirstPaintBudget fails on real Smoke |
| S4 VHD/digest rebuild | Maintainer optimization — not a product ticket |
| `*Dto` rename | Opportunistic on next BundleLoader touch |
| Wizard | After M1 Smoke green; second BuildPlan host only |
| Hardware | M4; stricter evidence; no Supervisor fork |

**Deferred implement:** Wizard / hardware / metal jobs / keep-flag expansion — order per [ADR-006](decisions/ADR-006-post-keepflag-sequencing.md). Keep-flag AppX vertical (**11–13**) implemented. Profile property names frozen in ticket **01**; optional `debloat.removeProvisionedAppx` on v1.  
**Owned elsewhere:** AppearanceOnce consume path → ticket **07** (done); splash spike → [SPLASH](design/SPLASH.md) appendix.

## Design Acceptance

Sign-off: [ROADMAP](ROADMAP.md#design-acceptance) (grill lock: ROADMAP table only).

## After hold lifts

Work only from [TICKETS](TICKETS.md). Do not expand M2–M4 until M1 green or rescope ([ADR-006](decisions/ADR-006-post-keepflag-sequencing.md)).
