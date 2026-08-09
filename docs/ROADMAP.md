# WinMint v2 — Roadmap

**Phase now:** **Alpha** — Design Acceptance signed · Implementation Released ([TICKETS](TICKETS.md)). Requirement tiers: [ADR-011](decisions/ADR-011-alpha-posture-and-package-delegation.md).  
**Authority:** [ARCHITECTURE](ARCHITECTURE.md), [Smoke](specs/2026-07-27-smoke.md), ADRs, [design/](design/), [DESIGN](DESIGN.md).

## Milestones

| ID | Milestone | Destination | Status |
|----|-----------|-------------|--------|
| **D0** | Design-plan complete | Designs + roadmap + gate signed | **Done** (2026-07-28) |
| **M0** | Repo scaffold | Reserved `src/` builds | Present |
| **M1** | Smoke Hyper-V green | Profile → ISO → FirstLogon evidence | **Done** — maintainer Smoke prove-out (**14**) green 2026-08-04 |
| **M2** | Wizard | Second BuildPlan host; presets → remove-lists; packages + caps UI | **Done** thin + packages (**15**, **22**) + polish (**25**, 2026-08-05); full UX polish still out |
| **M3** | Metal jobs / matrix expand | winget + reboot-resume + Scoop (**16–18**); caps **19–20**; WSL **23**; ExitWindowsEx **24** | **Done** (metal exit 2026-08-04; WSL/caps follow-on 2026-08-05) |
| **M4** | Hardware acceptance | Stricter evidence bars; same Supervisor/settle/jobs | Bars opt-in (**30**); full hardware campaign after M2/M3 — maintainer-timed |
| **M5** | Workstation compiler | WinPE apply + online debloat default (legacy Setup deleted in [#90](https://github.com/yanai-sh/winmint/issues/90)) | **Done** — Gates A–C ([#70](https://github.com/yanai-sh/winmint/issues/70)–[#72](https://github.com/yanai-sh/winmint/issues/72)); spec: [workstation-compiler](specs/2026-08-05-workstation-compiler-winpe-apply.md) |

## Design Acceptance

| Field | Value |
|-------|-------|
| Date | **2026-07-28** |
| Maintainer | Project owner (batch-grill shared understanding) |
| Splash prototype | Waived for gate; required before ticket **04** |
| Notes | Grill locks: [DESIGN](DESIGN.md#decisions-locked-grill). **Alpha:** defaults revisable per [ADR-011](decisions/ADR-011-alpha-posture-and-package-delegation.md). Post–keep-flag sequencing: [ADR-006](decisions/ADR-006-post-keepflag-sequencing.md) (**met**). CDM: [ADR-007](decisions/ADR-007-cdm-not-primary.md). |

## M1 order

Canonical closed index: **[TICKETS](TICKETS.md)**. Do not duplicate tables elsewhere.

## M1 exit criteria

Pro Smoke; Local+autoLogon; DMA on acceptance Profile; splash before Explorer; DMA hard evidence; `Test` lane; fail-open; reboot keeps Shell; pwsh-free guest; `%ProgramData%\WinMint\`; paint time recorded; **pinned acceptance remove-list proven** ([ADR-006](decisions/ADR-006-post-keepflag-sequencing.md) B4). **Prove-out:** maintainer `just smoke` on a real Source ISO (ticket **14**) — fixture S4 alone is not exit. **Met** 2026-08-04.

## M2–M4

Keep-flag AppX (**11–13**) + capabilities/features (**19–20**) done. Wizard + metal + deferred backlog **23–30** done. **Still locked out by policy** ([ADR-005](decisions/ADR-005-keep-flag-matrix.md) / [ADR-006](decisions/ADR-006-post-keepflag-sequencing.md) / [ADR-007](decisions/ADR-007-cdm-not-primary.md)): Profile presets-in-JSON; schema `v2` without a break; CDM-as-primary; leftover-confidence *product* cleanup. Product-default **`recommended`** host preset is in (issue **56**). Acceptance Profile carries a small frozen remove-list for prove-out. Hardware = stricter evidence bars (**30**); no Supervisor fork. No guest pwsh / settle forks / ISO Avalonia.
