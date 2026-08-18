using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>
/// Staging copies the published Supervisor as-is, so a forgotten republish once shipped an ISO whose guest
/// code predated the tree that built it — an install that fails in ways the source no longer explains.
/// </summary>
public class SupervisorFreshnessTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("winmint-freshness").FullName;

    [Fact]
    public void Source_newer_than_the_publish_is_reported()
    {
        string exe = Publish(at: new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc));
        string source = Source("Program.cs", at: new DateTime(2026, 1, 2, 0, 0, 0, DateTimeKind.Utc));

        Failure? stale = ImageServicing.CheckPublishedBinaryFreshness(
            exe, [SourceRoot], "hostCompile.supervisor.stale", "Supervisor", "just publish-provisioning");

        Assert.NotNull(stale);
        Assert.Equal("hostCompile.supervisor.stale", stale.Value.Code);
        Assert.Contains(source, stale.Value.Message, StringComparison.Ordinal);
        Assert.Contains("just publish-provisioning", stale.Value.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Publish_newer_than_source_is_current()
    {
        string exe = Publish(at: new DateTime(2026, 1, 2, 0, 0, 0, DateTimeKind.Utc));
        _ = Source("Program.cs", at: new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc));

        Assert.Null(ImageServicing.CheckPublishedBinaryFreshness(
            exe, [SourceRoot], "hostCompile.supervisor.stale", "Supervisor", "just publish-provisioning"));
    }

    [Fact]
    public void Source_mtime_in_the_future_is_clock_skew_not_stale()
    {
        DateTime now = DateTime.UtcNow;
        string exe = Publish(at: now.AddMinutes(-5));
        _ = Source("Program.cs", at: now.AddHours(2));

        Assert.Null(ImageServicing.CheckPublishedBinaryFreshness(
            exe, [SourceRoot], "hostCompile.supervisor.stale", "Supervisor", "just publish-provisioning"));
    }

    [Fact]
    public void Build_output_is_not_mistaken_for_source()
    {
        string exe = Publish(at: new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc));
        // obj/ regenerates on every build and would report stale forever.
        _ = Source(Path.Combine("obj", "Generated.cs"), at: new DateTime(2026, 1, 2, 0, 0, 0, DateTimeKind.Utc));

        Assert.Null(ImageServicing.CheckPublishedBinaryFreshness(
            exe, [SourceRoot], "hostCompile.supervisor.stale", "Supervisor", "just publish-provisioning"));
    }

    [Fact]
    public void Absent_source_cannot_be_checked_and_must_not_block()
    {
        string exe = Publish(at: new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc));

        Assert.Null(ImageServicing.CheckPublishedBinaryFreshness(
            exe, [Path.Combine(_root, "no-such-src")], "hostCompile.supervisor.stale", "Supervisor", "just publish-provisioning"));
    }

    [Fact]
    public void Missing_publish_cannot_be_checked_and_must_not_block()
    {
        Assert.Null(ImageServicing.CheckPublishedBinaryFreshness(
            null, [SourceRoot], "hostCompile.supervisor.stale", "Supervisor", "just publish-provisioning"));
    }

    private string SourceRoot => Path.Combine(_root, "src");

    private string Publish(DateTime at)
    {
        string exe = Path.Combine(_root, "WinMint.Provisioning.exe");
        File.WriteAllText(exe, "binary");
        File.SetLastWriteTimeUtc(exe, at);
        return exe;
    }

    private string Source(string relativePath, DateTime at)
    {
        string file = Path.Combine(SourceRoot, relativePath);
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        File.WriteAllText(file, "// code");
        File.SetLastWriteTimeUtc(file, at);
        return file;
    }

    public void Dispose()
    {
        Directory.Delete(_root, recursive: true);
        GC.SuppressFinalize(this);
    }
}
