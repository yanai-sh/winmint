using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>Image-quality lane owns its ExportWim parameters.</summary>
public class ExportLaneTests
{
    [Theory]
    [InlineData(ImageQualityLane.Test, "Test", "fast", "skip")]
    [InlineData(ImageQualityLane.Release, "Release", "max", "full")]
    public void For_returns_the_lane_export_contract(
        ImageQualityLane lane,
        string name,
        string compression,
        string cleanup) =>
        Assert.Equal(
            new ExportLane(name, compression, cleanup),
            ExportLane.For(lane));
}
