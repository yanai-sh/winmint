using WinMint.Orchestrator;

namespace WinMint.Tests;

public class ChipAxisResolveTests
{
    [Fact]
    public void Yasb_taskbar_injects_yasb_package()
    {
        Result<ChipAxisResolution, Failure> result = ChipAxisResolve.TryResolve(
            [],
            [],
            StationOutcomes.TaskbarYasb,
            komorebi: false);

        Assert.True(result.IsOk);
        Assert.Contains("AmN.yasb", result.Value.Packages.WingetInstallIds);
        Assert.Equal("YASB + tHide", result.Value.SelectionLabels[0]);
    }

    [Fact]
    public void Komorebi_injects_komorebi_and_whkd()
    {
        Result<ChipAxisResolution, Failure> result = ChipAxisResolve.TryResolve(
            [],
            [],
            StationOutcomes.TaskbarWindows,
            komorebi: true);

        Assert.True(result.IsOk);
        Assert.Contains("LGUG2Z.komorebi", result.Value.Packages.WingetInstallIds);
        Assert.Contains("LGUG2Z.whkd", result.Value.Packages.WingetInstallIds);
        Assert.Equal(["Windows taskbar", "Komorebi"], result.Value.SelectionLabels);
    }

    [Fact]
    public void Windows_without_komorebi_injects_no_desktop_axis_packages()
    {
        Result<ChipAxisResolution, Failure> result = ChipAxisResolve.TryResolve(
            [],
            [],
            StationOutcomes.TaskbarWindows,
            komorebi: false);

        Assert.True(result.IsOk);
        Assert.Empty(result.Value.Packages.WingetInstallIds);
        Assert.Empty(result.Value.Packages.ScoopInstallIds);
        Assert.Equal(["Windows taskbar"], result.Value.SelectionLabels);
    }

    [Fact]
    public void Non_package_tool_key_is_filtered_from_resolve()
    {
        Result<ChipAxisResolution, Failure> result = ChipAxisResolve.TryResolve(
            ["edge", "cursor"],
            [],
            StationOutcomes.TaskbarWindows,
            komorebi: false);

        Assert.True(result.IsOk);
        Assert.Equal(["Anysphere.Cursor"], result.Value.Packages.WingetInstallIds);
        Assert.Equal(["Windows taskbar", "Edge", "Cursor"], result.Value.SelectionLabels);
    }

    [Fact]
    public void Unknown_tool_key_fails_via_catalog()
    {
        Result<ChipAxisResolution, Failure> result = ChipAxisResolve.TryResolve(
            ["not-a-real-chip"],
            [],
            StationOutcomes.TaskbarWindows,
            komorebi: false);

        Assert.False(result.IsOk);
        Assert.Equal("packages.catalog.unknown", result.Error.Code);
    }

    [Fact]
    public void Comfort_like_keys_match_Station_label_order()
    {
        Result<ChipAxisResolution, Failure> result = ChipAxisResolve.TryResolve(
            ["cursor", "zen-browser"],
            ["FedoraLinux"],
            StationOutcomes.TaskbarWindows,
            komorebi: false);

        Assert.True(result.IsOk);
        Assert.Equal(
            ["Anysphere.Cursor", "Zen-Team.Zen-Browser"],
            result.Value.Packages.WingetInstallIds);
        Assert.Equal(["FedoraLinux"], result.Value.Packages.WslProfileTokens);
        Assert.Equal(
            ["Windows taskbar", "Cursor", "Zen", "Fedora 44"],
            result.Value.SelectionLabels);
    }
}
