using System.Text;
using WinMint.Orchestrator;
using WinMint.Contracts;

namespace WinMint.Tests;

/// <summary>Ticket 15 / 25 / issue 56 — host-side Debloat presets expand to remove-lists (not in Profile JSON).</summary>
public class DebloatPresetTests
{
    [Fact]
    public void Expand_acceptance_returns_pinned_acceptance_ids()
    {
        Result<DebloatExpansion, Failure> result = DebloatPresets.TryExpand("acceptance");

        Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
        Assert.Equal(
            ["Microsoft.BingNews", "Microsoft.BingWeather"],
            result.Value.RemoveProvisionedAppx);
        Assert.Equal(
            ["App.StepsRecorder~~~~0.0.1.0", "WMIC~~~~"],
            result.Value.RemoveCapabilities);
        Assert.Equal(["WorkFolders-Client"], result.Value.DisableOptionalFeatures);
    }

    [Fact]
    public void Expand_empty_returns_no_ids()
    {
        Result<DebloatExpansion, Failure> result = DebloatPresets.TryExpand("empty");

        Assert.True(result.IsOk);
        Assert.Empty(result.Value.RemoveProvisionedAppx);
        Assert.Empty(result.Value.RemoveCapabilities);
        Assert.Empty(result.Value.DisableOptionalFeatures);
    }

    [Fact]
    public void Expand_unknown_preset_fails()
    {
        Result<DebloatExpansion, Failure> result = DebloatPresets.TryExpand("not-a-preset");

        Assert.False(result.IsOk);
        Assert.Equal("debloat.preset.unknown", result.Error.Code);
        Assert.Contains("not-a-preset", result.Error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Expand_recommended_returns_curated_ids()
    {
        Result<DebloatExpansion, Failure> result = DebloatPresets.TryExpand(DebloatPresets.Recommended);

        Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
        Assert.Equal(
            [
                "Microsoft.BingNews",
                "Microsoft.BingWeather",
                "Microsoft.GetHelp",
                "Microsoft.Getstarted",
                "Microsoft.MicrosoftOfficeHub",
                "Microsoft.MicrosoftSolitaireCollection",
                "Microsoft.People",
                "Microsoft.PowerAutomateDesktop",
                "Microsoft.Todos",
                "Microsoft.WindowsAlarms",
                "Microsoft.WindowsFeedbackHub",
                "Microsoft.WindowsMaps",
                "Microsoft.YourPhone",
                "Microsoft.ZuneMusic",
                "Microsoft.ZuneVideo",
                "MicrosoftCorporationII.QuickAssist",
            ],
            result.Value.RemoveProvisionedAppx);
        Assert.Equal(
            [
                "App.StepsRecorder~~~~0.0.1.0",
                "WMIC~~~~",
                "VBSCRIPT~~~~",
                "Browser.InternetExplorer~~~~0.0.11.0",
                "Microsoft.Windows.PowerShell.ISE~~~~0.0.1.0",
                "Microsoft.Wallpapers.Extended~~~~0.0.1.0",
                "Media.WindowsMediaPlayer~~~~0.0.12.0",
            ],
            result.Value.RemoveCapabilities);
        Assert.Equal(
            [
                "WorkFolders-Client",
                "WindowsMediaPlayer",
                "TelnetClient",
                "TFTP",
                "SimpleTCP",
            ],
            result.Value.DisableOptionalFeatures);
        Assert.DoesNotContain("MathRecognizer~~~~0.0.1.0", result.Value.RemoveCapabilities);
        Assert.DoesNotContain("Print.Management.Console~~~~0.0.1.0", result.Value.RemoveCapabilities);
    }

    [Fact]
    public void Expand_recommended_leaves_product_required_appx_to_posture()
    {
        Result<DebloatExpansion, Failure> result =
            DebloatPresets.TryExpand(DebloatPresets.Recommended);

        Assert.True(result.IsOk);
        Assert.DoesNotContain("Microsoft.GamingApp", result.Value.RemoveProvisionedAppx);
        Assert.DoesNotContain("Microsoft.Copilot", result.Value.RemoveProvisionedAppx);
        Assert.Equal(
            ProductPosture.AppxIds,
            ProductPosture.UnionAppx(result.Value.RemoveProvisionedAppx)
                .Where(id => ProductPosture.AppxIds.Contains(id, StringComparer.OrdinalIgnoreCase))
                .ToArray());
    }

    [Fact]
    public void Compose_acceptance_preset_parses_and_plans()
    {
        Result<DebloatExpansion, Failure> expanded = DebloatPresets.TryExpand(DebloatPresets.Acceptance);
        Assert.True(expanded.IsOk);

        Profile profile = new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget(true, "en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            expanded.Value.RemoveProvisionedAppx,
            [],
            [],
            [],
            [],
            [],
            [],
            expanded.Value.RemoveCapabilities,
            expanded.Value.DisableOptionalFeatures);

        byte[] utf8 = BuildPlan.SerializeProfile(profile);

        // Preset name must not appear in Profile JSON (host expands only).
        string json = Encoding.UTF8.GetString(utf8);
        Assert.DoesNotContain("\"preset\"", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("acceptance", json, StringComparison.OrdinalIgnoreCase);

        Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile(utf8);
        Assert.True(parsed.IsOk, parsed.IsOk ? null : string.Join("; ", parsed.Error.Select(i => i.Code)));
        Assert.Equal(["Microsoft.BingNews", "Microsoft.BingWeather"], parsed.Value.RemoveProvisionedAppx);
        Assert.Equal(
            ["App.StepsRecorder~~~~0.0.1.0", "WMIC~~~~"],
            parsed.Value.RemoveCapabilities);
        Assert.Equal(["WorkFolders-Client"], parsed.Value.DisableOptionalFeatures);

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(parsed.Value);
        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.AppxSafetyNet);
        Assert.DoesNotContain(
            planned.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.RemoveProvisionedAppx);
        Assert.Contains(
            planned.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.RemoveCapabilities);
        Assert.Contains(
            planned.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.DisableOptionalFeatures);
    }

    [Fact]
    public void Compose_recommended_serialize_has_no_preset_name()
    {
        Result<DebloatExpansion, Failure> expanded =
            DebloatPresets.TryExpand(DebloatPresets.Recommended);
        Assert.True(expanded.IsOk);

        Profile profile = new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget(true, "en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            expanded.Value.RemoveProvisionedAppx,
            [],
            [],
            [],
            [],
            [],
            [],
            expanded.Value.RemoveCapabilities,
            expanded.Value.DisableOptionalFeatures);

        string json = Encoding.UTF8.GetString(BuildPlan.SerializeProfile(profile));
        Assert.DoesNotContain("\"preset\"", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("recommended", json, StringComparison.OrdinalIgnoreCase);

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
    }

    [Fact]
    public void Compose_empty_preset_plans_without_remove_stage()
    {
        Result<DebloatExpansion, Failure> expanded = DebloatPresets.TryExpand(DebloatPresets.Empty);
        Assert.True(expanded.IsOk);

        Profile profile = new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget(true, "en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            expanded.Value.RemoveProvisionedAppx,
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            []);

        byte[] utf8 = BuildPlan.SerializeProfile(profile);

        Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile(utf8);
        Assert.True(parsed.IsOk);
        Assert.Empty(parsed.Value.RemoveProvisionedAppx);

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(parsed.Value);
        Assert.True(planned.IsOk);
        Assert.DoesNotContain(
            planned.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.RemoveProvisionedAppx);
    }

    [Fact]
    public void Acceptance_sample_profile_debloat_matches_DebloatPresets_Acceptance()
    {
        Result<DebloatExpansion, Failure> expanded = DebloatPresets.TryExpand(DebloatPresets.Acceptance);
        Assert.True(expanded.IsOk, expanded.IsOk ? null : $"{expanded.Error.Code}: {expanded.Error.Message}");

        string samplePath = Path.Combine(FindRepoRoot(), "samples", "acceptance.profile.json");
        byte[] utf8 = File.ReadAllBytes(samplePath);
        string json = Encoding.UTF8.GetString(utf8);
        Assert.DoesNotContain("\"preset\"", json, StringComparison.OrdinalIgnoreCase);

        Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile(utf8);
        Assert.True(parsed.IsOk, parsed.IsOk ? null : string.Join("; ", parsed.Error.Select(i => i.Code)));

        Assert.Equal(expanded.Value.RemoveProvisionedAppx, parsed.Value.RemoveProvisionedAppx);
        Assert.Equal(expanded.Value.RemoveCapabilities, parsed.Value.RemoveCapabilities);
        Assert.Equal(expanded.Value.DisableOptionalFeatures, parsed.Value.DisableOptionalFeatures);
    }

    [Fact]
    public void Sl7_sample_matches_recommended_and_plans_packages()
    {
        Result<DebloatExpansion, Failure> expanded =
            DebloatPresets.TryExpand(DebloatPresets.Recommended);
        Assert.True(expanded.IsOk);

        string root = FindRepoRoot();
        string scratch = Path.Combine(root, ".scratch");
        Directory.CreateDirectory(scratch);
        string pwFile = Path.Combine(scratch, "sl7.password");
        File.WriteAllText(pwFile, "lab-only-sl7");

        string samplePath = Path.Combine(root, "samples", "sl7.profile.json");
        byte[] utf8 = File.ReadAllBytes(samplePath);
        string json = Encoding.UTF8.GetString(utf8);
        Assert.DoesNotContain("\"preset\"", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("\"password\"", json, StringComparison.Ordinal);
        Assert.Contains("../.scratch/sl7.password", json, StringComparison.Ordinal);

        Result<Profile, IReadOnlyList<DocumentError>> parsed = ProfileFile.TryLoad(samplePath);
        Assert.True(parsed.IsOk, parsed.IsOk ? null : string.Join("; ", parsed.Error.Select(i => i.Code)));
        Assert.Equal("yanai", parsed.Value.Account.Username);
        Assert.Equal("lab-only-sl7", parsed.Value.Account.Password);
        Assert.Equal(
            ProductPosture.UnionAppx(expanded.Value.RemoveProvisionedAppx),
            parsed.Value.RemoveProvisionedAppx);
        Assert.Equal(expanded.Value.RemoveCapabilities, parsed.Value.RemoveCapabilities);
        Assert.Equal(expanded.Value.DisableOptionalFeatures, parsed.Value.DisableOptionalFeatures);
        Assert.Equal(
            ["Anysphere.Cursor", "Zen-Team.Zen-Browser"],
            parsed.Value.WingetPackages);
        Assert.Equal(
            ["Git.MinGit", "Nilesoft.Shell", "Anysphere.Cursor", "Zen-Team.Zen-Browser"],
            ProductPosture.MergeWinget(parsed.Value.WingetPackages));
        Assert.Equal(["FedoraLinux"], parsed.Value.WslDistros);

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(parsed.Value);
        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.WingetImport);
        Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.Wsl);
        Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.AppxSafetyNet);
        Assert.DoesNotContain(
            planned.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.RemoveProvisionedAppx);
        Assert.Contains(planned.Value.RemoveProvisionedAppx, id => id == "Microsoft.Copilot");
        Assert.Contains(planned.Value.RemoveProvisionedAppx, id => id == "Microsoft.GamingApp");
        Assert.Contains(
            planned.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.RemoveCapabilities);
        Assert.Contains(
            planned.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.DisableOptionalFeatures);
    }

    private static string FindRepoRoot()
    {
        string? dir = AppContext.BaseDirectory;
        while (dir is not null)
        {
            if (File.Exists(Path.Combine(dir, "Justfile"))
                && Directory.Exists(Path.Combine(dir, "samples")))
            {
                return dir;
            }

            dir = Directory.GetParent(dir)?.FullName;
        }

        throw new InvalidOperationException("Repo root not found from test BaseDirectory.");
    }
}
