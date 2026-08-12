using WinMint.Orchestrator;

namespace WinMint.Tests;

public class OutputIsoNamingTests
{
    [Theory]
    [InlineData(@"samples\sl7.profile.json", "sl7")]
    [InlineData("sl7.profile.json", "sl7")]
    [InlineData("custom.json", "custom")]
    [InlineData(@"C:\x\My Profile.profile.json", "My_Profile")]
    [InlineData("", "profile")]
    [InlineData(null, "profile")]
    public void ProfileStem_from_path(string? path, string expected) =>
        Assert.Equal(expected, OutputIsoNaming.ProfileStem(path));

    [Fact]
    public void DefaultFileName_product_centric()
    {
        DateTimeOffset ts = new(2026, 8, 12, 8, 59, 28, TimeSpan.FromHours(3));
        string name = OutputIsoNaming.DefaultFileName(
            @"samples\sl7.profile.json",
            ImageQualityLane.Release,
            ts);
        Assert.Equal("winmint_sl7_Release_20260812-085928.iso", name);
    }

    [Fact]
    public void DefaultPath_joins_workdir()
    {
        DateTimeOffset ts = new(2026, 8, 12, 9, 0, 0, TimeSpan.FromHours(3));
        string path = OutputIsoNaming.DefaultPath(
            @"C:\work\gate-b",
            "samples/sl7.profile.json",
            ImageQualityLane.Test,
            ts);
        Assert.Equal(
            Path.Combine(@"C:\work\gate-b", "winmint_sl7_Test_20260812-090000.iso"),
            path);
    }
}
