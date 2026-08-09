# Design: ProvisioningSession module

**Status:** **Accepted** (Design-it-twice + batch-grill 2026-07-28)  
**Module:** ProvisioningSession · **Owner project:** `WinMint.Provisioning` (Native AOT Supervisor)  
**Entrypoints:** `--machine-setup` | Shell (default) — **one phase machine**  
**Authority:** [ARCHITECTURE](../ARCHITECTURE.md), [V1-LESSONS](V1-LESSONS.md), [TDD S3](../TDD.md), ADR-004, [DESIGN grill locks](../DESIGN.md#decisions-locked-grill)  
**Implements:** Smoke tickets 03–08

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
- No **guest pwsh product runtime**; no peer Splash.exe; no Shell↔RunOnce coupling. Inbox `powershell.exe` for Scoop bootstrap or winget import is OK ([ADR-011](../decisions/ADR-011-alpha-posture-and-package-delegation.md)).

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
    Action<ProvisioningBundle>? WipeSecrets = null,
    IEvidenceSink? Evidence = null,
    IAppxPackageManager? Appx = null,
    ISystemReboot? Reboot = null,
    ILocalAccounts? LocalAccounts = null,
    Func<string?>? ResolveScoopCmd = null);
```

Adapter interfaces are part of the **module interface** (callers/tests must know them) but stay thin. Production Win32 / WinRT adapters live in the same project; tests supply fakes.

**`IAppxPackageManager` (one env port — do not split Machine setup vs Shell):** keep-flag FirstLogon safety net (ticket **13**) **and** winget path seam. Method subsets: Machine setup calls `EnsureSystemFullControlOnWingetFrameworkPackages` (best-effort swallow — must not fail Machine setup); Shell safety-net uses find/remove/deprovision; Shell winget uses `RegisterPackageFamilyForCurrentUser` then `TryResolveWingetExecutablePath` (null ⇒ fail closed; no alias / `File.Exists` / PATH `"winget"` fallback). Winget jobs **require** `Appx`. Seven methods stay; slim = fold former public `WingetFrameworkPackageAcl` into `WinRTAppxPackageManager` (private takeown/icacls) — locked on [How slim should IAppxPackageManager be?](https://github.com/yanai-sh/winmint/issues/49). Path sealing: [Where do winget and Scoop paths resolve?](https://github.com/yanai-sh/winmint/issues/44).

Scoop discovery is **not** AppX: `ResolveScoopCmd` on the env bag (same Func/Action pattern as `WipeSecrets`); production wires shim `File.Exists` in `Program`; session never touches the filesystem for Scoop. Scoop jobs **require** the Func; null return → official bootstrap (below) → call the same Func again → still null ⇒ fail closed. `ISystemReboot` requests OS reboot after a `NeedsReboot` checkpoint (ticket **16**): `Win32SystemReboot` prefers `ExitWindowsEx` with `SeShutdownPrivilege`, falling back to `shutdown.exe /r /t 0 /f` (ticket **24**). Profile-driven `packages.wingetNeedsReboot` (ticket **17**) is a fail-closed subset of `packages.winget` that sets `needsReboot: true` on Plan winget jobs. Job kinds `winget` / `scoop` / `wsl` / optional `package.auditNative` spawn via `IProcessHost`, or Plan may emit **batch/delegated** package phases (`winget import`, batch `scoop install`, configure wrapper) — Supervisor still owns splash, checkpoints, evidence ([ADR-011](../decisions/ADR-011-alpha-posture-and-package-delegation.md)). WSL unchanged ([ADR-010](../decisions/ADR-010-arm64-package-policy.md)). Curated packages: **best-effort + evidence** by default; invariants (DMA, unlock) stay fail-closed. `ILocalAccounts` removes OOBE leftover `defaultuser0` during Machine setup (best-effort).

**Scoop bootstrap (why):** Official ScoopInstaller admin path — `iex "& {$(irm get.scoop.sh)} -RunAsAdmin"` via inbox **`powershell.exe`**. After bootstrap: add catalog-declared buckets (`scoop bucket add extras` when needed), then `scoop.cmd install …` or batch install. Network required; fail closed if bootstrap exits non-zero.

### Phase machine

**MachineSetup:** StampAutologon → VerifyOrRestampShell (fail-closed) → WipeSecrets → EnsureWingetFrameworkAcls (best-effort via AppX) → RemoveOobeTempUser (`defaultuser0`) → `Complete` | `Failed`  
(No splash, settle, or jobs.)

**Shell:**

```
Bootstrap (checkpoint | stale→fail-open)
  → FirstPaint (≤ FirstPaintBudget)
  → Settling (poll → final snapshot)
  → RunningJobs (hard settle green only)
  → Finishing
  → Unlock → Complete evidence → ResidueErase (branded payload; ADR-008)
       ↘ hard DMA / job fail / timeout → FailedDwell → Unlock → Failed (no residue erase)
       ↘ needsReboot → Checkpoint → Reboot (Shell kept; no residue erase)
```

### Invariants

1. Fail-open unlock on `Complete` / `Failed` / wall-clock timeout.
2. `Reboot` does **not** unlock; checkpoint + keep Supervisor as Shell.
3. DMA: intermediate probe failures are non-authoritative; **final snapshot** decides hard gates.
4. Jobs never start if hard settle fails.
5. Status is in-memory; evidence JSON is write-only projection (`winmint.provisioning.evidence/v1`).
6. Never stamp `defaultuser0` + AutoAdminLogon; Machine setup best-effort **deletes** leftover `defaultuser0` (+ profile) so the lock-screen picker is Profile-only.
7. Crash/stale tenure past `StaleTenureThreshold` ⇒ fail-open `Failed`.
8. Same settle + job executor on Smoke and metal; only `Jobs` list differs.
9. Winget executable path only via `IAppxPackageManager.TryResolveWingetExecutablePath` (AppX required). Scoop shim path only via `SessionEnvironment.ResolveScoopCmd` (Func required for scoop jobs). No in-session `File.Exists` for either.
10. **Residual minimization ([ADR-008](../decisions/ADR-008-residual-minimization.md)):** on Shell `Complete` only, best-effort clear AutoAdminLogon secrets and delete `%WINDIR%\WinMint\` + `SetupComplete.cmd`. Failed/Reboot skip erase. `%ProgramData%\WinMint\` may remain for harness harvest.

### Secrets (Smoke)

Smoke stages the Local+autoLogon password in plaintext under `C:\Windows\WinMint\bundle.json` (ImageServicing StagePayload). `Run(MachineSetup)` stamps Winlogon then redacts `password` in that file via `SessionEnvironment.WipeSecrets` (`Action<ProvisioningBundle>?` — ticket **28**; deepening [Delete FileSecretScrubber or keep the module?](https://github.com/yanai-sh/winmint/issues/47): **delete** the `FileSecretScrubber` class; wire wipe in `Program` as the Action). Guarantee is disk JSON redact (`Password=""`) + `WriteAllBytes` + no further use in the MachineSetup phase — not cryptographic process-memory scrub, not random overwrite of prior bytes. Assert wipe through `Run(MachineSetup)` against a temp `bundle.json`. Full DPAPI host→guest staging channel remains future if lab plaintext+wipe stays acceptable for Smoke.

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

**Hidden:** registry key paths, D2D/GDI details, DMA poll loop, job argv construction (not which exe — that is behind AppX / `ResolveScoopCmd`), checkpoint file layout, heartbeat, evidence projection formatting, production Scoop shim `File.Exists` wiring in `Program`, WinRT-private winget framework ACL grant (former `WingetFrameworkPackageAcl`).

## S3 test strategy (locked)

| Ticket | Assert via `Run` + fakes |
|--------|---------------------------|
| 03 | Autologon keys; reject defaultuser0; Shell verify fail/success |
| 04 | Splash `Show` before settle; status updates; evidence projection shape |
| 05 | Scripted region reads → final hard fail skips jobs; soft location warns + continues |
| 06 | Stub jobs via child-process fakes; jobs skipped after hard settle fail |
| metal jobs | Winget: AppX fake canned path → `IProcessHost` recording asserts `fileName`; resolve null → fail, host not started. Scoop: Func null→path after bootstrap script → recording sees powershell then `scoop.cmd`. No leaf tests of private path helpers. |
| 07 | Timeout via `FakeTimeProvider`; stale fail-open; unlock on Failed |
| 08 | Reboot keeps Shell + checkpoint; resume continues tenure |

**No Hyper-V required for S3.** Hyper-V is S4 only.

**Assembly shape (design decision):** keep logic in `WinMint.Provisioning` with public adapter interfaces so `WinMint.Tests` references the project and runs phase tests on the non-AOT TFM build. Extract `WinMint.Provisioning.Core` **only** if AOT/test friction forces it (ponytail).

**JobRunner (internal):** package/job execution lives in nested `JobRunner` (`ProvisioningSession.JobRunner.cs`); public seam stays `Run`. `JobRunner.Execute` uses a local `FailJob(code, message)` helper (SetStatus + phases + Failed). Settle still hand-rolls; extract further only if another edit pass touches those branches.

## Smoke defaults (grill-locked)

| Policy field | Smoke default |
|--------------|---------------|
| `WallClockTimeout` | **90 min** (measured with **monotonic** `TimeProvider.GetTimestamp` / `GetElapsedTime` — survives Hyper-V IC/NTP UTC jumps; wall clock remains OK for evidence / heartbeat UTC) |
| `FailedDwell` | **5 s** |
| `SettleDeadline` | **120 s** (same monotonic clock as tenure) |
| `SettlePollInterval` | implementation choice inside deadline |
| `FirstPaintBudget` | **2.0 s** (S3 = order; S4 = measure) |
| `StaleTenureThreshold` | **15 min** (wall-clock vs persisted heartbeat UTC — must survive process restart) |
| `InputLock` | `None` |

**Durable paths (guest):** `%ProgramData%\WinMint\` — `checkpoint.json`, heartbeat file, `evidence\` (optional diagnostics; harness may wipe after harvest). Staged `C:\Windows\WinMint\` + `SetupComplete.cmd` are **tenure-only** — erased after successful Shell Complete ([ADR-008](../decisions/ADR-008-residual-minimization.md)).

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
| 06 | Stub jobs + child-process executor |
| 07 | Unlock + timeout + stale fail-open |
| 08 | Checkpoint reboot keeps Shell |
| 13 | AppX safety-net job |
| 16 | Metal `winget` job + OS reboot request |
| 23 | Metal `wsl` job |
| 24 | ExitWindowsEx reboot fallback |
| 28 | Best-effort bundle secret overwrite |
| 29 | GDI splash status text |

## Explicitly rejected

MediatR; peer Splash.exe; guest pwsh; file status/control as control plane; RunOnce/PreLock; Hyper-V-only executor; public phase plugin API.
