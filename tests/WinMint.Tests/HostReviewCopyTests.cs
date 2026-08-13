using WinMint.Contracts;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class HostReviewCopyTests
{
    [Fact]
    public void QuietBlock_always_lists_product_constants()
    {
        Result<HostPlan, HostComposeError> planned = HostCompile.PlanDocument(Lab());
        Assert.True(planned.IsOk, planned.IsOk ? null : planned.Error.Message);
        string text = planned.Value.Review.QuietBlock;

        Assert.Contains("Edge policies", text, StringComparison.Ordinal);
        Assert.Contains("OneDrive", text, StringComparison.Ordinal);
        Assert.Contains("device metadata", text, StringComparison.Ordinal);
        Assert.Contains("Widgets off", text, StringComparison.Ordinal);
        Assert.Contains("consumer features off", text, StringComparison.Ordinal);
        Assert.Contains("Store suggested apps off", text, StringComparison.Ordinal);
        Assert.Contains("Reserved Storage", text, StringComparison.Ordinal);
        Assert.Contains("MinGit", text, StringComparison.Ordinal);
        Assert.Contains("PowerShell 7", text, StringComparison.Ordinal);
        Assert.Contains("Windows Terminal", text, StringComparison.Ordinal);
        Assert.Contains("Nilesoft Shell", text, StringComparison.Ordinal);
        Assert.Contains("Starship + scoop CLI", text, StringComparison.Ordinal);
        Assert.Contains("shell skel stamp", text, StringComparison.Ordinal);
        Assert.DoesNotContain("Copilot off", text, StringComparison.Ordinal);
        Assert.DoesNotContain("Brave", text, StringComparison.Ordinal);
    }

    [Fact]
    public void QuietBlock_adds_brave_only_when_selected()
    {
        Result<HostPlan, HostComposeError> without = HostCompile.PlanDocument(Lab());
        Result<HostPlan, HostComposeError> withBrave =
            HostCompile.PlanDocument(Lab(winget: [ProductPosture.BraveWingetId]));
        Assert.True(without.IsOk);
        Assert.True(withBrave.IsOk);

        Assert.DoesNotContain("Brave", without.Value.Review.QuietBlock, StringComparison.Ordinal);
        Assert.Contains("Brave policies", withBrave.Value.Review.QuietBlock, StringComparison.Ordinal);
        Assert.DoesNotContain("Bing Weather", withBrave.Value.Review.QuietBlock, StringComparison.Ordinal);
        Assert.DoesNotContain("Solitaire", withBrave.Value.Review.QuietBlock, StringComparison.Ordinal);
    }

    [Fact]
    public void FriendlyRemoveNames_maps_known_recommended_appx_ids()
    {
        IReadOnlyList<string> names = PlanDiff.FriendlyRemoveNames(
        [
            "Microsoft.BingNews",
            "Microsoft.BingWeather",
            "Microsoft.MicrosoftSolitaireCollection",
            "Microsoft.YourPhone",
            "Microsoft.ZuneVideo",
        ]);

        Assert.Equal(
            ["Bing News", "Bing Weather", "Solitaire", "Phone Link", "Movies & TV"],
            names);
    }

    [Fact]
    public void FriendlyRemoveNames_falls_back_to_last_segment_for_unknown_ids()
    {
        Assert.Equal(["UnknownApp"], PlanDiff.FriendlyRemoveNames(["Contoso.UnknownApp"]));
    }

    [Fact]
    public void WhatsIncluded_joins_friendly_names()
    {
        Result<HostPlan, HostComposeError> planned = HostCompile.PlanDocument(Lab());
        Assert.True(planned.IsOk);
        Assert.Equal(
            "Bing News · To Do",
            (planned.Value.Review with
            {
                RemoveProvisionedAppx = ["Microsoft.BingNews", "Microsoft.Todos"],
            }).WhatsIncluded);
    }

    [Fact]
    public void PickStrip_joins_labels_with_middle_dot()
    {
        Result<HostPlan, HostComposeError> planned = HostCompile.PlanDocument(
            Lab(),
            new HostComposeOptions(AuthoredSelectionLabels: ["VS Code", "Brave"]));
        Assert.True(planned.IsOk);
        Assert.Equal("VS Code · Brave", planned.Value.Review.PickStrip);
    }

    [Fact]
    public void PickStrip_empty_returns_empty()
    {
        Result<HostPlan, HostComposeError> planned = HostCompile.PlanDocument(Lab());
        Assert.True(planned.IsOk);
        Assert.Equal(string.Empty, planned.Value.Review.PickStrip);
    }

    [Fact]
    public void QuietSummary_counts_stripped_apps()
    {
        Result<HostPlan, HostComposeError> planned = HostCompile.PlanDocument(Lab());
        Assert.True(planned.IsOk);
        Assert.Equal(
            "This build applies product defaults.",
            (planned.Value.Review with { RemoveProvisionedAppx = [] }).QuietSummary);
        Assert.Equal(
            "This build strips 5 apps.",
            (planned.Value.Review with
            {
                RemoveProvisionedAppx = ["a", "b", "c", "d", "e"],
            }).QuietSummary);
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
