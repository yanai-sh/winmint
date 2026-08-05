# Wizard UX Phase B — design lock

**Date:** 2026-08-05  
**Status:** Locked (grill) · implement in-repo

## Locks

| Topic | Decision |
|-------|----------|
| Invoke | `ImageServicing.Apply` from Wizard (same as Cli) — not `Process.Start(Cli)` |
| Elevation | Wizard unelevated; `PwshElevatedPlanRunner` UAC `runas` |
| Gate | Build enabled only after Save + existing Source ISO |
| Work | Default `%ProgramData%\WinMint\work`; out ISO `<work>\out.iso` |
| Progress | Busy “Building…”, Cancel via `CancellationToken`; no fake stage list |
| Out | Edition probe, WebView2, live winget search, rich per-stage progress |

## Product role

Wizard authors Profile + RunOptions and invokes the shared plan/build path — not a second planner, not in-process DISM.

## Gate

`just check` (unit tests cover `WizardBuild.TryApply` fail-closed + fake runner; no real DISM).

**Manual (maintainer):** Save Profile → Build → approve UAC → success/fail message + output ISO path (or preserved work dir on failure).
