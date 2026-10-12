using System.Text;
using System.Text.Json;

using WinMint.Contracts;
using WinMint.Orchestrator;
using WinMint.Provisioning;

using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

public class OnlineDebloatPlanTests
{
    [Theory]
    [InlineData(null, true, true, true)]
    [InlineData("online", true, true, true)]
    [InlineData("offline", false, true, true)]
    public void Plan_debloat_mode_controls_appx_venue(
        string? mode,
        bool expectSafetyNet,
        bool expectOfflineStage,
        bool expectRequiresNetwork)
    {
        string modeLine = mode is null ? "" : $$""" "mode": "{{mode}}", """;
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.LocalAutoLogonMode}}",
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
                {{modeLine}}
                "removeProvisionedAppx": ["Microsoft.BingNews"]
              }
            }
            """);

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk);
        BuildArtifacts artifacts = planned.Value;

        Assert.Equal(expectRequiresNetwork, artifacts.Manifest.RequiresNetwork);
        Assert.Equal(expectSafetyNet, artifacts.Jobs.Jobs.Any(j => j.Kind == ProvisionJobKind.AppxSafetyNet));
        Assert.Equal(
            expectOfflineStage,
            artifacts.Stages.Contains(ServicingOpcode.RemoveProvisionedAppx));
    }

    [Fact]
    public void SerializeProfile_omits_mode_when_online()
    {
        Profile profile = Parse("""
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

        string json = Encoding.UTF8.GetString(BuildPlan.SerializeProfile(profile));
        using (JsonDocument doc = JsonDocument.Parse(json))
        {
            JsonElement debloat = doc.RootElement.GetProperty("debloat");
            Assert.False(debloat.TryGetProperty("mode", out _));
            Assert.Contains(
                "Microsoft.BingNews",
                debloat.GetProperty("removeProvisionedAppx").EnumerateArray().Select(e => e.GetString()),
                StringComparer.Ordinal);
        }

        Profile offline = profile with { DebloatMode = DebloatMode.Offline };
        string offlineJson = Encoding.UTF8.GetString(BuildPlan.SerializeProfile(offline));
        Assert.Contains("\"mode\": \"offline\"", offlineJson, StringComparison.Ordinal);
    }

    [Fact]
    public void PlanRequiresNetwork_true_when_winget_jobs_present()
    {
        Assert.True(BuildPlan.PlanRequiresNetwork(
        [
            new ProvisionJob("winget.import", ProvisionJobKind.WingetImport),
        ]));
        Assert.False(BuildPlan.PlanRequiresNetwork(
        [
            new ProvisionJob("smoke.stub.ready", ProvisionJobKind.Stub),
            new ProvisionJob("workstation.quiet", ProvisionJobKind.WorkstationQuiet),
            new ProvisionJob("wsl.platform", ProvisionJobKind.WslPlatform),
            new ProvisionJob("shell.chrome", ProvisionJobKind.ShellChrome),
        ]));
    }

    private static Profile Parse(string json)
    {
        Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes(json));
        Assert.True(parsed.IsOk);
        return parsed.Value;
    }
}

public class OnlineDebloatSessionTests
{
    [Fact]
    public async Task Shell_network_required_offline_fails_after_settle_with_evidence()
    {
        RecordingAppx appx = new();
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();
        SessionResult result = await ProvisioningSession.RunShellAsync(
            BundleFastSettle([new ProvisionJob("debloat.appx.safetyNet", ProvisionJobKind.AppxSafetyNet)]) with
            {
                RemoveProvisionedAppx = ["Microsoft.BingNews"],
                RequiresNetwork = true,
            },
            Env(
                new FakeGuestMachine
                {
                    Appx = appx,
                    Connectivity = new OfflineConnectivityProbe(),
                },
                evidence,
                splash: splash),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("network.required.offline", result.FinalStatus.Code);
        Assert.Contains(evidence.Documents[0].Phases, p => p == "network.wait");
        Assert.Contains(evidence.Documents[0].Phases, p => p == "network.required.offline");
    }

    [Fact]
    public async Task Shell_requiresNetwork_waits_then_ok_when_connectivity_appears()
    {
        RecordingEvidenceSink evidence = new();
        DelayedConnectivityProbe probe = new(failCount: 3);
        SessionResult result = await ProvisioningSession.RunShellAsync(
            BundleFastSettle([new ProvisionJob("debloat.appx.safetyNet", ProvisionJobKind.AppxSafetyNet)]) with
            {
                RemoveProvisionedAppx = ["Microsoft.BingNews"],
                RequiresNetwork = true,
            },
            Env(
                new FakeGuestMachine
                {
                    Appx = new RecordingAppx(),
                    Connectivity = probe,
                },
                evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Contains(evidence.Documents[0].Phases, p => p == "network.wait");
        Assert.Contains(evidence.Documents[0].Phases, p => p == "network.ok");
        Assert.DoesNotContain(evidence.Documents[0].Phases, p => p == "network.required.offline");
    }

    [Fact]
    public async Task Shell_requiresNetwork_false_completes_when_offline()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();
        SessionResult result = await ProvisioningSession.RunShellAsync(
            BundleFastSettle(
            [
                new ProvisionJob("smoke.stub.ready", ProvisionJobKind.Stub),
                new ProvisionJob("smoke.stub.complete", ProvisionJobKind.Stub),
            ]) with
            {
                RequiresNetwork = false,
            },
            Env(
                new FakeGuestMachine
                {
                    Processes = processes,
                    Connectivity = new OfflineConnectivityProbe(),
                },
                evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.DoesNotContain(evidence.Documents[0].Phases, p => p == "network.required.offline");
        Assert.Equal("jobs.ok", result.FinalStatus.Code);
    }

    [Fact]
    public async Task Shell_online_appx_job_emits_removed_phase_per_catalog_id()
    {
        RecordingAppx appx = new();
        appx.Registered.Add(new AppxPackageInfo(
            "Microsoft.BingNews_1.0.0.0_neutral__8wekyb3d8bbwe",
            "Microsoft.BingNews_8wekyb3d8bbwe",
            "Microsoft.BingNews"));

        RecordingEvidenceSink evidence = new();
        SessionResult result = await ProvisioningSession.RunShellAsync(
            BundleFastSettle([new ProvisionJob("debloat.appx.safetyNet", ProvisionJobKind.AppxSafetyNet)]) with
            {
                RemoveProvisionedAppx = ["Microsoft.BingNews"],
            },
            Env(appx, new RecordingSplashPresenter()) with { Evidence = evidence },
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Contains(evidence.Documents[0].Phases, p => p == "removed.appx.online.Microsoft.BingNews");
    }

    private sealed class OfflineConnectivityProbe : IConnectivityProbe
    {
        public Task<bool> HasOutboundNetworkAsync(CancellationToken ct = default) =>
            Task.FromResult(false);
    }

    private sealed class DelayedConnectivityProbe(int failCount) : IConnectivityProbe
    {
        private int _remaining = failCount;

        public Task<bool> HasOutboundNetworkAsync(CancellationToken ct = default)
        {
            if (_remaining > 0)
            {
                _remaining--;
                return Task.FromResult(false);
            }

            return Task.FromResult(true);
        }
    }
}
