using WinMint.Watch;

namespace WinMint.Tests;

public class WatchSmokeDisplayTests
{
    [Theory]
    [InlineData("continue", "cyan")]
    [InlineData("awaiting-run", "cyan")]
    [InlineData("done", "green")]
    [InlineData("harness-stale", "red")]
    [InlineData("empty-vhd", "red")]
    public void VerdictSpectreColor_maps_by_kind(string verdict, string expectedColor)
    {
        Assert.Equal(expectedColor, SmokeWatchDisplay.VerdictSpectreColor(verdict));
    }

    [Fact]
    public void Alarm_verdict_shows_status_stale_suffix()
    {
        string markup = SmokeWatchDisplay.BuildSmokeHeaderMarkup("harness-stale", "guest-up", 30, 158, 180);
        Assert.Contains("[red]harness-stale[/]", markup);
        Assert.Contains("status stale 180s", markup);
    }

    [Fact]
    public void Quiet_continue_one_liner_has_no_stale_suffix()
    {
        string markup = SmokeWatchDisplay.BuildSmokeHeaderMarkup("continue", "apply", 41, 168, 99999);
        Assert.Contains("[cyan]continue[/]", markup);
        Assert.DoesNotContain("status stale", markup);
    }

    [Fact]
    public void Done_verdict_is_green_without_stale_suffix()
    {
        string markup = SmokeWatchDisplay.BuildSmokeHeaderMarkup("done", "green", 0, 0, 500);
        Assert.Contains("[green]done[/]", markup);
        Assert.DoesNotContain("status stale", markup);
    }

    [Fact]
    public void ClipHostLine_ends_with_ellipsis_when_long()
    {
        string clipped = SmokeWatchDisplay.ClipHostLine(new string('x', 100), 60);
        Assert.Equal(60, clipped.Length);
        Assert.EndsWith("…", clipped);
    }
}
