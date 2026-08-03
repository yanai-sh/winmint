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

[CONTRACTS](design/CONTRACTS.md) · [SECRETS](design/SECRETS.md) · [SPLASH](design/SPLASH.md) · [V1-LESSONS](design/V1-LESSONS.md)

## ADRs

[001](decisions/ADR-001-source-iso-legal.md) · [002](decisions/ADR-002-v2-architecture.md) · [003](decisions/ADR-003-dma-interop.md) · [004](decisions/ADR-004-stack-and-guest-control-plane.md)

## Decisions locked (grill)

Batch-grill rounds 1–4; shared understanding 2026-07-28. Full table retained for agents:

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

**Deferred:** M2–M4 specs. Profile property names frozen in ticket **01** ([BUILDPLAN](design/BUILDPLAN.md)).  
**Owned elsewhere:** AppearanceOnce → ticket **07**; splash spike measurements → [SPLASH](design/SPLASH.md) appendix (gate for **04**).

## Design Acceptance

Sign-off: [ROADMAP](ROADMAP.md#design-acceptance) (grill lock: ROADMAP table only).

## After hold lifts

Work only from [TICKETS](TICKETS.md). Do not expand M2–M4 until M1 green or rescope.
