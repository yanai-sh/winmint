using System.Text.Json;

using WinMint.Contracts;
using WinMint.Orchestrator;
using WinMint.Provisioning;

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
    public void UnionAppx_includes_v1_default_groups_and_whatsapp_and_drops_clock()
    {
        IReadOnlyList<string> merged = ProductPosture.UnionAppx(["Microsoft.WindowsAlarms", "Microsoft.BingNews"]);

        Assert.DoesNotContain("Microsoft.WindowsAlarms", merged);
        Assert.Contains("Microsoft.BingNews", merged);
        Assert.Contains("Clipchamp.Clipchamp", merged);
        Assert.Contains("Microsoft.OutlookForWindows", merged);
        Assert.Contains("MicrosoftWindows.Client.WebExperience", merged);
        Assert.Contains("Microsoft.WindowsCalculator", merged);
        Assert.Contains("MSTeams", merged);
        Assert.Contains("5319275A.WhatsAppDesktop", merged);
        Assert.Contains("LinkedInforWindows", merged);
        Assert.Contains("SpotifyAB.SpotifyMusic", merged);
        Assert.Contains("4DF9E0F8.Netflix", merged);
        Assert.Contains("AD2F1837.HPWelcome", merged);
        Assert.DoesNotContain("Microsoft.WindowsStore", merged);
        Assert.DoesNotContain("Microsoft.WindowsCamera", merged);
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
    public void ComposePolicies_declares_family_on_each_row_so_digest_is_never_inferred()
    {
        IReadOnlyList<OfflinePolicyRow> rows = ProductPosture.ComposePolicies(
            includeBraveDebloat: true,
            includeDriverHygiene: true);

        Assert.All(rows, row => Assert.False(string.IsNullOrWhiteSpace(row.Family)));
        Assert.All(rows, row => Assert.Equal($"policy.{row.Family}.{row.Name}", row.Digest));

        string[] digestKeys = [.. rows.Select(static row => row.Digest)];

        // A new row falling through to the "edge" default shows up as a missing family here.
        Assert.Equal(
            [
                "brave",
                "cloudContent",
                "developer",
                "device",
                "deviceInstaller",
                "edge",
                "filesystem",
                "fonts",
                "onedrive",
                "search",
                "start",
                "store",
                "sudo",
                "taskbar",
                "widgets",
                "wpbt",
            ],
            [.. digestKeys.Select(key => key.Split('.')[1])
                .Distinct(StringComparer.Ordinal)
                .Order(StringComparer.Ordinal)]);

        // Keys the apply/smoke gates assert on by literal (tools/apply/Assert-ApplyEvidence.ps1).
        Assert.Contains("policy.cloudContent.DisableWindowsConsumerFeatures", digestKeys);
        Assert.Contains("policy.cloudContent.DisableSoftLanding", digestKeys);
        Assert.Contains("policy.store.AutoDownload", digestKeys);
        Assert.Contains("policy.wpbt.DisableWpbtExecution", digestKeys);
        Assert.Contains("policy.filesystem.LongPathsEnabled", digestKeys);
        Assert.Contains("policy.deviceInstaller.DisableCoInstallers", digestKeys);
        Assert.Contains("policy.taskbar.LayoutXMLPath", digestKeys);
        Assert.Contains("policy.onedrive.DisableFileSyncNGSC", digestKeys);
        Assert.Contains("policy.onedrive.PreventNetworkTrafficPreUserSignIn", digestKeys);
        Assert.Equal("AllowNewsAndInterests", rows[0].Name);
        Assert.Equal("ConfigureStartPins", rows[1].Name);
        Assert.Equal(GuestChrome.StartPinsBaselineJson, rows[1].Data);
        Assert.Contains(
            rows,
            static row => row.Name == "LayoutXMLPath" && row.Data == GuestChrome.TaskbarLayoutOemGuestPath);
    }

    [Fact]
    public void ComposeDefaultUserRows_matches_quiet_overlay_and_omits_policies()
    {
        IReadOnlyList<OfflinePolicyRow> rows = ProductPosture.ComposeDefaultUserRows();
        Assert.NotEmpty(rows);
        Assert.All(rows, static row => Assert.Equal("NTUSER", row.Hive));
        Assert.All(
            rows,
            static row => Assert.DoesNotContain("Policies", row.SubKey, StringComparison.OrdinalIgnoreCase));

        foreach ((string name, int value) in Win32WorkstationQuiet.ExplorerAdvancedDwords)
        {
            if (name is "TaskbarDa" or "TaskbarMn" or "ShowTaskViewButton" or "ShowCopilotButton")
            {
                Assert.DoesNotContain(rows, row => row.Name == name);
                continue;
            }

            Assert.Contains(
                rows,
                row => row.Name == name
                    && row.Data == value.ToString(System.Globalization.CultureInfo.InvariantCulture)
                    && row.RegType == "REG_DWORD");
        }

        foreach (string name in Win32WorkstationQuiet.ContentDeliveryManagerDwords)
        {
            Assert.Contains(rows, row => row.Name == name && row.Data == "0");
        }

        Assert.Contains(
            rows,
            row => row.Name == "Wallpaper" && row.Data == GuestChrome.BloomWallpaperPath);
        Assert.Contains(rows, row => row.Name == "TileWallpaper" && row.Data == "0");
        Assert.Equal(GuestChrome.BloomWallpaperPath, ShellChromeLayout.WallpaperPath);
    }

    [Fact]
    public void Plan_emits_default_user_opcode_after_payload()
    {
        Profile profile = Lab();

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);

        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        IReadOnlyList<ServicingOpcode> stages = planned.Value.Stages;
        int payloadAt = stages.ToList().IndexOf(ServicingOpcode.StagePayload);
        int defaultUserAt = stages.ToList().IndexOf(ServicingOpcode.StampOfflineDefaultUser);
        int oobeAt = stages.ToList().IndexOf(ServicingOpcode.StageOobeUnattend);
        Assert.True(payloadAt >= 0 && defaultUserAt == payloadAt + 1 && oobeAt == defaultUserAt + 1);
        Assert.NotEmpty(planned.Value.OfflineDefaultUser);
        Assert.All(
            planned.Value.OfflineDefaultUser,
            static row => Assert.DoesNotContain("Policies", row.SubKey, StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Plan_never_stamps_copilot_kill_policies()
    {
        Profile profile = Lab();

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);

        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        Assert.Contains(ServicingOpcode.StampOfflinePolicies, planned.Value.Stages);
        Assert.DoesNotContain(planned.Value.OfflinePolicies, static row => row.Name == "TurnOffWindowsCopilot");
        Assert.DoesNotContain(planned.Value.OfflinePolicies, static row => row.Name == "HubsSidebarEnabled");
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
        string[] ids = [.. doc.RootElement.GetProperty("Sources")[0].GetProperty("Packages")
            .EnumerateArray()
            .Select(p => p.GetProperty("PackageIdentifier").GetString()!)];
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
        ProvisionJob batch = Assert.Single(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.ScoopBatch);
        foreach (string id in ProductPosture.ScoopIds)
        {
            Assert.Contains(id, batch.PackageId!, StringComparison.OrdinalIgnoreCase);
        }
    }

    private static Profile Lab(IReadOnlyList<string>? winget = null) =>
        new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true)),
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
