using System.Text;
using System.Text.Json;
using WinMint.Orchestrator;
using WinMint.Contracts;

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
            DebloatMode.Online,
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
    public void Serialize_winget_and_scoop_plans_package_jobs()
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

        Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile(utf8);
        Assert.True(parsed.IsOk, parsed.IsOk ? null : string.Join("; ", parsed.Error.Select(i => i.Code)));

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(
            parsed.Value,
            new RunOptions { ImageArchitecture = "amd64" });
        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        Assert.Contains(
            planned.Value.Jobs.Jobs,
            j => j.Kind == ProvisionJobKind.Winget && j.PackageId == "jqlang.jq" && j.NeedsReboot);
        Assert.Contains(
            planned.Value.Jobs.Jobs,
            j => j.Kind == ProvisionJobKind.ScoopBatch && j.PackageId!.Contains("curl") && !j.NeedsReboot);
    }

    [Fact]
    public void Serialize_empty_packages_omits_packages_object()
    {
        byte[] utf8 = BuildPlan.SerializeProfile(LabProfile());

        string json = Encoding.UTF8.GetString(utf8);
        Assert.DoesNotContain("\"packages\"", json, StringComparison.Ordinal);

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(BuildPlan.TryParseProfile(utf8).Value);
        Assert.True(planned.IsOk);
        Assert.DoesNotContain(planned.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.Stub);
        Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.OneDriveUninstall);
        Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.ReservedStorageDisable);
        Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.WingetImport);
        Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.ScoopBatch);
        Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.ShellStamp);
        Assert.DoesNotContain(planned.Value.Jobs.Jobs, j => j.Kind is ProvisionJobKind.Scoop or ProvisionJobKind.Wsl);
    }

    [Fact]
    public void Serialize_wingetNeedsReboot_not_in_winget_fails_plan()
    {
        Profile profile = LabProfile(winget: ["jqlang.jq"], wingetNeedsReboot: ["Microsoft.VisualStudioCode"]);

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);
        Assert.False(planned.IsOk);
        Assert.Equal("packages.wingetNeedsReboot.unknown", planned.Error.Code);
    }

    [Fact]
    public void Serialize_scoopNeedsReboot_not_in_scoop_fails_plan()
    {
        Profile profile = LabProfile(scoop: ["curl"], scoopNeedsReboot: ["7zip"]);

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);
        Assert.False(planned.IsOk);
        Assert.Equal("packages.scoopNeedsReboot.unknown", planned.Error.Code);
    }

    [Fact]
    public void Serialize_roundtrips_TryParseProfile()
    {
        Profile profile = LabProfile(winget: ["jqlang.jq"], scoop: ["curl"]);
        byte[] utf8 = BuildPlan.SerializeProfile(profile);
        Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile(utf8);
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
