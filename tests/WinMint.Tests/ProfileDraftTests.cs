using WinMint.Contracts;
using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>Issue #151 — shared Profile assembly from outcome seed + account + DMA + packages.</summary>
public class ProfileDraftTests
{
    [Fact]
    public void TryBuild_Comfort_seed_packages_match_curated_software_slice()
    {
        Result<StationSeed, Failure> comfort = StationOutcomes.TrySeed(StationOutcomes.Comfort);
        Assert.True(comfort.IsOk);

        DmaProfile dma = new(true, new DmaSettleTarget("en-US", 244, "Pacific Standard Time", true));
        AccountProfile account = new("winmint", "bootstrap-secret", true);

        Result<Profile, Failure> built = ProfileDraft.TryBuild(
            StationOutcomes.Comfort,
            account,
            dma,
            comfort.Value.Packages);
        Assert.True(built.IsOk, built.IsOk ? null : $"{built.Error.Code}: {built.Error.Message}");

        Profile profile = built.Value;
        Assert.Equal(account, profile.Account);
        Assert.Equal(dma, profile.Dma);
        Assert.Equal(DebloatMode.Online, profile.DebloatMode);
        Assert.Equal(comfort.Value.RemoveProvisionedAppx, profile.RemoveProvisionedAppx);
        Assert.Equal(comfort.Value.RemoveCapabilities, profile.RemoveCapabilities);
        Assert.Equal(comfort.Value.DisableOptionalFeatures, profile.DisableOptionalFeatures);
        Assert.Equal(comfort.Value.Packages.WingetInstallIds, profile.WingetPackages);
        Assert.Equal(comfort.Value.Packages.WslProfileTokens, profile.WslDistros);
        Assert.Empty(profile.ScoopPackages);
        Assert.Empty(profile.WingetNeedsReboot);
        Assert.Empty(profile.ScoopNeedsReboot);
        Assert.Empty(profile.WslNeedsReboot);
    }

    [Fact]
    public void TryBuild_merges_advanced_winget_ids()
    {
        PackageSelection packages = new(["Anysphere.Cursor"], [], []);
        DmaProfile dma = new(true, new DmaSettleTarget("en-US", 244, "UTC", true));
        AccountProfile account = new("lab", "secret", false);

        Result<Profile, Failure> built = ProfileDraft.TryBuild(
            StationOutcomes.Comfort,
            account,
            dma,
            packages,
            advancedWinget: "Extra.Id\nAnysphere.Cursor");
        Assert.True(built.IsOk);
        Assert.Equal(["Anysphere.Cursor", "Extra.Id"], built.Value.WingetPackages);
    }

    [Fact]
    public void TryParseDma_bad_geo_id_fails()
    {
        Result<DmaProfile, Failure> dma = ProfileDraft.TryParseDma(
            enabled: true,
            locale: "en-US",
            geoId: "nope",
            timeZoneId: "UTC",
            locationServices: true);
        Assert.False(dma.IsOk);
        Assert.Equal("dma.settle.geoId", dma.Error.Code);
    }

    [Fact]
    public void TryBuild_remove_lists_follow_station_seed_not_packages()
    {
        Result<StationSeed, Failure> comfort = StationOutcomes.TrySeed(StationOutcomes.Comfort);
        Assert.True(comfort.IsOk);

        Result<Profile, Failure> built = ProfileDraft.TryBuild(
            StationOutcomes.Comfort,
            new AccountProfile("u", "p", false),
            new DmaProfile(true, new DmaSettleTarget("en-US", 244, "UTC", true)),
            new PackageSelection([], [], []));
        Assert.True(built.IsOk);
        Assert.Equal(comfort.Value.RemoveProvisionedAppx, built.Value.RemoveProvisionedAppx);
        Assert.Empty(built.Value.WingetPackages);
    }
}
