# Design: ProvisioningSession module

**Status:** **Accepted** (Design-it-twice + batch-grill 2026-07-28)  
**Module:** ProvisioningSession · **Owner project:** `WinMint.Provisioning` (Native AOT Supervisor)  
**Entrypoints:** `--machine-setup` | Shell (default) — **one phase machine**  
**Authority:** [ARCHITECTURE](../ARCHITECTURE.md), [V1-LESSONS](V1-LESSONS.md), [TDD S3](../TDD.md), ADR-004, [DESIGN grill locks](../DESIGN.md#decisions-locked-grill)  
**Implements:** Smoke tickets 03–06

## Problem space

This is the module that motivated greenfield. It must replace v1’s multi-pwsh + peer Splash + JSON mailbox graph with **one process** that Winlogon can run as Shell, while remaining **testable without Hyper-V** for phase rules.

Constraints any interface must satisfy:

- Single AOT binary: Machine setup + Shell tenure.
- In-process splash; in-memory status; JSON = evidence projections only.
- DMA settle by **final snapshot**; hard locale/GeoID/TZ; soft location.
- Fail-open unlock on complete/failed/timeout; hold Shell on reboot + checkpoint.
- Never leave `defaultuser0` + AutoAdminLogon after Machine setup.
- Time-to-first-paint budget; crash/stale tenure → fail-open.
- Secret wipe after Machine setup stamp.
- No guest pwsh; no peer Splash.exe; no Shell↔RunOnce coupling.

Dependency category: **local-substitutable** OS (registry, locale snapshot, process spawn, splash presenter, clock) + true-external child processes (winget/etc.) behind the job runner.

## Designs considered (summary)

Design-it-twice: one `Run` + env bag vs flexible bundle/policy vs ports-first. **Locked:** one `Run(mode, bundle, env)` + public thin adapters for S3; data-driven jobs/policy; paint-before-settle; ProgramData durable state. See [DESIGN grill](../DESIGN.md#decisions-locked-grill).

## Locked interface sketch

```csharp
namespace WinMint.Provisioning;

public static class ProvisioningSession
{
    public static SessionResult Run(
        SessionMode mode,
        ProvisioningBundle bundle,
        SessionEnvironment env,
        CancellationToken ct = default);
}

public enum SessionMode { MachineSetup, Shell }

public enum SessionOutcome { Complete, Failed, Reboot }

public sealed record SessionResult(
    SessionOutcome Outcome,
    SessionStatus FinalStatus,
    IReadOnlyList<EvidenceSnapshot> EvidenceEmitted);

public sealed record ProvisioningBundle(
    AccountStamp Account,
    DmaSettleTarget Dma,
    IReadOnlyList<ProvisionJob> Jobs,
    SessionPolicy Policy,
    SupervisorIdentity Supervisor,
    AppearanceOnce? Appearance = null,
    CheckpointState? Resume = null);

public sealed record SessionPolicy(
    TimeSpan WallClockTimeout,
    TimeSpan SettleDeadline,
    TimeSpan SettlePollInterval,
    TimeSpan FailedDwell,
    TimeSpan FirstPaintBudget,
    TimeSpan StaleTenureThreshold,
    InputLockMode InputLock = InputLockMode.None);

public enum InputLockMode { None, Soft, Hard }

public sealed record SessionEnvironment(
    TimeProvider Time,
    IWinlogonRegistry Winlogon,
    IRegionSnapshot Region,
    IProcessHost Processes,
    ISplashPresenter Splash,
    ICheckpointStore Checkpoints,
    ISecretScrubber Secrets,
    IEvidenceSink? Evidence = null);
```

Adapter interfaces are part of the **module interface** (callers/tests must know them) but stay thin. Production Win32 adapters live in the same project; tests supply fakes.

### Phase machine

**MachineSetup:** StampAutologon → VerifyOrRestampShell (fail-closed) → WipeSecrets → `Complete` | `Failed`  
(No splash, settle, or jobs.)

**Shell:**

```
Bootstrap (checkpoint | stale→fail-open)
  → FirstPaint (≤ FirstPaintBudget)
  → Settling (poll → final snapshot)
  → RunningJobs (hard settle green only)
  → Finishing (appearance once)
  → Unlock → Complete
       ↘ hard DMA / job fail / timeout → FailedDwell → Unlock → Failed
       ↘ needsReboot → Checkpoint → Reboot (Shell kept)
```

### Invariants

1. Fail-open unlock on `Complete` / `Failed` / wall-clock timeout.
2. `Reboot` does **not** unlock; checkpoint + keep Supervisor as Shell.
3. DMA: intermediate probe failures are non-authoritative; **final snapshot** decides hard gates.
4. Jobs never start if hard settle fails.
5. Status is in-memory; evidence JSON is write-only projection (`winmint.provisioning.evidence/v1`).
6. Never stamp `defaultuser0` + AutoAdminLogon.
7. Crash/stale tenure past `StaleTenureThreshold` ⇒ fail-open `Failed`.
8. Same settle + job executor on Smoke and metal; only `Jobs` list differs.

### Error modes

| Condition | Outcome | Unlock? |
|-----------|---------|---------|
| MachineSetup Shell verify fails | `Failed` | N/A (pre-interactive) |
| DMA hard mismatch (final) | `Failed` | Yes (+ dwell) |
| Job failure | `Failed` | Yes (+ dwell) |
| Timeout / cancel | `Failed` | Yes |
| Stale/crash bootstrap | `Failed` | Yes |
| Job needs reboot | `Reboot` | **No** |
| Success | `Complete` | Yes |

Expected failures return `SessionResult`; exceptions = bugs.

## What stays outside / hidden

**Outside:** `Program.cs` arg parse; staged JSON → `ProvisioningBundle` loader; SetupComplete.cmd; Winlogon launching the exe.

**Hidden:** registry key paths, D2D/GDI details, DMA poll loop, job argv, checkpoint file layout, heartbeat, evidence projection formatting, appearance apply.

## S3 test strategy (locked)

| Ticket | Assert via `Run` + fakes |
|--------|---------------------------|
| 03 | Autologon keys; reject defaultuser0; Shell verify fail/success |
| 04 | Splash `Show` before settle; status updates; evidence projection shape |
| 05 | Scripted region reads → final hard fail skips jobs; soft location warns + continues |
| 06 | Stub jobs; timeout via `FakeTimeProvider`; reboot keeps Shell + checkpoint; unlock on Failed |

**No Hyper-V required for S3.** Hyper-V is S4 only.

**Assembly shape (design decision):** keep logic in `WinMint.Provisioning` with public adapter interfaces so `WinMint.Tests` references the project and runs phase tests on the non-AOT TFM build. Extract `WinMint.Provisioning.Core` **only** if AOT/test friction forces it (ponytail).

## Smoke defaults (grill-locked)

| Policy field | Smoke default |
|--------------|---------------|
| `WallClockTimeout` | **90 min** |
| `FailedDwell` | **5 s** |
| `SettleDeadline` | **120 s** |
| `SettlePollInterval` | implementation choice inside deadline |
| `FirstPaintBudget` | **2.0 s** (S3 = order; S4 = measure) |
| `StaleTenureThreshold` | **15 min** |
| `InputLock` | `None` |

**Durable paths (guest):** `%ProgramData%\WinMint\` — `checkpoint.json`, heartbeat file, `evidence\`.

**MachineSetup failure:** Supervisor exits non-zero; SetupComplete must not treat stamps as success; leave diagnosable logs under ProgramData.

**Soft location:** compare location-services enabled posture to Profile; warn + continue (not a hard gate).

**Stale recovery:** on Shell start, in-progress checkpoint + missing/stale heartbeat older than `StaleTenureThreshold` ⇒ fail-open unlock + `Failed`.

## Time-to-first-paint

`SessionPolicy.FirstPaintBudget` default **≤ 2.0 s** (see [SPLASH.md](SPLASH.md)). Tests with `RecordingSplashPresenter` + `FakeTimeProvider` assert **order** (paint before settle), not wall-clock OS latency. S4 measures real latency. Splash VM spike **required before ticket 04** is `ready-for-agent` (waived only for Design Acceptance).


## Ticket mapping

| Ticket | Deepens |
|--------|---------|
| 03 | MachineSetup + `IWinlogonRegistry` |
| 04 | Splash + status + evidence |
| 05 | Settling + final snapshot |
| 06 | Jobs + unlock/timeout + checkpoint/reboot + stale path |

## Explicitly rejected

MediatR; peer Splash.exe; guest pwsh; file status/control as control plane; RunOnce/PreLock; Hyper-V-only executor; public phase plugin API.
