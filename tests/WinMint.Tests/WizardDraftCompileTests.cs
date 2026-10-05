using WinMint.Orchestrator;

namespace WinMint.Tests;

public class WizardDraftCompileTests
{
    [Fact]
    public void TryCompile_shipping_pins_are_release_and_from_lane()
    {
        Result<WizardDraft, Failure> draft = WizardDraftCompile.TryCompile(LabRequest());
        Assert.True(draft.IsOk, draft.IsOk ? null : draft.Error.Message);

        HostComposeOptions options = draft.Value.Options;
        Assert.Equal(ImageQualityLane.Release, options.ImageQuality);
        Assert.Equal(PackageStrictOverride.FromLane, options.PackageStrict);
        Assert.Equal(WizardDraftCompile.ShippingProfileName, options.ProfileName);
        Assert.True(HostDefaults.ResolvePackageStrict(options.ImageQuality, options.PackageStrict));
    }

    [Fact]
    public void TryCompile_remove_lists_follow_station_seed_not_chip_refine()
    {
        Result<StationSeed, Failure> comfort = StationOutcomes.TrySeed(StationOutcomes.Comfort);
        Assert.True(comfort.IsOk);

        Result<WizardDraft, Failure> draft = WizardDraftCompile.TryCompile(
            LabRequest() with
            {
                StationOutcome = StationOutcomes.Comfort,
                Packages = new PackageSelection([], [], []),
            });
        Assert.True(draft.IsOk);
        Assert.Equal(comfort.Value.RemoveProvisionedAppx, draft.Value.Profile.RemoveProvisionedAppx);
        Assert.Empty(draft.Value.Profile.WingetPackages);
    }

    [Fact]
    public void TryCompile_merges_advanced_winget_ids()
    {
        Result<WizardDraft, Failure> draft = WizardDraftCompile.TryCompile(
            LabRequest() with
            {
                Packages = new PackageSelection(["Anysphere.Cursor"], [], []),
                AdvancedWinget = "Extra.Id\nAnysphere.Cursor",
            });
        Assert.True(draft.IsOk);
        Assert.Equal(["Anysphere.Cursor", "Extra.Id"], draft.Value.Profile.WingetPackages);
    }

    [Fact]
    public void TryCompile_bad_geo_id_fails()
    {
        Result<WizardDraft, Failure> draft = WizardDraftCompile.TryCompile(
            LabRequest() with { GeoId = "nope" });
        Assert.False(draft.IsOk);
        Assert.Equal("dma.settle.geoId", draft.Error.Code);
    }

    private static WizardDraftRequest LabRequest() =>
        new(
            Username: "winmint",
            Password: "lab-only",
            RequireWifi: false,
            DmaEnabled: true,
            Locale: "en-US",
            GeoId: "244",
            TimeZoneId: "UTC",
            LocationServices: true,
            StationOutcome: StationOutcomes.Comfort,
            Packages: new PackageSelection(["Anysphere.Cursor"], [], ["FedoraLinux"]),
            AdvancedWinget: null,
            AdvancedScoop: null,
            AdvancedWsl: null,
            SourceIsoPath: @"C:\iso\source.iso",
            WimIndex: 1,
            SelectionLabels: ["Windows taskbar", "Cursor"]);
}
