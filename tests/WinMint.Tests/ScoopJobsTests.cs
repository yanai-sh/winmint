using System.Text;
using WinMint.Orchestrator;
using WinMint.Provisioning;
using DmaSettleTarget = WinMint.Provisioning.DmaSettleTarget;

namespace WinMint.Tests;

/// <summary>Ticket 18 — metal scoop job at S1 (Plan) + S3 (Run).</summary>
public class ScoopJobsTests
{
    private static string SupervisorPath => ImageServicing.ShellStampGuestPath;

    [Fact]
    public void Plan_emits_scoop_jobs_from_packages_scoop()
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
                "scoop": ["curl", "jq"]
              }
            }
            """);

        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        JobDescriptor curl = Assert.Single(result.Value.Jobs.Jobs, j => j.Kind == "scoop" && j.PackageId == "curl");
        Assert.Equal("scoop.curl", curl.Id);
        Assert.False(curl.NeedsReboot);
        Assert.Contains(result.Value.Jobs.Jobs, j => j.Kind == "scoop" && j.PackageId == "jq");
    }

    [Fact]
    public void Plan_scoopNeedsReboot_subset_emits_needsReboot()
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
                "scoop": ["curl"],
                "scoopNeedsReboot": ["curl"]
              }
            }
            """);

        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        JobDescriptor curl = Assert.Single(result.Value.Jobs.Jobs, j => j.PackageId == "curl");
        Assert.True(curl.NeedsReboot);
    }

    [Fact]
    public void Plan_scoopNeedsReboot_id_not_in_scoop_fails_closed()
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
                "scoop": ["curl"],
                "scoopNeedsReboot": ["jq"]
              }
            }
            """);

        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);

        Assert.False(result.IsOk);
        Assert.Equal("packages.scoopNeedsReboot.unknown", result.Error.Code);
    }

    [Fact]
    public void Shell_scoop_bootstraps_then_installs_when_scoop_missing()
    {
        RecordingProcessHost processes = new()
        {
            OnRun = (file, args) =>
            {
                if (file.Equals("powershell.exe", StringComparison.OrdinalIgnoreCase))
                {
                    // Pretend bootstrap wrote scoop.cmd for the next resolve — tests use fake host only.
                    return new ProcessStartResult(0);
                }

                return new ProcessStartResult(0);
            },
        };
        RecordingEvidenceSink evidence = new();

        // Without a real scoop.cmd on disk, production would bootstrap then fail resolve.
        // Inject a temp scoop.cmd so the install path is exercised after a bootstrap attempt.
        string shimDir = Path.Combine(Path.GetTempPath(), "winmint-scoop-test-" + Guid.NewGuid().ToString("n"), "scoop", "shims");
        Directory.CreateDirectory(shimDir);
        string scoopCmd = Path.Combine(shimDir, "scoop.cmd");
        File.WriteAllText(scoopCmd, "@echo off");

        // Pre-create under USERPROFILE so TryResolveScoopCmd finds it — then no bootstrap.
        // Separate test covers bootstrap argv when missing.
        string userScoop = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "scoop",
            "shims");
        bool createdShim = false;
        string? previous = null;
        string target = Path.Combine(userScoop, "scoop.cmd");
        try
        {
            Directory.CreateDirectory(userScoop);
            if (File.Exists(target))
            {
                previous = File.ReadAllText(target);
            }
            else
            {
                createdShim = true;
            }

            File.WriteAllText(target, "@echo off");

            SessionResult result = ProvisioningSession.Run(
                SessionMode.Shell,
                Bundle(jobs: [new ProvisionJob("scoop.curl", "scoop", PackageId: "curl")]),
                Env(processes, evidence),
                TestContext.Current.CancellationToken);

            Assert.Equal(SessionOutcome.Complete, result.Outcome);
            Assert.Equal("jobs.ok", result.FinalStatus.Code);
            Assert.DoesNotContain(
                processes.Starts,
                s => s.FileName.Equals("powershell.exe", StringComparison.OrdinalIgnoreCase));
            Assert.Contains(
                processes.Starts,
                s => s.FileName.EndsWith("scoop.cmd", StringComparison.OrdinalIgnoreCase)
                    && s.Arguments is ["install", "curl"]);
        }
        finally
        {
            if (createdShim && File.Exists(target))
            {
                File.Delete(target);
            }
            else if (previous is not null)
            {
                File.WriteAllText(target, previous);
            }
        }
    }

    [Fact]
    public void Shell_scoop_bootstraps_via_official_admin_one_liner_when_missing()
    {
        string userScoopShim = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "scoop",
            "shims",
            "scoop.cmd");

        bool moved = false;
        string backupPath = userScoopShim + ".winmint-test-bak";
        try
        {
            if (File.Exists(userScoopShim))
            {
                File.Move(userScoopShim, backupPath, overwrite: true);
                moved = true;
            }

            RecordingProcessHost processes = new()
            {
                OnRun = (file, args) =>
                {
                    if (file.Equals("powershell.exe", StringComparison.OrdinalIgnoreCase))
                    {
                        // Bootstrap "succeeds" but does not create scoop.cmd → bootstrap_failed.
                        return new ProcessStartResult(0);
                    }

                    return new ProcessStartResult(0);
                },
            };
            RecordingEvidenceSink evidence = new();

            SessionResult result = ProvisioningSession.Run(
                SessionMode.Shell,
                Bundle(jobs: [new ProvisionJob("scoop.curl", "scoop", PackageId: "curl")]),
                Env(processes, evidence),
                TestContext.Current.CancellationToken);

            Assert.Equal(SessionOutcome.Failed, result.Outcome);
            Assert.Equal("jobs.scoop.bootstrap_failed", result.FinalStatus.Code);
            Assert.Single(processes.Starts);
            Assert.Equal("powershell.exe", processes.Starts[0].FileName, StringComparer.OrdinalIgnoreCase);
            Assert.Equal("-NoProfile", processes.Starts[0].Arguments[0]);
            Assert.Equal("-ExecutionPolicy", processes.Starts[0].Arguments[1]);
            Assert.Equal("Bypass", processes.Starts[0].Arguments[2]);
            Assert.Equal("-Command", processes.Starts[0].Arguments[3]);
            Assert.Contains("get.scoop.sh", processes.Starts[0].Arguments[4]);
            Assert.Contains("-RunAsAdmin", processes.Starts[0].Arguments[4]);
        }
        finally
        {
            if (moved && File.Exists(backupPath))
            {
                File.Move(backupPath, userScoopShim, overwrite: true);
            }
        }
    }

    [Fact]
    public void Shell_unknown_job_kind_still_unsupported()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(jobs: [new ProvisionJob("wsl.install", "wsl")]),
            Env(processes, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("jobs.kind.unsupported", result.FinalStatus.Code);
        Assert.Empty(processes.Starts);
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

    private static SessionEnvironment Env(IProcessHost processes, IEvidenceSink evidence) =>
        new(
            Time: TimeProvider.System,
            Winlogon: new NoopWinlogon(),
            Region: new MatchingRegion(),
            Processes: processes,
            Splash: new RecordingSplashPresenter(),
            Checkpoints: new NoopCheckpoints(),
            Secrets: new NoopSecrets(),
            Evidence: evidence);

    private sealed class RecordingProcessHost : IProcessHost
    {
        public List<(string FileName, IReadOnlyList<string> Arguments)> Starts { get; } = [];

        public Func<string, IReadOnlyList<string>, ProcessStartResult>? OnRun { get; init; }

        public ProcessStartResult Run(
            string fileName,
            IReadOnlyList<string> arguments,
            CancellationToken ct = default)
        {
            Starts.Add((fileName, arguments));
            return OnRun?.Invoke(fileName, arguments) ?? new ProcessStartResult(0);
        }
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
