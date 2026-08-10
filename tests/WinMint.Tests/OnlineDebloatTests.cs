using System.Text;
using System.Text.Json;
using WinMint.Orchestrator;
using WinMint.Provisioning;
using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

public class OnlineDebloatPlanTests
{
    [Theory]
    [InlineData(null, true, false, true)]
    [InlineData("online", true, false, true)]
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
        Assert.Equal(expectSafetyNet, artifacts.Jobs.Jobs.Any(j => j.Kind == "appx.safetyNet"));
        Assert.Equal(
            expectOfflineStage,
            artifacts.Stages.Stages.Any(s => s.Opcode == ServicingOpcode.RemoveProvisionedAppx));
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
    public void PlanRequiresNetwork_always_true()
    {
        Assert.True(BuildPlan.PlanRequiresNetwork());
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
        SessionResult result = await ProvisioningSession.RunAsync(
            SessionMode.Shell,
            BundleFastSettle([new ProvisionJob("debloat.appx.safetyNet", ProvisionJobKind.AppxSafetyNet)]) with
            {
                RemoveProvisionedAppx = ["Microsoft.BingNews"],
                RequiresNetwork = true,
            },
            Env(appx, splash) with
            {
                Evidence = evidence,
                Connectivity = new OfflineConnectivityProbe(),
            },
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("network.required.offline", result.FinalStatus.Code);
        Assert.Contains(evidence.Documents[0].Phases, p => p == "network.required.offline");
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
        SessionResult result = await ProvisioningSession.RunAsync(
            SessionMode.Shell,
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
}
