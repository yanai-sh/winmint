using System.Text.Json;
using WinMint.Orchestrator;
using WinMint.Contracts;

namespace WinMint.Tests;

public class ProductPostureTests
{
    [Fact]
    public void MergeWinget_constants_first_then_profile_deduped()
    {
        IReadOnlyList<string> merged = ProductPosture.MergeWinget(
            ["Anysphere.Cursor", "Git.MinGit", "Nilesoft.Shell"]);

        Assert.Equal(
            [
                "Git.MinGit",
                "Microsoft.PowerShell",
                "Microsoft.WindowsTerminal",
                "Microsoft.Coreutils",
                "Nilesoft.Shell",
                "Anysphere.Cursor",
            ],
            merged);
    }

    [Fact]
    public void StripWingetFromAuthored_drops_product_constants()
    {
        string stripped = ProductPosture.StripWingetFromAuthored(
            "Git.MinGit\nAnysphere.Cursor\nMicrosoft.PowerShell\nNilesoft.Shell\njqlang.jq");

        Assert.Equal($"Anysphere.Cursor{Environment.NewLine}jqlang.jq", stripped);
    }

    [Fact]
    public void MergeScoop_constants_first_then_profile_deduped()
    {
        IReadOnlyList<string> merged = ProductPosture.MergeScoop(["neovim", "starship", "fzf"]);

        Assert.Equal(
            ["starship", "fzf", "fd", "ripgrep", "bat", "zoxide", "jq", "chezmoi", "neovim"],
            merged);
    }

    [Fact]
    public void StripScoopFromAuthored_drops_product_constants()
    {
        string stripped = ProductPosture.StripScoopFromAuthored("starship\nneovim\nfzf");

        Assert.Equal("neovim", stripped);
    }

    [Fact]
    public void UnionAppx_adds_copilot_and_gaming_when_missing()
    {
        IReadOnlyList<string> merged = ProductPosture.UnionAppx(["Microsoft.BingNews"]);

        Assert.Contains("Microsoft.Copilot", merged);
        Assert.Contains("Microsoft.GamingApp", merged);
        Assert.Contains("Microsoft.Xbox.TCUI", merged);
        Assert.Contains("Microsoft.XboxGamingOverlay", merged);
        Assert.Contains("Microsoft.XboxSpeechToTextOverlay", merged);
        Assert.Contains("Microsoft.BingNews", merged);
    }

    [Fact]
    public void UnionAppx_deduplicates_case_insensitively()
    {
        IReadOnlyList<string> merged = ProductPosture.UnionAppx(
            ["Microsoft.Copilot", "microsoft.gamingapp"]);

        Assert.Equal(1, merged.Count(id => string.Equals(id, "Microsoft.Copilot", StringComparison.OrdinalIgnoreCase)));
        Assert.Equal(1, merged.Count(id => string.Equals(id, "Microsoft.GamingApp", StringComparison.OrdinalIgnoreCase)));
    }

    [Fact]
    public void Plan_never_stamps_copilot_kill_policies()
    {
        Profile profile = Lab();

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);

        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        string specs = Assert.Single(
            planned.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.StampOfflinePolicies).Parameters[StageParams.PolicySpecs];
        Assert.DoesNotContain("TurnOffWindowsCopilot", specs, StringComparison.Ordinal);
        Assert.DoesNotContain("HubsSidebarEnabled", specs, StringComparison.Ordinal);
    }

    [Fact]
    public void Plan_empty_winget_still_emits_mingit_and_nilesoft_import_on_arm64()
    {
        Profile profile = Lab(winget: []);
        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "arm64" });

        Assert.True(result.IsOk, result.IsOk ? null : result.Error.Message);
        Assert.NotNull(result.Value.WingetImportJson);
        Assert.Contains(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.WingetImport);
        Assert.True(result.Value.Manifest.RequiresNetwork);

        using JsonDocument doc = JsonDocument.Parse(result.Value.WingetImportJson!);
        string[] ids = doc.RootElement.GetProperty("Sources")[0].GetProperty("Packages")
            .EnumerateArray()
            .Select(p => p.GetProperty("PackageIdentifier").GetString()!)
            .ToArray();
        Assert.Equal(
            [
                "Git.MinGit",
                "Microsoft.PowerShell",
                "Microsoft.WindowsTerminal",
                "Microsoft.Coreutils",
                "Nilesoft.Shell",
            ],
            ids);
    }

    [Fact]
    public void Plan_empty_scoop_still_emits_shell_core_scoop_batch()
    {
        Profile profile = Lab(winget: []);
        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "arm64" });

        Assert.True(result.IsOk, result.IsOk ? null : result.Error.Message);
        JobDescriptor batch = Assert.Single(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.ScoopBatch);
        foreach (string id in ProductPosture.ScoopIds)
        {
            Assert.Contains(id, batch.PackageId!, StringComparison.OrdinalIgnoreCase);
        }
    }

    private static Profile Lab(IReadOnlyList<string>? winget = null) =>
        new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget(true, "en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            [],
            winget ?? [],
            [],
            [],
            [],
            [],
            [],
            [],
            []);
}
