using WinMint.Orchestrator;

namespace WinMint.Tests;

public class MediaCacheIdentityTests
{
    [Fact]
    public void Same_bytes_at_two_paths_share_identity()
    {
        string root = NewRoot();
        try
        {
            string a = Path.Combine(root, "a.iso");
            string b = Path.Combine(root, "other", "b.iso");
            Directory.CreateDirectory(Path.GetDirectoryName(b)!);
            File.WriteAllBytes(a, [1, 2, 3, 4]);
            File.Copy(a, b);

            Assert.True(MediaCacheIdentity.TryFromFile(a, 3, out MediaCacheIdentity left, out _));
            Assert.True(MediaCacheIdentity.TryFromFile(b, 3, out MediaCacheIdentity right, out _));
            Assert.Equal(left, right);
            Assert.Equal(left.RelativeEntryPath, right.RelativeEntryPath);
            Assert.Equal(64, left.SourceIsoSha256.Length);
            Assert.Equal(left.SourceIsoSha256, left.SourceIsoSha256.ToLowerInvariant());
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public void One_changed_byte_changes_identity()
    {
        string root = NewRoot();
        try
        {
            string a = Path.Combine(root, "a.iso");
            string b = Path.Combine(root, "b.iso");
            File.WriteAllBytes(a, [1, 2, 3, 4]);
            File.WriteAllBytes(b, [1, 2, 3, 5]);

            Assert.True(MediaCacheIdentity.TryFromFile(a, 3, out MediaCacheIdentity left, out _));
            Assert.True(MediaCacheIdentity.TryFromFile(b, 3, out MediaCacheIdentity right, out _));
            Assert.NotEqual(left.SourceIsoSha256, right.SourceIsoSha256);
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Theory]
    [InlineData(1, 2)]
    [InlineData(3, 1)]
    public void Different_index_or_schema_changes_relative_path(int indexA, int indexB)
    {
        string sha = new('a', 64);
        Assert.True(MediaCacheIdentity.TryCreate(sha, 4, indexA, 1, out MediaCacheIdentity a, out _));
        Assert.True(MediaCacheIdentity.TryCreate(sha, 4, indexB, 1, out MediaCacheIdentity b, out _));
        Assert.NotEqual(a.RelativeEntryPath, b.RelativeEntryPath);
        Assert.True(MediaCacheIdentity.TryCreate(sha, 4, 3, 2, out MediaCacheIdentity schema, out _));
        Assert.NotEqual(a.RelativeEntryPath, schema.RelativeEntryPath);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public void Non_positive_index_fails(int index)
    {
        Assert.False(MediaCacheIdentity.TryFromFile("unused", index, out _, out Failure error));
        Assert.Equal("servicing.wimIndex.invalid", error.Code);
        Assert.False(MediaCacheIdentity.TryCreate(new string('a', 64), 1, index, 1, out _, out Failure created));
        Assert.Equal("servicing.wimIndex.invalid", created.Code);
    }

    [Fact]
    public void Cache_root_is_host_servicing_media_cache()
    {
        Assert.Equal(
            Path.Combine(ImageServicing.HostServicingRoot, "media-cache"),
            MediaCacheIdentity.Root);
    }

    private static string NewRoot()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-media-id-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        return root;
    }
}
