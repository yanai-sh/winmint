using System.Text;
using System.Text.Json;
using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>Ticket 22 — Wizard authors packages.* into Profile (S1b compose → Plan).</summary>
public class WizardPackagesTests
{
    private static Profile LabProfile(
        IReadOnlyList<string>? winget = null,
        IReadOnlyList<string>? wingetNeedsReboot = null,
        IReadOnlyList<string>? scoop = null,
        IReadOnlyList<string>? scoopNeedsReboot = null) =>
        new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true)),
            [],
            winget ?? [],
            wingetNeedsReboot ?? [],
            scoop ?? [],
            scoopNeedsReboot ?? [],
            [],
            [],
            [],
            []);

    [Fact]
    public void Serialize_winget_and_scoop_plans_metal_jobs()
    {
        Profile profile = LabProfile(
            winget: ["jqlang.jq"],
            wingetNeedsReboot: ["jqlang.jq"],
            scoop: ["curl"],
            scoopNeedsReboot: []);

        byte[] utf8 = BuildPlan.SerializeProfile(profile);
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
    public void Serialize_empty_packages_omits_packages_object()
    {
        byte[] utf8 = BuildPlan.SerializeProfile(LabProfile());

        string json = Encoding.UTF8.GetString(utf8);
        Assert.DoesNotContain("\"packages\"", json, StringComparison.Ordinal);

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(BuildPlan.TryParseProfile(utf8).Value);
        Assert.True(planned.IsOk);
        Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == "stub");
        Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == "onedrive.uninstall");
        Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == "reservedStorage.disable");
        Assert.DoesNotContain(planned.Value.Jobs.Jobs, j => j.Kind is "winget" or "scoop" or "wsl");
    }

    [Fact]
    public void Serialize_wingetNeedsReboot_not_in_winget_fails_plan()
    {
        Profile profile = LabProfile(winget: ["jqlang.jq"], wingetNeedsReboot: ["Git.Git"]);

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(profile);
        Assert.False(planned.IsOk);
        Assert.Equal("packages.wingetNeedsReboot.unknown", planned.Error.Code);
    }

    [Fact]
    public void Serialize_scoopNeedsReboot_not_in_scoop_fails_plan()
    {
        Profile profile = LabProfile(scoop: ["curl"], scoopNeedsReboot: ["7zip"]);

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(profile);
        Assert.False(planned.IsOk);
        Assert.Equal("packages.scoopNeedsReboot.unknown", planned.Error.Code);
    }

    [Fact]
    public void Serialize_roundtrips_TryParseProfile()
    {
        Profile profile = LabProfile(winget: ["jqlang.jq"], scoop: ["curl"]);
        byte[] utf8 = BuildPlan.SerializeProfile(profile);
        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(utf8);
        Assert.True(parsed.IsOk);
        Assert.Equal(profile.WingetPackages, parsed.Value.WingetPackages);
        Assert.Equal(profile.ScoopPackages, parsed.Value.ScoopPackages);
        Assert.Equal(profile.Account.Username, parsed.Value.Account.Username);
    }

    [Fact]
    public void FromMultiline_newline_trim_drops_blanks()
    {
        IReadOnlyList<string> ids = IdList.FromMultiline("  jqlang.jq\n\ncurl  \r\n\n");
        Assert.Equal(["jqlang.jq", "curl"], ids);
        Assert.Empty(IdList.FromMultiline(null));
        Assert.Empty(IdList.FromMultiline("  \n  "));
    }
}
