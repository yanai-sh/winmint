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
    public void ClearPrior_removes_other_leaves_keeps_target()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-iso-" + Guid.NewGuid().ToString("n"));
        Directory.CreateDirectory(root);
        try
        {
            string keep = Path.Combine(root, "winmint_sl7_Test_20261005-120000.iso");
            string drop = Path.Combine(root, "winmint_sl7_Test_20260928-083807.iso");
            string legacy = Path.Combine(root, "out.iso");
            File.WriteAllText(keep, "keep");
            File.WriteAllText(drop, "drop");
            File.WriteAllText(legacy, "legacy");

            Assert.Equal(2, WorkdirOutputIsos.ClearPrior(root, keep));
            Assert.True(File.Exists(keep));
            Assert.False(File.Exists(drop));
            Assert.False(File.Exists(legacy));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void ClearPrior_without_keep_removes_all_leaves()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-iso-" + Guid.NewGuid().ToString("n"));
        Directory.CreateDirectory(root);
        try
        {
            File.WriteAllText(Path.Combine(root, "winmint_a_Test_20260101-000000.iso"), "a");
            File.WriteAllText(Path.Combine(root, "out.iso"), "b");
            Assert.Equal(2, WorkdirOutputIsos.ClearPrior(root));
            Assert.Empty(Directory.GetFiles(root, "*.iso"));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }
}
