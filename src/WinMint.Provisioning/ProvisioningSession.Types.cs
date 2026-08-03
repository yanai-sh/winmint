namespace WinMint.Provisioning;

public enum SessionMode
{
    MachineSetup,
    Shell,
}

public enum SessionOutcome
{
    Complete,
    Failed,
    Reboot,
}

public sealed record SessionResult(
    SessionOutcome Outcome,
    SessionStatus FinalStatus,
    IReadOnlyList<EvidenceSnapshot> EvidenceEmitted);

public sealed record SessionStatus(string Code, string Message);

public sealed record EvidenceSnapshot(string SchemaVersion, string Path);

public sealed record ProvisioningBundle(
    AccountStamp Account,
    DmaSettleTarget Dma,
    IReadOnlyList<ProvisionJob> Jobs,
    SessionPolicy Policy,
    SupervisorIdentity Supervisor,
    AppearanceOnce? Appearance = null,
    CheckpointState? Resume = null);

public sealed record AccountStamp(string Username, string Password);

public sealed record DmaSettleTarget(
    bool Enabled,
    string? Locale,
    int? GeoId,
    string? TimeZoneId,
    bool? LocationServicesEnabled);

public sealed record ProvisionJob(string Id, string Kind);

public sealed record SupervisorIdentity(string ShellPath);

public sealed record AppearanceOnce(string? Theme);

public sealed record CheckpointState(string Phase);

public sealed record SessionPolicy(
    TimeSpan WallClockTimeout,
    TimeSpan SettleDeadline,
    TimeSpan SettlePollInterval,
    TimeSpan FailedDwell,
    TimeSpan FirstPaintBudget,
    TimeSpan StaleTenureThreshold,
    InputLockMode InputLock = InputLockMode.None)
{
    public static SessionPolicy SmokeDefaults { get; } = new(
        WallClockTimeout: TimeSpan.FromMinutes(90),
        SettleDeadline: TimeSpan.FromSeconds(120),
        SettlePollInterval: TimeSpan.FromSeconds(2),
        FailedDwell: TimeSpan.FromSeconds(5),
        FirstPaintBudget: TimeSpan.FromSeconds(2),
        StaleTenureThreshold: TimeSpan.FromMinutes(15),
        InputLock: InputLockMode.None);
}

public enum InputLockMode
{
    None,
    Soft,
    Hard,
}

public sealed record SessionEnvironment(
    TimeProvider Time,
    IWinlogonRegistry Winlogon,
    IRegionSnapshot Region,
    IProcessHost Processes,
    ISplashPresenter Splash,
    ICheckpointStore Checkpoints,
    ISecretScrubber Secrets,
    IEvidenceSink? Evidence = null);

public interface IWinlogonRegistry
{
    void SetAutoLogon(string username, string password);

    string? GetDefaultUserName();

    bool GetAutoAdminLogon();

    string? GetShell();

    void SetShell(string path);
}

public interface IRegionSnapshot
{
    // Ticket 05
}

public interface IProcessHost
{
    // Ticket 06
}

public interface ISplashPresenter
{
    // Ticket 04
}

public interface ICheckpointStore
{
    // Ticket 08
}

public interface ISecretScrubber
{
    void Wipe(ProvisioningBundle bundle);
}

public interface IEvidenceSink
{
    // Ticket 04
}
