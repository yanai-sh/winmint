using WinMint.Orchestrator;
using WinMint.Wizard;

namespace WinMint.Tests;

/// <summary>Issue #95 — Avalonia-free Included receipt text layers (ADR-009 quiet vs recommended strip).</summary>
public class IncludedReceiptTests
{
    [Fact]
    public void FormatQuietBlock_always_lists_product_constants()
    {
        string text = IncludedReceipt.FormatQuietBlock(keepCopilot: true, braveSelected: false);

        Assert.Contains("Edge policies", text, StringComparison.Ordinal);
        Assert.Contains("OneDrive", text, StringComparison.Ordinal);
        Assert.Contains("device metadata", text, StringComparison.Ordinal);
        Assert.Contains("WPBT", text, StringComparison.Ordinal);
        Assert.Contains("Reserved Storage", text, StringComparison.Ordinal);
    }

    [Fact]
    public void FormatQuietBlock_adds_copilot_off_only_when_not_kept()
    {
        string kept = IncludedReceipt.FormatQuietBlock(keepCopilot: true, braveSelected: false);
        string stripped = IncludedReceipt.FormatQuietBlock(keepCopilot: false, braveSelected: false);

        Assert.DoesNotContain("Copilot off", kept, StringComparison.Ordinal);
        Assert.Contains("Copilot off", stripped, StringComparison.Ordinal);
    }

    [Fact]
    public void FormatQuietBlock_adds_brave_only_when_selected()
    {
        string without = IncludedReceipt.FormatQuietBlock(keepCopilot: true, braveSelected: false);
        string withBrave = IncludedReceipt.FormatQuietBlock(keepCopilot: true, braveSelected: true);

        Assert.DoesNotContain("Brave", without, StringComparison.Ordinal);
        Assert.Contains("Brave policies", withBrave, StringComparison.Ordinal);
    }

    [Fact]
    public void FormatQuietBlock_does_not_list_recommended_appx_names()
    {
        string text = IncludedReceipt.FormatQuietBlock(keepCopilot: false, braveSelected: true);

        Assert.DoesNotContain("Bing Weather", text, StringComparison.Ordinal);
        Assert.DoesNotContain("Solitaire", text, StringComparison.Ordinal);
        Assert.DoesNotContain("Microsoft.BingWeather", text, StringComparison.Ordinal);
    }

    [Fact]
    public void FriendlyRemoveNames_maps_known_recommended_appx_ids()
    {
        IReadOnlyList<string> names = IncludedReceipt.FriendlyRemoveNames(
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
        IReadOnlyList<string> names = IncludedReceipt.FriendlyRemoveNames(["Contoso.UnknownApp"]);

        Assert.Equal(["UnknownApp"], names);
    }

    [Fact]
    public void FormatWhatsIncluded_joins_friendly_names()
    {
        string text = IncludedReceipt.FormatWhatsIncluded(["Microsoft.BingNews", "Microsoft.Todos"]);

        Assert.Equal("Bing News · To Do", text);
    }

    [Fact]
    public void FormatPickStrip_joins_labels_with_middle_dot()
    {
        string text = IncludedReceipt.FormatPickStrip(["VS Code", "Brave", "Gaming kept"]);

        Assert.Equal("VS Code · Brave · Gaming kept", text);
    }

    [Fact]
    public void FormatPickStrip_empty_returns_empty()
    {
        Assert.Equal(string.Empty, IncludedReceipt.FormatPickStrip([]));
        Assert.Equal(string.Empty, IncludedReceipt.FormatPickStrip(null!));
    }

    [Fact]
    public void FormatQuietSummary_counts_stripped_apps()
    {
        Result<KeepFlagExpansion, PlanFailure> expansion =
            KeepFlagPresets.TryExpand(KeepFlagPresets.Recommended);

        Assert.True(expansion.IsOk);

        string summary = IncludedReceipt.FormatQuietSummary(
            expansion.Value.RemoveProvisionedAppx.Count,
            keepCopilot: false,
            keepGaming: false);

        Assert.Contains("strips", summary, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("21", summary, StringComparison.Ordinal);
    }
}
