using WinMint.Orchestrator;

namespace WinMint.Tests;

public class ApplyOperatorProgressTrackerTests
{
    [Fact]
    public void Stage_change_emits_once_skips_idle()
    {
        ApplyOperatorProgressTracker tracker = new();
        Assert.Null(tracker.Consider(new ApplyProgress("idle", null), null, cancelled: false));
        Assert.True(
            tracker.Consider(new ApplyProgress("MountInstallWim", null), null, cancelled: false)
            == "MountInstallWim");
        Assert.Null(tracker.Consider(new ApplyProgress("MountInstallWim", null), null, cancelled: false));
    }

    [Fact]
    public void Still_emits_on_log_growth_rate_limited()
    {
        ApplyOperatorProgressTracker tracker = new(stillInterval: TimeSpan.FromHours(1));
        string log = @"C:\logs\01-MountInstallWim.log";
        Assert.True(
            tracker.Consider(new ApplyProgress("MountInstallWim", log), 10, cancelled: false)
            == $"MountInstallWim — {log}");

        Assert.True(
            tracker.Consider(new ApplyProgress("MountInstallWim", log), 15, cancelled: false)
            == "still MountInstallWim (01-MountInstallWim.log, +5B)");

        Assert.Null(tracker.Consider(new ApplyProgress("MountInstallWim", log), 20, cancelled: false));
    }

    [Fact]
    public void Quiet_once_when_no_growth()
    {
        ApplyOperatorProgressTracker tracker = new(quietAfter: TimeSpan.Zero);
        string log = @"C:\logs\02.log";
        Assert.NotNull(tracker.Consider(new ApplyProgress("ExportWim", log), 100, cancelled: false));
        Assert.True(
            tracker.Consider(new ApplyProgress("ExportWim", log), 100, cancelled: false)
            == "quiet ExportWim — no log growth");
        Assert.Null(tracker.Consider(new ApplyProgress("ExportWim", log), 100, cancelled: false));
    }

    [Fact]
    public void Log_truncate_resets_baseline_without_emit()
    {
        ApplyOperatorProgressTracker tracker = new(stillInterval: TimeSpan.Zero);
        string log = @"C:\logs\03.log";
        _ = tracker.Consider(new ApplyProgress("InjectDrivers", log), 1000, cancelled: false);
        Assert.Null(tracker.Consider(new ApplyProgress("InjectDrivers", log), 50, cancelled: false));
        Assert.True(
            tracker.Consider(new ApplyProgress("InjectDrivers", log), 60, cancelled: false)
            == "still InjectDrivers (03.log, +10B)");
    }

    [Fact]
    public void Cancelled_emits_nothing()
    {
        ApplyOperatorProgressTracker tracker = new();
        Assert.Null(
            tracker.Consider(new ApplyProgress("MountInstallWim", null), null, cancelled: true));
    }

    [Fact]
    public void TryGetLogLength_missing_returns_null()
    {
        Assert.Null(ApplyOperatorProgressTracker.TryGetLogLength(@"C:\no-such-winmint-log-file.log"));
    }
}
