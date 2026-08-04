using System.Text;
using WinMint.Orchestrator;
using WinMint.Provisioning;
using DmaSettleTarget = WinMint.Provisioning.DmaSettleTarget;

namespace WinMint.Tests;

/// <summary>Ticket 16 — metal winget job at S1 (Plan) + S3 (Run).</summary>
public class WingetJobsTests
{
    private static string SupervisorPath => ImageServicing.ShellStampGuestPath;

    [Fact]
    public void Plan_emits_winget_jobs_from_packages_winget()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountModeWire.LocalAutoLogon}}",
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
              "packages": {
                "winget": ["Git.Git", "Microsoft.VisualStudioCode"]
              }
            }
            """);

        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        IReadOnlyList<JobDescriptor> jobs = result.Value.Jobs.Jobs;
        Assert.Contains(jobs, j => j is { Kind: "stub", Id: "smoke.stub.ready" });
        Assert.Contains(jobs, j => j is { Kind: "stub", Id: "smoke.stub.complete" });
        JobDescriptor git = Assert.Single(jobs, j => j.Kind == "winget" && j.PackageId == "Git.Git");
        Assert.Equal("winget.Git.Git", git.Id);
        JobDescriptor vscode = Assert.Single(jobs, j => j.Kind == "winget" && j.PackageId == "Microsoft.VisualStudioCode");
        Assert.Equal("winget.Microsoft.VisualStudioCode", vscode.Id);
        Assert.Equal(2, jobs.Count(j => j.Kind == "winget"));
    }

    [Fact]
    public void Plan_without_packages_emits_stubs_only()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountModeWire.LocalAutoLogon}}",
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

        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        Assert.DoesNotContain(result.Value.Jobs.Jobs, j => j.Kind == "winget");
        Assert.All(result.Value.Jobs.Jobs, j => Assert.Equal("stub", j.Kind));
    }

    [Fact]
    public void Plan_wingetNeedsReboot_subset_emits_needsReboot_on_matching_jobs()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountModeWire.LocalAutoLogon}}",
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
              "packages": {
                "winget": ["jqlang.jq", "Git.Git"],
                "wingetNeedsReboot": ["jqlang.jq"]
              }
            }
            """);

        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        JobDescriptor jq = Assert.Single(result.Value.Jobs.Jobs, j => j.PackageId == "jqlang.jq");
        Assert.True(jq.NeedsReboot);
        JobDescriptor git = Assert.Single(result.Value.Jobs.Jobs, j => j.PackageId == "Git.Git");
        Assert.False(git.NeedsReboot);
    }

    [Fact]
    public void Plan_wingetNeedsReboot_id_not_in_winget_fails_closed()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountModeWire.LocalAutoLogon}}",
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
              "packages": {
                "winget": ["jqlang.jq"],
                "wingetNeedsReboot": ["Git.Git"]
              }
            }
            """);

        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);

        Assert.False(result.IsOk);
        Assert.Equal("packages.wingetNeedsReboot.unknown", result.Error.Code);
    }

    [Fact]
    public void Shell_winget_job_invokes_expected_argv()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(jobs: [new ProvisionJob("winget.Git.Git", "winget", PackageId: "Git.Git")]),
            Env(processes, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal("jobs.ok", result.FinalStatus.Code);
        Assert.Single(processes.Starts);
        Assert.Equal("winget", processes.Starts[0].FileName, StringComparer.OrdinalIgnoreCase);
        Assert.Equal(
            [
                "install",
                "--id",
                "Git.Git",
                "--exact",
                "--silent",
                "--accept-package-agreements",
                "--accept-source-agreements",
                "--disable-interactivity",
            ],
            processes.Starts[0].Arguments);
        Assert.Contains("jobs.ok", evidence.Documents[0].Phases);
    }

    [Fact]
    public void Shell_winget_job_registers_app_installer_before_spawn()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();
        RecordingAppx appx = new()
        {
            WingetPath = @"C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_1.0_arm64__8wekyb3d8bbwe\winget.exe",
        };

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(jobs: [new ProvisionJob("winget.jqlang.jq", "winget", PackageId: "jqlang.jq")]),
            Env(processes, evidence, appx: appx),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Contains(
            ProvisioningSession.DesktopAppInstallerFamilyName,
            appx.RegisteredFamilyNames);
        Assert.Single(processes.Starts);
        Assert.Equal(appx.WingetPath, processes.Starts[0].FileName);
    }

    [Fact]
    public void Shell_unknown_job_kind_still_unsupported()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(jobs: [new ProvisionJob("scoop.install", "scoop")]),
            Env(processes, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("jobs.kind.unsupported", result.FinalStatus.Code);
        Assert.Empty(processes.Starts);
        Assert.Contains("jobs.kind.unsupported", evidence.Documents[0].Phases);
    }

    [Fact]
    public void Shell_needsReboot_requests_os_reboot_after_checkpoint()
    {
        RecordingProcessHost processes = new();
        RecordingCheckpoints checkpoints = new();
        RecordingSystemReboot reboot = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(jobs: [new ProvisionJob("smoke.stub.reboot", "stub", NeedsReboot: true)]),
            Env(processes, evidence, checkpoints, reboot),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Reboot, result.Outcome);
        Assert.Equal("jobs:1", checkpoints.LastWritten!.Phase);
        Assert.True(reboot.Requested);
        Assert.Equal("Reboot", evidence.Documents[0].Outcome);
    }

    private static Profile Parse(string json)
    {
        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes(json));
        if (!parsed.IsOk)
        {
            Assert.Fail(string.Join("; ", parsed.Error.Issues.Select(i => $"{i.Code}: {i.Message}")));
        }

        return parsed.Value;
    }

    private static ProvisioningBundle Bundle(IReadOnlyList<ProvisionJob> jobs) =>
        new(
            Account: new AccountStamp("winmint", ""),
            Dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
            Jobs: jobs,
            Policy: SessionPolicy.SmokeDefaults,
            Supervisor: new SupervisorIdentity(SupervisorPath));

    private static SessionEnvironment Env(
        IProcessHost processes,
        IEvidenceSink evidence,
        ICheckpointStore? checkpoints = null,
        ISystemReboot? reboot = null,
        IAppxPackageManager? appx = null) =>
        new(
            Time: TimeProvider.System,
            Winlogon: new NoopWinlogon(),
            Region: new MatchingRegion(),
            Processes: processes,
            Splash: new RecordingSplashPresenter(),
            Checkpoints: checkpoints ?? new NoopCheckpoints(),
            Secrets: new NoopSecrets(),
            Evidence: evidence,
            Reboot: reboot,
            Appx: appx);

    private sealed class RecordingAppx : IAppxPackageManager
    {
        public List<string> RegisteredFamilyNames { get; } = [];

        public string? WingetPath { get; init; }

        public IReadOnlyList<AppxPackageInfo> FindRegisteredByCatalogId(string catalogId) => [];

        public IReadOnlyList<AppxPackageInfo> FindProvisionedByCatalogId(string catalogId) => [];

        public void RemovePackage(string packageFullName) { }

        public void DeprovisionPackageFamily(string packageFamilyName) { }

        public void RegisterPackageFamilyForCurrentUser(string packageFamilyName) =>
            RegisteredFamilyNames.Add(packageFamilyName);

        public void EnsureSystemFullControlOnWingetFrameworkPackages() { }

        public string? TryResolveWingetExecutablePath() => WingetPath;
    }

    private sealed class RecordingProcessHost : IProcessHost
    {
        public List<(string FileName, IReadOnlyList<string> Arguments)> Starts { get; } = [];

        public ProcessStartResult Run(
            string fileName,
            IReadOnlyList<string> arguments,
            CancellationToken ct = default)
        {
            Starts.Add((fileName, arguments));
            return new ProcessStartResult(0);
        }
    }

    private sealed class RecordingSystemReboot : ISystemReboot
    {
        public bool Requested { get; private set; }

        public void RequestReboot() => Requested = true;
    }

    private sealed class RecordingCheckpoints : ICheckpointStore
    {
        public CheckpointState? LastWritten { get; private set; }

        public TenureState ReadTenure() =>
            new(CheckpointInProgress: LastWritten is not null, HeartbeatUtc: null);

        public void WriteHeartbeat(DateTimeOffset utcNow) { }

        public void WriteCheckpoint(CheckpointState state) => LastWritten = state;

        public CheckpointState? TryReadCheckpoint() => LastWritten;

        public void ClearCheckpoint() => LastWritten = null;
    }

    private sealed class RecordingSplashPresenter : ISplashPresenter
    {
        public void Show() { }

        public void SetStatus(SessionStatus status) { }
    }

    private sealed class RecordingEvidenceSink : IEvidenceSink
    {
        public List<ProvisioningEvidenceDocument> Documents { get; } = [];

        public EvidenceSnapshot Write(ProvisioningEvidenceDocument document)
        {
            Documents.Add(document);
            return new EvidenceSnapshot(document.SchemaVersion, $"memory:{Documents.Count}");
        }
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
        public string? Shell { get; private set; } = SupervisorPath;

        public void SetAutoLogon(string username, string password) { }

        public string? GetDefaultUserName() => null;

        public bool GetAutoAdminLogon() => false;

        public string? GetShell() => Shell;

        public void SetShell(string path) => Shell = path;

        public void GrantShellUnlockAccess(string username) { }
    }

    private sealed class NoopCheckpoints : ICheckpointStore
    {
        public TenureState ReadTenure() => new(CheckpointInProgress: false, HeartbeatUtc: null);

        public void WriteHeartbeat(DateTimeOffset utcNow) { }

        public void WriteCheckpoint(CheckpointState state) { }

        public CheckpointState? TryReadCheckpoint() => null;

        public void ClearCheckpoint() { }
    }

    private sealed class NoopSecrets : ISecretScrubber
    {
        public void Wipe(ProvisioningBundle bundle) { }
    }
}
