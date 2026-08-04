using System.Text;
using System.Text.Json;
using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>Ticket 22 — Wizard authors packages.* into Profile (S1b compose → Plan).</summary>
public class WizardPackagesTests
{
    [Fact]
    public void Compose_winget_and_scoop_plans_metal_jobs()
    {
        byte[] utf8 = WizardProfileComposer.ToUtf8Json(
            username: "winmint",
            password: "lab-only",
            requireWifiDuringOobe: false,
            dmaEnabled: true,
            locale: "en-GB",
            geoId: 242,
            timeZoneId: "GMT Standard Time",
            locationServicesEnabled: true,
            removeProvisionedAppx: [],
            winget: ["jqlang.jq"],
            wingetNeedsReboot: ["jqlang.jq"],
            scoop: ["curl"],
            scoopNeedsReboot: []);

        string json = Encoding.UTF8.GetString(utf8);
        using JsonDocument doc = JsonDocument.Parse(json);
        JsonElement packages = doc.RootElement.GetProperty("packages");
        Assert.Equal("jqlang.jq", packages.GetProperty("winget")[0].GetString());
        Assert.Equal("jqlang.jq", packages.GetProperty("wingetNeedsReboot")[0].GetString());
        Assert.Equal("curl", packages.GetProperty("scoop")[0].GetString());
        Assert.False(packages.TryGetProperty("scoopNeedsReboot", out _));

        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(utf8);
        Assert.True(parsed.IsOk, parsed.IsOk ? null : string.Join("; ", parsed.Error.Issues.Select(i => i.Code)));

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(parsed.Value);
        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        Assert.Contains(
            planned.Value.Jobs.Jobs,
            j => j.Kind == "winget" && j.PackageId == "jqlang.jq" && j.NeedsReboot);
        Assert.Contains(
            planned.Value.Jobs.Jobs,
            j => j.Kind == "scoop" && j.PackageId == "curl" && !j.NeedsReboot);
    }

    [Fact]
    public void Compose_empty_packages_omits_packages_object()
    {
        byte[] utf8 = WizardProfileComposer.ToUtf8Json(
            username: "winmint",
            password: "lab-only",
            requireWifiDuringOobe: false,
            dmaEnabled: true,
            locale: "en-GB",
            geoId: 242,
            timeZoneId: "GMT Standard Time",
            locationServicesEnabled: true,
            removeProvisionedAppx: []);

        string json = Encoding.UTF8.GetString(utf8);
        Assert.DoesNotContain("\"packages\"", json, StringComparison.Ordinal);

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(BuildPlan.TryParseProfile(utf8).Value);
        Assert.True(planned.IsOk);
        Assert.All(planned.Value.Jobs.Jobs, j => Assert.Equal("stub", j.Kind));
    }

    [Fact]
    public void Compose_wingetNeedsReboot_not_in_winget_fails_plan()
    {
        byte[] utf8 = WizardProfileComposer.ToUtf8Json(
            username: "winmint",
            password: "lab-only",
            requireWifiDuringOobe: false,
            dmaEnabled: true,
            locale: "en-GB",
            geoId: 242,
            timeZoneId: "GMT Standard Time",
            locationServicesEnabled: true,
            removeProvisionedAppx: [],
            winget: ["jqlang.jq"],
            wingetNeedsReboot: ["Git.Git"]);

        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(utf8);
        Assert.True(parsed.IsOk);

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(parsed.Value);
        Assert.False(planned.IsOk);
        Assert.Equal("packages.wingetNeedsReboot.unknown", planned.Error.Code);
    }

    [Fact]
    public void Compose_scoopNeedsReboot_not_in_scoop_fails_plan()
    {
        byte[] utf8 = WizardProfileComposer.ToUtf8Json(
            username: "winmint",
            password: "lab-only",
            requireWifiDuringOobe: false,
            dmaEnabled: true,
            locale: "en-GB",
            geoId: 242,
            timeZoneId: "GMT Standard Time",
            locationServicesEnabled: true,
            removeProvisionedAppx: [],
            scoop: ["curl"],
            scoopNeedsReboot: ["7zip"]);

        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(utf8);
        Assert.True(parsed.IsOk);

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(parsed.Value);
        Assert.False(planned.IsOk);
        Assert.Equal("packages.scoopNeedsReboot.unknown", planned.Error.Code);
    }

    [Fact]
    public void ParseIdList_newline_trim_drops_blanks()
    {
        IReadOnlyList<string> ids = WizardProfileComposer.ParseIdList("  jqlang.jq\n\ncurl  \r\n\n");
        Assert.Equal(["jqlang.jq", "curl"], ids);
        Assert.Empty(WizardProfileComposer.ParseIdList(null));
        Assert.Empty(WizardProfileComposer.ParseIdList("  \n  "));
    }
}
