using WinMint.Orchestrator;
using WinMint.Provisioning;
using DmaSettleTarget = WinMint.Provisioning.DmaSettleTarget;

namespace WinMint.Tests;

/// <summary>Ticket 13 — FirstLogon AppX safety-net job at S3 (fake PackageManager).</summary>
public class KeepFlagAppxSafetyNetTests
{
    private static string SupervisorPath => ImageServicing.ShellStampGuestPath;

    [Fact]
    public void Shell_appx_safetyNet_removes_registered_packages_matching_catalog_ids()
    {
        FakeAppxPackageManager appx = new();
        appx.Registered.Add(new AppxPackageInfo(
            "Microsoft.BingNews_1.0.0.0_neutral__8wekyb3d8bbwe",
            "Microsoft.BingNews_8wekyb3d8bbwe",
            "Microsoft.BingNews"));
        appx.Registered.Add(new AppxPackageInfo(
            "Microsoft.Other_1.0.0.0_neutral__8wekyb3d8bbwe",
            "Microsoft.Other_8wekyb3d8bbwe",
            "Microsoft.Other"));

        RecordingSplashPresenter splash = new();
        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(
                jobs: [new ProvisionJob("keepflag.appx.safetyNet", "appx.safetyNet")],
                removeProvisionedAppx: ["Microsoft.BingNews"]),
            Env(appx, splash),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal("jobs.ok", result.FinalStatus.Code);
        Assert.Equal(
            ["Microsoft.BingNews_1.0.0.0_neutral__8wekyb3d8bbwe"],
            appx.RemovedFullNames);
        Assert.Empty(appx.DeprovisionedFamilyNames);
    }

    [Fact]
    public void Shell_appx_safetyNet_deprovisions_only_when_still_provisioned()
    {
        FakeAppxPackageManager appx = new();
        appx.Registered.Add(new AppxPackageInfo(
            "Microsoft.GamingApp_1.0.0.0_neutral__8wekyb3d8bbwe",
            "Microsoft.GamingApp_8wekyb3d8bbwe",
            "Microsoft.GamingApp"));
        appx.Provisioned.Add(new AppxPackageInfo(
            "Microsoft.GamingApp_1.0.0.0_neutral__8wekyb3d8bbwe",
            "Microsoft.GamingApp_8wekyb3d8bbwe",
            "Microsoft.GamingApp"));
        // BingNews listed and still provisioned (not registered) → deprovision only.
        appx.Provisioned.Add(new AppxPackageInfo(
            "Microsoft.BingNews_1.0.0.0_neutral__8wekyb3d8bbwe",
            "Microsoft.BingNews_8wekyb3d8bbwe",
            "Microsoft.BingNews"));

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(
                jobs: [new ProvisionJob("keepflag.appx.safetyNet", "appx.safetyNet")],
                removeProvisionedAppx: ["Microsoft.GamingApp", "Microsoft.BingNews"]),
            Env(appx, new RecordingSplashPresenter()),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal(
            ["Microsoft.GamingApp_1.0.0.0_neutral__8wekyb3d8bbwe"],
            appx.RemovedFullNames);
        Assert.Equal(
            ["Microsoft.GamingApp_8wekyb3d8bbwe", "Microsoft.BingNews_8wekyb3d8bbwe"],
            appx.DeprovisionedFamilyNames);
    }

    [Fact]
    public void Plan_emits_appx_safetyNet_job_when_remove_list_non_empty()
    {
        Profile profile = ParseProfile("""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "localAutoLogon",
                "username": "winmint",
                "password": "lab-only"
              },
              "dma": {
                "enabled": true,
                "settle": {
                  "locale": "en-GB",
                  "geoId": 242,
                  "timeZoneId": "GMT Standard Time",
                  "locationServicesEnabled": true
                }
              },
              "debloat": {
                "removeProvisionedAppx": ["Microsoft.BingNews"]
              }
            }
            """);

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        JobDescriptor safety = Assert.Single(
            planned.Value.Jobs.Jobs,
            j => j.Kind == "appx.safetyNet");
        Assert.Equal("keepflag.appx.safetyNet", safety.Id);
        Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == "stub");
    }

    [Fact]
    public void Plan_omits_appx_safetyNet_job_when_remove_list_empty()
    {
        Profile profile = ParseProfile("""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "localAutoLogon",
                "username": "winmint",
                "password": "lab-only"
              },
              "dma": {
                "enabled": true,
                "settle": {
                  "locale": "en-GB",
                  "geoId": 242,
                  "timeZoneId": "GMT Standard Time",
                  "locationServicesEnabled": true
                }
              }
            }
            """);

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk);
        Assert.DoesNotContain(planned.Value.Jobs.Jobs, j => j.Kind == "appx.safetyNet");
    }

    private static Profile ParseProfile(string json)
    {
        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(
            System.Text.Encoding.UTF8.GetBytes(json));
        Assert.True(parsed.IsOk);
        return parsed.Value;
    }

    private static ProvisioningBundle Bundle(
        IReadOnlyList<ProvisionJob> jobs,
        IReadOnlyList<string> removeProvisionedAppx) =>
        new(
            Account: new AccountStamp("winmint", ""),
            Dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
            Jobs: jobs,
            Policy: SessionPolicy.SmokeDefaults,
            Supervisor: new SupervisorIdentity(SupervisorPath),
            RemoveProvisionedAppx: removeProvisionedAppx);

    private static SessionEnvironment Env(IAppxPackageManager appx, ISplashPresenter splash) =>
        new(
            Time: TimeProvider.System,
            Winlogon: new NoopWinlogon(),
            Region: new MatchingRegion(),
            Processes: new NoopProcesses(),
            Splash: splash,
            Checkpoints: new NoopCheckpoints(),
            Evidence: new NoopEvidence(),
            Appx: appx);

    private sealed class FakeAppxPackageManager : IAppxPackageManager
    {
        public List<AppxPackageInfo> Registered { get; } = [];
        public List<AppxPackageInfo> Provisioned { get; } = [];
        public List<string> RemovedFullNames { get; } = [];
        public List<string> DeprovisionedFamilyNames { get; } = [];

        public IReadOnlyList<AppxPackageInfo> FindRegisteredByCatalogId(string catalogId) =>
            Registered.Where(p => WinRTAppxPackageManager.MatchesCatalogId(p, catalogId)).ToArray();

        public IReadOnlyList<AppxPackageInfo> FindProvisionedByCatalogId(string catalogId) =>
            Provisioned.Where(p => WinRTAppxPackageManager.MatchesCatalogId(p, catalogId)).ToArray();

        public void RemovePackage(string packageFullName) => RemovedFullNames.Add(packageFullName);

        public void DeprovisionPackageFamily(string packageFamilyName) =>
            DeprovisionedFamilyNames.Add(packageFamilyName);

        public void RegisterPackageFamilyForCurrentUser(string packageFamilyName) =>
            RegisteredFamilyNames.Add(packageFamilyName);

        public void EnsureSystemFullControlOnWingetFrameworkPackages() { }

        public string? TryResolveWingetExecutablePath() => null;

        public List<string> RegisteredFamilyNames { get; } = [];
    }

    private sealed class RecordingSplashPresenter : ISplashPresenter
    {
        public List<string> Events { get; } = [];

        public void Show() => Events.Add("Show");

        public void SetStatus(SessionStatus status) => Events.Add($"Status:{status.Code}");
    }

    private sealed class MatchingRegion : IRegionSnapshot
    {
        private RegionState _state = new("en-GB", 242, "GMT Standard Time", true);

        public void Apply(DmaSettleTarget target) =>
            _state = new RegionState(
                target.Locale,
                target.GeoId,
                target.TimeZoneId,
                target.LocationServicesEnabled);

        public RegionState Read() => _state;
    }

    private sealed class NoopWinlogon : IWinlogonRegistry
    {
        public void SetAutoLogon(string username, string password) { }

        public string? GetDefaultUserName() => null;

        public bool GetAutoAdminLogon() => false;

        public string? Shell { get; private set; } = SupervisorPath;

        public string? GetShell() => Shell;

        public void SetShell(string path) => Shell = path;

        public void GrantShellUnlockAccess(string username) { }
    }

    private sealed class NoopProcesses : IProcessHost
    {
        public ProcessStartResult Run(
            string fileName,
            IReadOnlyList<string> arguments,
            CancellationToken ct = default) =>
            new(0);
    }

    private sealed class NoopCheckpoints : ICheckpointStore
    {
        public TenureState ReadTenure() => new(CheckpointInProgress: false, HeartbeatUtc: null);

        public void WriteHeartbeat(DateTimeOffset utcNow) { }

        public void WriteCheckpoint(CheckpointState state) { }

        public CheckpointState? TryReadCheckpoint() => null;

        public void ClearCheckpoint() { }
    }

    private sealed class NoopEvidence : IEvidenceSink
    {
        public EvidenceSnapshot Write(ProvisioningEvidenceDocument document) =>
            new(document.SchemaVersion, "memory:1");
    }
}
