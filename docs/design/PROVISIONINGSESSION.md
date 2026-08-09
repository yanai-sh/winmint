# Design: ProvisioningSession module

**Module:** ProvisioningSession · **Owner:** `WinMint.Provisioning` (Native AOT Supervisor)  
**Entrypoints:** `--machine-setup` | Shell — **one phase machine**  
**Authority:** [ARCHITECTURE](../ARCHITECTURE.md) · [V1-LESSONS](V1-LESSONS.md) · [TDD](../TDD.md) · [DESIGN](../DESIGN.md)

## Role

One AOT process for Machine setup + Shell tenure. In-process splash; in-memory status; JSON = evidence only. DMA settle by **final snapshot**. Fail-open unlock; reboot keeps Shell + checkpoint. No guest **pwsh product runtime**; no peer Splash.exe. Inbox `powershell.exe` for Scoop bootstrap / narrow import OK.

## Interface

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

Thin adapters are part of the module interface; production Win32/WinRT live in-project; tests supply fakes. Winget path via `IAppxPackageManager`; Scoop via `ResolveScoopCmd`. Jobs may be per-id or batch/delegated; Supervisor owns splash/checkpoints/evidence. Curated packages: best-effort + evidence by default.

## Phase machine

**MachineSetup:** StampAutologon → VerifyOrRestampShell (fail-closed) → WipeSecrets → EnsureWingetFrameworkAcls (best-effort) → RemoveOobeTempUser → `Complete` | `Failed`  
(No splash, settle, or jobs.)

**Shell:** Bootstrap (checkpoint | stale→fail-open) → FirstPaint → Settling (final snapshot) → RunningJobs (hard settle green only) → Unlock → Complete + ResidueErase  
↘ hard DMA / job fail / timeout → FailedDwell → Unlock → Failed  
↘ needsReboot → Checkpoint → Reboot (Shell kept)

## Invariants

1. Fail-open unlock on Complete / Failed / wall-clock timeout.
2. Reboot does **not** unlock; checkpoint + keep Supervisor as Shell.
3. DMA: final snapshot authoritative for hard gates (locale / GeoID / TZ); soft location warn/continue.
4. Jobs never start if hard settle fails.
5. Status in-memory; evidence JSON write-only projection.
6. Never stamp `defaultuser0` + AutoAdminLogon; Machine setup best-effort deletes leftover `defaultuser0`.
7. Stale tenure past threshold ⇒ fail-open Failed.
8. Same settle + job executor on Smoke and metal; only Jobs list differs.
9. Residual erase on Shell Complete only (`%WINDIR%\WinMint\` + SetupComplete); ProgramData may remain for harness.

## Smoke defaults

| Field | Default |
|-------|---------|
| WallClockTimeout | 90 min (monotonic for tenure) |
| FailedDwell | 5 s |
| SettleDeadline | 120 s |
| FirstPaintBudget | 2.0 s (S3 = order; S4 = measure) |
| StaleTenureThreshold | 15 min |
| InputLock | None |

Durable: `%ProgramData%\WinMint\`. MachineSetup failure ⇒ non-zero exit.

## Outside / rejected

Outside: `Program.cs` arg parse, bundle JSON loader, SetupComplete.cmd, Winlogon launch.  
Rejected: MediatR; peer Splash; guest pwsh product runtime; file mailbox control plane; RunOnce/PreLock; Hyper-V-only executor; public phase plugin API.
