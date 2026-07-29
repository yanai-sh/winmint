# WinMint v2 — Roadmap

**Phase now:** Design Acceptance **signed** · Implementation **Released** ([TICKETS](TICKETS.md)).  
**Authority:** [ARCHITECTURE](ARCHITECTURE.md), [Smoke](specs/2026-07-27-smoke.md), ADRs, [design/](design/), [DESIGN](DESIGN.md).

## Milestones

| ID | Milestone | Destination | Status |
|----|-----------|-------------|--------|
| **D0** | Design-plan complete | Designs + roadmap + gate signed | **Done** (2026-07-28) |
| **M0** | Repo scaffold | Reserved `src/` builds | Present |
| **M1** | Smoke Hyper-V green | Profile → ISO → FirstLogon evidence | **In progress** (hold released 2026-07-29) |
| **M2–M4** | Wizard / matrix / hardware | — | Stubs |

## Design Acceptance

| Field | Value |
|-------|-------|
| Date | **2026-07-28** |
| Maintainer | Project owner (batch-grill shared understanding) |
| Splash prototype | Waived for gate; required before ticket **04** |
| Notes | Grill locks: [DESIGN](DESIGN.md#decisions-locked-grill). Quality pass: canonical backlog [TICKETS](TICKETS.md). |

## M1 order

Canonical ticket cards + DoD: **[TICKETS](TICKETS.md)**. Do not duplicate tables elsewhere.

## M1 exit criteria

Pro Smoke; Local+autoLogon; DMA on acceptance Profile; splash before Explorer; DMA hard evidence; `Test` lane; fail-open; reboot keeps Shell; pwsh-free guest; `%ProgramData%\WinMint\`; paint time recorded.

## M2–M4 stubs

Wizard = second BuildPlan host. Matrix = Profile/job data. Hardware = stricter evidence bars. No guest pwsh / settle forks / ISO Avalonia.
