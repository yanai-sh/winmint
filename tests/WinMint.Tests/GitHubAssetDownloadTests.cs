using WinMint.Provisioning;

namespace WinMint.Tests;

public class GitHubAssetDownloadTests
{
    [Fact]
    public void PickReleaseAsset_prefers_wsl_over_bundle_and_sha()
    {
        (string Name, string? Url)[] assets =
        [
            ("archlinuxarm-aarch64-2026.10.01.wsl.bundle", "https://example/bundle"),
            ("archlinuxarm-aarch64-2026.10.01.wsl.SHA256", "https://example/sha"),
            ("archlinuxarm-aarch64-2026.10.01.wsl", "https://example/wsl"),
        ];

        (string Name, string Url)? picked = GitHubAssetDownload.PickReleaseAsset(
            assets,
            ["archlinuxarm-aarch64"]);

        Assert.NotNull(picked);
        Assert.Equal("archlinuxarm-aarch64-2026.10.01.wsl", picked.Value.Name);
        Assert.Equal("https://example/wsl", picked.Value.Url);
    }

    [Fact]
    public void PickReleaseAsset_skips_path_traversal_names()
    {
        (string Name, string? Url)[] assets =
        [
            ("../evil.wsl", "https://example/evil"),
            ("archlinuxarm-aarch64.wsl", "https://example/ok"),
        ];

        (string Name, string Url)? picked = GitHubAssetDownload.PickReleaseAsset(
            assets,
            ["archlinuxarm-aarch64"]);

        Assert.NotNull(picked);
        Assert.Equal("archlinuxarm-aarch64.wsl", picked.Value.Name);
    }
}
