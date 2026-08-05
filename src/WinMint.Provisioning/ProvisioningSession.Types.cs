using System.Text.Json.Serialization;

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
    CheckpointState? Resume = null,
    IReadOnlyList<string>? RemoveProvisionedAppx = null);

public sealed record AccountStamp(string Username, string Password);

public sealed record DmaSettleTarget(
    bool Enabled,
    string? Locale,
    int? GeoId,
    string? TimeZoneId,
    bool? LocationServicesEnabled);

public sealed record ProvisionJob(
    string Id,
    string Kind,
    bool NeedsReboot = false,
    string? PackageId = null);

public sealed record SupervisorIdentity(string ShellPath);

public sealed record CheckpointState(string Phase);

public sealed record SessionPolicy(
    // Name is historical: tenure/settle budgets use monotonic TimeProvider timestamps (not DateTime UTC).
    TimeSpan WallClockTimeout,
    TimeSpan SettleDeadline,
    TimeSpan SettlePollInterval,
    TimeSpan FailedDwell,
    TimeSpan StaleTenureThreshold)
{
    public static SessionPolicy SmokeDefaults { get; } = new(
        WallClockTimeout: TimeSpan.FromMinutes(90),
        SettleDeadline: TimeSpan.FromSeconds(120),
        SettlePollInterval: TimeSpan.FromSeconds(2),
        FailedDwell: TimeSpan.FromSeconds(5),
        StaleTenureThreshold: TimeSpan.FromMinutes(15));
}

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

/// <summary>OS reboot after NeedsReboot checkpoint (ticket 16). Nullable in tests; production wires Win32.</summary>
public interface ISystemReboot
{
    void RequestReboot();
}

/// <summary>
/// SetupComplete/SYSTEM: remove leftover OOBE temp accounts (defaultuser0). Best-effort; must not throw.
/// </summary>
public interface ILocalAccounts
{
    void TryDeleteLocalUserAndProfile(string username);
}

public sealed record AppxPackageInfo(
    string PackageFullName,
    string PackageFamilyName,
    string? DisplayName);

/// <summary>FirstLogon AppX safety net (ticket 13) — fake in S3; WinRT adapter in production.</summary>
public interface IAppxPackageManager
{
    IReadOnlyList<AppxPackageInfo> FindRegisteredByCatalogId(string catalogId);

    IReadOnlyList<AppxPackageInfo> FindProvisionedByCatalogId(string catalogId);

    void RemovePackage(string packageFullName);

    void DeprovisionPackageFamily(string packageFamilyName);

    /// <summary>
    /// Register a provisioned package family for the current user (winget / App Installer FirstLogon).
    /// </summary>
    void RegisterPackageFamilyForCurrentUser(string packageFamilyName);

    /// <summary>
    /// SetupComplete/SYSTEM: grant LocalSystem FullControl on staged App Installer framework
    /// packages. Inbox ACLs often leave SYSTEM RX-only; AppXDeploymentServer then fails Trust Label
    /// registration (error surfaces as logo.png access denied for S-1-5-18).
    /// </summary>
    void EnsureSystemFullControlOnWingetFrameworkPackages();

    /// <summary>
    /// Resolve <c>winget.exe</c> under the current user's registered DesktopAppInstaller package.
    /// </summary>
    string? TryResolveWingetExecutablePath();
}

public interface IWinlogonRegistry
{
    void SetAutoLogon(string username, string password);

    string? GetDefaultUserName();

    bool GetAutoAdminLogon();

    string? GetShell();

    void SetShell(string path);

    void GrantShellUnlockAccess(string username);
}

public sealed record RegionState(
    string? Locale,
    int? GeoId,
    string? TimeZoneId,
    bool? LocationServicesEnabled);

public interface IRegionSnapshot
{
    void Apply(DmaSettleTarget target);

    RegionState Read();
}

public sealed record ProcessStartResult(int ExitCode);

public interface IProcessHost
{
    ProcessStartResult Run(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken ct = default);
}

public interface ISplashPresenter
{
    void Show();

    void SetStatus(SessionStatus status);
}

/// <summary>
/// Durable tenure under %ProgramData%\WinMint\.
/// Heartbeat + checkpoint write/clear for reboot resume.
/// </summary>
public sealed record TenureState(bool CheckpointInProgress, DateTimeOffset? HeartbeatUtc);

public interface ICheckpointStore
{
    TenureState ReadTenure();

    void WriteHeartbeat(DateTimeOffset utcNow);

    void WriteCheckpoint(CheckpointState state);

    CheckpointState? TryReadCheckpoint();

    void ClearCheckpoint();
}

public interface IEvidenceSink
{
    EvidenceSnapshot Write(ProvisioningEvidenceDocument document);
}

/// <summary>Write-only projection for S4 harness — never read by the session phase machine.</summary>
public sealed record ProvisioningEvidenceDocument(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("outcome")] string Outcome,
    [property: JsonPropertyName("statusCode")] string StatusCode,
    [property: JsonPropertyName("statusMessage")] string StatusMessage,
    [property: JsonPropertyName("phases")] IReadOnlyList<string> Phases,
    [property: JsonPropertyName("firstPaintMs")] long? FirstPaintMs = null);
