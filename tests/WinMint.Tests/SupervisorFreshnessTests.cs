using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>
/// Staging copies the published Supervisor as-is. The sibling stamp is a hash of guest source, so a
/// forgotten republish is stale at any mtime and a clock jump is not.
/// </summary>
public class SupervisorFreshnessTests : IDisposable
{
    /// <summary>One file, <c>WinMint.Provisioning/Program.cs</c> containing <c>stamp</c>. Shared with Test-SourceStamp.ps1.</summary>
    private const string PinnedDigest = "a628d45f7c32f7f21b081290b3f441b85512d970b677614c6039933f56b0dd21";

    private readonly string _root = Directory.CreateTempSubdirectory("winmint-freshness").FullName;

    [Fact]
    public void One_file_digest_matches_the_pinned_vector()
    {
        _ = Source("Program.cs", "stamp");

        Assert.Equal(PinnedDigest, ImageServicing.ComputeSourceTreeDigest([SourceRoot]));
    }

    [Fact]
    public void Matching_stamp_is_current_at_any_mtime()
    {
        string exe = Publish();
        _ = Source("Program.cs", "stamp", at: DateTime.UtcNow.AddHours(2));
        File.WriteAllText(exe + ".sha256", PinnedDigest + "\n");

        Assert.Null(Check(exe));
    }

    [Fact]
    public void Mismatched_stamp_is_stale()
    {
        string exe = Publish();
        _ = Source("Program.cs", "edited");
        File.WriteAllText(exe + ".sha256", PinnedDigest);

        Failure? stale = Check(exe);

        Assert.NotNull(stale);
        Assert.Equal("hostCompile.supervisor.stale", stale.Value.Code);
        Assert.Contains("just publish-provisioning", stale.Value.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Missing_stamp_while_source_exists_is_stale()
    {
        string exe = Publish();
        _ = Source("Program.cs", "stamp");

        Failure? stale = Check(exe);

        Assert.NotNull(stale);
        Assert.Equal("hostCompile.supervisor.stale", stale.Value.Code);
        Assert.Contains("no source stamp", stale.Value.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Build_output_does_not_change_the_digest()
    {
        _ = Source("Program.cs", "stamp");
        _ = Source(Path.Combine("obj", "Generated.cs"), "generated");
        _ = Source(Path.Combine("bin", "Debug", "Generated.cs"), "generated");

        Assert.Equal(PinnedDigest, ImageServicing.ComputeSourceTreeDigest([SourceRoot]));
    }

    [Fact]
    public void Absent_source_cannot_be_checked_and_must_not_block()
    {
        string exe = Publish();

        Assert.Null(ImageServicing.CheckPublishedBinaryFreshness(
            exe, [Path.Combine(_root, "no-such-src")], "hostCompile.supervisor.stale", "Supervisor", "just publish-provisioning"));
    }

    [Fact]
    public void Missing_publish_cannot_be_checked_and_must_not_block()
    {
        Assert.Null(ImageServicing.CheckPublishedBinaryFreshness(
            null, [SourceRoot], "hostCompile.supervisor.stale", "Supervisor", "just publish-provisioning"));
    }

    private string SourceRoot => Path.Combine(_root, "WinMint.Provisioning");

    private Failure? Check(string exe) =>
        ImageServicing.CheckPublishedBinaryFreshness(
            exe, [SourceRoot], "hostCompile.supervisor.stale", "Supervisor", "just publish-provisioning");

    private string Publish()
    {
        string exe = Path.Combine(_root, "WinMint.Provisioning.exe");
        File.WriteAllText(exe, "binary");
        return exe;
    }

    private string Source(string relativePath, string text, DateTime? at = null)
    {
        string file = Path.Combine(SourceRoot, relativePath);
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        File.WriteAllText(file, text);
        if (at is { } when)
        {
            File.SetLastWriteTimeUtc(file, when);
        }

        return file;
    }

    public void Dispose()
    {
        Directory.Delete(_root, recursive: true);
        GC.SuppressFinalize(this);
    }
}
