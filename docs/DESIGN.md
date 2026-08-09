# WinMint v2 — Design plan (canonical)

**Phase:** **Alpha** (backlog **01–30** closed) — next is maintainer pick / new issue ([TICKETS](TICKETS.md)) · [ROADMAP](ROADMAP.md#design-acceptance).  
**Product:** Windows 11 ISO builder. Host ARM64-first. Guest = **Provisioning Supervisor** (C# phase machine). Requirement tiers: [ADR-011](decisions/ADR-011-alpha-posture-and-package-delegation.md).

## Read order

1. [CONTEXT](../CONTEXT.md) · [V1-LESSONS](design/V1-LESSONS.md)  
2. [ARCHITECTURE](ARCHITECTURE.md)  
3. This file + [design/](design/)  
4. [TICKETS](TICKETS.md) (closed index + policy-out) · [ROADMAP](ROADMAP.md)  
5. [Smoke](specs/2026-07-27-smoke.md) · [Workstation compiler](specs/2026-08-05-workstation-compiler-winpe-apply.md) · [TDD](TDD.md) · [AGENTIC](agents/AGENTIC.md)

## Modules (accepted)

| Module | Doc |
|--------|-----|
| BuildPlan | [BUILDPLAN](design/BUILDPLAN.md) |
| ImageServicing | [IMAGESERVICING](design/IMAGESERVICING.md) |
| ProvisioningSession | [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) |

## Cross-cutting (accepted)

[CONTRACTS](design/CONTRACTS.md) · [SECRETS](design/SECRETS.md) · [SPLASH](design/SPLASH.md) · [V1-LESSONS](design/V1-LESSONS.md) · [KEEPFLAG](design/KEEPFLAG.md) (post-M1; design accepted)

## ADRs

[001](decisions/ADR-001-source-iso-legal.md) · [002](decisions/ADR-002-v2-architecture.md) · [003](decisions/ADR-003-dma-interop.md) · [004](decisions/ADR-004-stack-and-guest-control-plane.md) · [005](decisions/ADR-005-keep-flag-matrix.md) · [006](decisions/ADR-006-post-keepflag-sequencing.md) · [007](decisions/ADR-007-cdm-not-primary.md) · [008](decisions/ADR-008-residual-minimization.md) · [009](decisions/ADR-009-product-constant-policies.md) · [010](decisions/ADR-010-arm64-package-policy.md) · [011](decisions/ADR-011-alpha-posture-and-package-delegation.md)

## Alpha posture

Grill locks below are **not all immutable**. [ADR-011](decisions/ADR-011-alpha-posture-and-package-delegation.md) splits **Invariant** (identity/safety), **Default** (current behaviour, change with spike), and **Guideline**. Agents should not treat ticket-sequence wording as a blocker when a net-positive alternative fits alpha.

## Grill index (tiered)

Batch-grill rounds 1–4; shared understanding 2026-07-28. Post–keep-flag grill 2026-08-04 ([ADR-006](decisions/ADR-006-post-keepflag-sequencing.md)); CDM 2026-08-05 ([ADR-007](decisions/ADR-007-cdm-not-primary.md)); residual ([ADR-008](decisions/ADR-008-residual-minimization.md)); product policies ([ADR-009](decisions/ADR-009-product-constant-policies.md)); package catalog ([ADR-010](decisions/ADR-010-arm64-package-policy.md)); **alpha tiers** 2026-08-06 ([ADR-011](decisions/ADR-011-alpha-posture-and-package-delegation.md)). Tier column: **I** = invariant, **D** = default (revisable), **G** = guideline.

| Topic | Tier | Lock |
|-------|------|------|
| Gate scope | G | Smoke M1 design; M2–M4 stubs at gate — **M1–M3 product path largely shipped** (see [ROADMAP](ROADMAP.md), [TICKETS](TICKETS.md)) |
| Modules | I | As written in design/* |
| Cross-cutting | I | CONTRACTS + SECRETS + SPLASH required |
| Sign-off | G | ROADMAP table only |
| Splash spike | G | Waived for gate; **required before ticket 04**; may run during hold (throwaway) |
| First paint | D | ≤ 2.0 s target; S3 order; S4 measure |
| Secrets | D | Lab honesty; fixtures inline OK; prefer path/env in Cli |
| Scaffold | G | Keep `src/` + `just check` |
| Profile fields | I | Freeze at ticket **01** (+ later optional v1 fields without schema bump) |
| SessionPolicy | D | Smoke defaults per [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md#smoke-defaults-grill-locked) |
| Guest paths | I | `%ProgramData%\WinMint\` (logs/evidence); `C:\Windows\WinMint\` + SetupComplete tenure-only — erased after Shell Complete ([ADR-008](decisions/ADR-008-residual-minimization.md)) |
| WIM metadata | I | Snapshot + assert Name/Arch/(Edition\|Build) across export/commit/max export ([IMAGESERVICING](design/IMAGESERVICING.md#invariants) §10) |
| Residual | I | Not a distro — self-erase branded payload on green; no dual `$OEM$` SetupScripts; CDM spray not product default ([ADR-008](decisions/ADR-008-residual-minimization.md), [ADR-007](decisions/ADR-007-cdm-not-primary.md)) |
| MachineSetup fail | I | Non-zero exit; fail closed |
| S4 harness | G | Thin pwsh `tools/vm/` |
| Issues | G | File when work is specified; apply `ready-for-agent` only when starting |
| Lanes | D | `Test` \| `Release` |
| Stale | D | Heartbeat + checkpoint ⇒ fail-open |
| Smoke accounts | D | Local+autoLogon only |
| Soft location | D | Location-services on/off; warn, continue |
| Cli | D | 01 `validate`/`plan`; 02 `build` |
| DMA off | D | Schema OK; acceptance Profile = on |
| Hyper-V Smoke | G | Pro only |
| WIM commit | I | Single-image only — Mount exports edition; Export fail-closes if multi-index ([IMAGESERVICING](design/IMAGESERVICING.md#invariants) §7) |
| Post-13 sequencing | G | **Met** — M1 Smoke (**14**) before Wizard / keep-flag expand / metal ([ADR-006](decisions/ADR-006-post-keepflag-sequencing.md)); tickets **14–30** done |
| Post-13 tickets | G | Thin cards **14+**; no mega-epic; carry folds into owning card |
| Keep-flag polarity | I | Remove-list only; **no** Profile preset names; product **`recommended`** host preset is the zero-config default (expands → ids); Acceptance remain prove-out-only ([ADR-005](decisions/ADR-005-keep-flag-matrix.md), issue **56**) |
| Keep-flag kinds | I | AppX **11–13**; capabilities/features **19–20** (same polarity) |
| CDM | I | Not primary keep-flag control ([ADR-007](decisions/ADR-007-cdm-not-primary.md)) |
| Product policies | I | Always EdgeDebloat + OneDrive + DeviceMetadata + WPBT + ReservedStorage; Copilot-kill iff `!keepCopilot`; BraveDebloat iff Brave selected ([ADR-009](decisions/ADR-009-product-constant-policies.md)) |
| Acceptance remove-list | D | Smoke **acceptance** Profile pins a **small frozen** list (AppX + thin caps/features); schema default elsewhere empty |
| Schema | I | Stay on `winmint.profile/v1` until a breaking change forces `v2` |
| Metal jobs | D | `winget` / Scoop / WSL shipped (**16–18**, **23**); may batch/delegate per [ADR-011](decisions/ADR-011-alpha-posture-and-package-delegation.md); unknown kinds fail closed until ticketed |
| Package fail posture | D | Invariants fail-closed; curated packages **best-effort + evidence** by default ([ADR-011](decisions/ADR-011-alpha-posture-and-package-delegation.md)) |
| OS reboot | D | `ISystemReboot` (**24**); Profile `*NeedsReboot` subsets |
| Appearance | D | No AppearanceOnce / theme apply until grilled |
| Secrets hardening | D | Smoke plaintext + wipe (**28**); metal: `passwordPath` / Wizard prompt — **no** PasswordEnvVar (issue **56**) |
| Splash D2D | D | GDI status text (**29**); full D2D only if S4 budget fails |
| S4 VHD/digest rebuild | G | Maintainer optimization |
| `*Dto` rename | G | Opportunistic |
| Wizard | D | BuildPlan host (**15** + packages **22**); Phase B Review → Apply |
| Hardware | D | M4 stricter evidence bars (**30** opt-in); no Supervisor fork |
| Install engine | D | **WinPE apply** only (`diskpart` + DISM apply + `bcdboot` + Panther OOBE unattend); legacy Setup `/legacy` deleted ([#90](https://github.com/yanai-sh/winmint/issues/90)) |
| Debloat venue | D | AppX **online** default (`debloat.mode` absent); offline DISM + caps/features always offline when listed |

**Workstation-compiler vertical (2026-08):** Gates A–C in [spec](specs/2026-08-05-workstation-compiler-winpe-apply.md). Pre-vertical ADRs remain guidance where superseded (install engine, offline-primary debloat); see spec + [ADR-011](decisions/ADR-011-alpha-posture-and-package-delegation.md) default tier.

**Still out (policy):** Profile presets-in-JSON; schema `v2` without a break; full DPAPI host→guest; full D2D; leftover-confidence *product* cleanup; Wizard edition probe / rich per-stage DISM progress.  
**Shipped:** AppX + capabilities keep-flag; product-default **`recommended`** host expansion (issue **56**); KeepGaming / KeepCopilot overlays; Wizard thin + packages + caps/WSL lists + host-DMA fill; metal winget/Scoop/WSL; Israel DMA sample; SL7 sample; M4 assert switch; WIM metadata discipline; residual self-erase ([ADR-008](decisions/ADR-008-residual-minimization.md)); product-constant offline policies + OneDrive/ReservedStorage jobs ([ADR-009](decisions/ADR-009-product-constant-policies.md)). Profile property names frozen in ticket **01**; optional `debloat.*` / `packages.*` / `account.requireWifiDuringOobe` / `account.passwordPath` / `policies.*` on v1.  
**Unlocked:** Phase A multi-step Avalonia Wizard shell; Phase B live elevated build invoke (busy/cancel) via shared ImageServicing path.

**Owned elsewhere:** Splash spike → [SPLASH](design/SPLASH.md) appendix. Appearance consume path was ticket **07**; removed 2026-08-05 until Profile appearance is grilled.

## Design Acceptance

Sign-off: [ROADMAP](ROADMAP.md#design-acceptance) (grill lock: ROADMAP table only).

## After backlog close

Next work is maintainer pick or a new issue (grill → to-spec) — not “start at **01**.” Sequencing gate in [ADR-006](decisions/ADR-006-post-keepflag-sequencing.md) is **met**; **invariants** in the grill table still bind; **defaults** revisable per [ADR-011](decisions/ADR-011-alpha-posture-and-package-delegation.md).