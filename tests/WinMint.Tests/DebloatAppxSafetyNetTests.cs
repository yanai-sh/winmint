using WinMint.Orchestrator;
using WinMint.Provisioning;
using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

/// <summary>Ticket 13 — FirstLogon AppX safety-net job at S3 (fake PackageManager).</summary>
public class DebloatAppxSafetyNetTests
{
    [Fact]
    public void Shell_appx_safetyNet_removes_registered_packages_matching_catalog_ids()
    {
        RecordingAppx appx = new();
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
                jobs: [new ProvisionJob("debloat.appx.safetyNet", "appx.safetyNet")],
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
        RecordingAppx appx = new();
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
                jobs: [new ProvisionJob("debloat.appx.safetyNet", "appx.safetyNet")],
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
        Assert.Equal("debloat.appx.safetyNet", safety.Id);
        Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == "appx.safetyNet");
        Assert.DoesNotContain(
            planned.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.RemoveProvisionedAppx);
    }

    [Fact]
    public void Plan_offline_emits_remove_stage_not_safetyNet_job()
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
                "mode": "offline",
                "removeProvisionedAppx": ["Microsoft.BingNews"]
              }
            }
            """);

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk);
        Assert.Contains(
            planned.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.RemoveProvisionedAppx);
        Assert.DoesNotContain(planned.Value.Jobs.Jobs, j => j.Kind == "appx.safetyNet");
    }

    [Fact]
    public void Plan_emits_appx_safetyNet_job_when_profile_remove_list_empty()
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
        JobDescriptor safety = Assert.Single(
            planned.Value.Jobs.Jobs,
            j => j.Kind == "appx.safetyNet");
        Assert.Equal("debloat.appx.safetyNet", safety.Id);
    }

    private static Profile ParseProfile(string json)
    {
        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(
            System.Text.Encoding.UTF8.GetBytes(json));
        Assert.True(parsed.IsOk);
        return parsed.Value;
    }
}
