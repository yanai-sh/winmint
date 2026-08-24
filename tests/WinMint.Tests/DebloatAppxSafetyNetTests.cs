using WinMint.Contracts;
using WinMint.Orchestrator;
using WinMint.Provisioning;

using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

/// <summary>Ticket 13 — FirstLogon AppX safety-net job at S3 (fake PackageManager).</summary>
public class DebloatAppxSafetyNetTests
{
    [Fact]
    public async Task Shell_appx_safetyNet_removes_registered_packages_matching_catalog_ids()
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
        RecordingEvidenceSink evidence = new();
        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(
                jobs: [new ProvisionJob("debloat.appx.safetyNet", ProvisionJobKind.AppxSafetyNet)],
                removeProvisionedAppx: ["Microsoft.BingNews"]),
            Env(new FakeGuestMachine { Appx = appx }, evidence, splash: splash),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal("jobs.ok", result.FinalStatus.Code);
        Assert.Equal(
            ["Microsoft.BingNews_1.0.0.0_neutral__8wekyb3d8bbwe"],
            appx.RemovedFullNames);
        Assert.Empty(appx.DeprovisionedFamilyNames);
        Assert.Equal(
            ["Microsoft.BingNews_8wekyb3d8bbwe"],
            appx.EnsuredDeprovisionedMarks);
        string[] effectPhases =
        [
            "removed.appx.online.Microsoft.BingNews",
            "deprovisioned.appx.Microsoft.BingNews_8wekyb3d8bbwe",
        ];
        Assert.All(effectPhases, phase => Assert.Contains($"Status:{phase}", splash.Events));
        Assert.All(effectPhases, phase => Assert.Contains(phase, evidence.Documents[^1].Phases));
    }

    [Fact]
    public async Task Shell_appx_safetyNet_deprovisions_only_when_still_provisioned()
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

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(
                jobs: [new ProvisionJob("debloat.appx.safetyNet", ProvisionJobKind.AppxSafetyNet)],
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
        Assert.Equal(
            ["Microsoft.BingNews_8wekyb3d8bbwe", "Microsoft.GamingApp_8wekyb3d8bbwe"],
            [.. appx.EnsuredDeprovisionedMarks.OrderBy(s => s, StringComparer.Ordinal)]);
    }

    [Fact]
    public async Task Shell_appx_safetyNet_stamps_deprovisioned_when_already_absent()
    {
        // Offline DISM already removed packages: live finds empty. Must still stamp
        // Deprovisioned hive (Learn FU guidance) and must NOT emit vacuous removed.appx.online.*.
        RecordingAppx appx = new();
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(
                jobs: [new ProvisionJob("debloat.appx.safetyNet", ProvisionJobKind.AppxSafetyNet)],
                removeProvisionedAppx: ["Microsoft.BingNews", "Microsoft.BingWeather"]),
            Env(new FakeGuestMachine { Appx = appx }, evidence, splash: splash),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Empty(appx.RemovedFullNames);
        Assert.Empty(appx.DeprovisionedFamilyNames);
        Assert.Equal(
            ["Microsoft.BingNews_8wekyb3d8bbwe", "Microsoft.BingWeather_8wekyb3d8bbwe"],
            [.. appx.EnsuredDeprovisionedMarks.OrderBy(s => s, StringComparer.Ordinal)]);
        Assert.DoesNotContain(
            splash.Events,
            e => e.StartsWith("Status:removed.appx.online.", StringComparison.Ordinal));
        Assert.Contains("Status:deprovisioned.appx.Microsoft.BingNews_8wekyb3d8bbwe", splash.Events);
        Assert.Contains("Status:deprovisioned.appx.Microsoft.BingWeather_8wekyb3d8bbwe", splash.Events);
        Assert.Contains("deprovisioned.appx.Microsoft.BingNews_8wekyb3d8bbwe", evidence.Documents[^1].Phases);
        Assert.DoesNotContain(
            evidence.Documents[^1].Phases,
            p => p.StartsWith("removed.appx.online.", StringComparison.Ordinal));
    }

    [Fact]
    public async Task Shell_appx_safetyNet_fails_when_family_still_visible_after_remove()
    {
        RecordingAppx appx = new() { RemoveIsNoOp = true };
        appx.Registered.Add(new AppxPackageInfo(
            "Microsoft.MicrosoftSolitaireCollection_1.0.0.0_neutral__8wekyb3d8bbwe",
            "Microsoft.MicrosoftSolitaireCollection_8wekyb3d8bbwe",
            "Microsoft.MicrosoftSolitaireCollection"));

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(
                jobs: [new ProvisionJob("debloat.appx.safetyNet", ProvisionJobKind.AppxSafetyNet)],
                removeProvisionedAppx: ["Microsoft.MicrosoftSolitaireCollection"]),
            Env(new FakeGuestMachine { Appx = appx }, new RecordingEvidenceSink()),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
    }

    [Fact]
    public void MatchesCatalogId_prefix_matches_publisher_variant()
    {
        AppxPackageInfo linkedIn = new(
            "7EE7776C.LinkedInforWindows_1.0.0.0_neutral__wfncspz0ncs4j",
            "7EE7776C.LinkedInforWindows_wfncspz0ncs4j",
            "7EE7776C.LinkedInforWindows");
        Assert.True(WinRTAppxPackageManager.MatchesCatalogId(linkedIn, "LinkedInforWindows"));
    }

    [Fact]
    public void AppxCatalogFamilyNames_resolves_microsoft_store_publisher()
    {
        Assert.Equal(
            "Microsoft.BingNews_8wekyb3d8bbwe",
            AppxCatalogFamilyNames.Resolve("Microsoft.BingNews"));
        Assert.Equal(
            "Clipchamp.Clipchamp_yxz26nhyzhsrt",
            AppxCatalogFamilyNames.Resolve("Clipchamp.Clipchamp"));
    }

    [Fact]
    public void AppxDeprovisionedMarks_path_is_under_appx_all_user_store()
    {
        Assert.Contains(
            "AppxAllUserStore\\Deprovisioned",
            AppxDeprovisionedMarks.DeprovisionedRoot,
            StringComparison.Ordinal);
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

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        ProvisionJob safety = Assert.Single(
            planned.Value.Jobs.Jobs,
            j => j.Kind == ProvisionJobKind.AppxSafetyNet);
        Assert.Equal("debloat.appx.safetyNet", safety.Id);
        Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.AppxSafetyNet);
        Assert.DoesNotContain(ServicingOpcode.RemoveProvisionedAppx, planned.Value.Stages);
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

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk);
        Assert.Contains(ServicingOpcode.RemoveProvisionedAppx, planned.Value.Stages);
        Assert.DoesNotContain(planned.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.AppxSafetyNet);
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

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk);
        ProvisionJob safety = Assert.Single(
            planned.Value.Jobs.Jobs,
            j => j.Kind == ProvisionJobKind.AppxSafetyNet);
        Assert.Equal("debloat.appx.safetyNet", safety.Id);
    }

    private static Profile ParseProfile(string json)
    {
        Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile(
            System.Text.Encoding.UTF8.GetBytes(json));
        Assert.True(parsed.IsOk);
        return parsed.Value;
    }
}
