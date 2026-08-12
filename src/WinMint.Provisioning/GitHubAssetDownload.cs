using System.Text.Json.Serialization;

namespace WinMint.Provisioning;

public sealed class GitHubAssetDownload : IAssetDownload
{
    public async Task<string?> TryDownloadGitHubReleaseAssetAsync(
        string repo,
        IReadOnlyList<string> assetNameCandidates,
        CancellationToken ct = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(repo);
        ArgumentNullException.ThrowIfNull(assetNameCandidates);

        using HttpClient client = new();
        client.DefaultRequestHeaders.UserAgent.ParseAdd("WinMint-Provisioning/1.0");
        string url = $"https://api.github.com/repos/{repo}/releases/latest";
        using HttpResponseMessage response = await client.GetAsync(url, ct).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
        GitHubRelease? release = await response.Content.ReadFromJsonAsync(
            GitHubReleaseJsonContext.Default.GitHubRelease,
            ct).ConfigureAwait(false);
        if (release?.Assets is null)
        {
            return null;
        }

        foreach (string candidate in assetNameCandidates)
        {
            GitHubAsset? asset = release.Assets.FirstOrDefault(
                a => a.Name.Contains(candidate, StringComparison.OrdinalIgnoreCase));
            if (asset?.BrowserDownloadUrl is null)
            {
                continue;
            }

            string assetLeaf = Path.GetFileName(asset.Name);
            if (string.IsNullOrWhiteSpace(assetLeaf)
                || !string.Equals(assetLeaf, asset.Name, StringComparison.Ordinal))
            {
                continue;
            }

            string tempDir = Path.Combine(Path.GetTempPath(), "WinMint", "wsl");
            Directory.CreateDirectory(tempDir);
            string destination = Path.Combine(tempDir, assetLeaf);
            using HttpResponseMessage assetResponse = await client.GetAsync(asset.BrowserDownloadUrl, ct)
                .ConfigureAwait(false);
            assetResponse.EnsureSuccessStatusCode();
            await using FileStream stream = File.Create(destination);
            await assetResponse.Content.CopyToAsync(stream, ct).ConfigureAwait(false);
            return destination;
        }

        return null;
    }
}

internal sealed record GitHubRelease(
    [property: JsonPropertyName("assets")] GitHubAsset[]? Assets);

internal sealed record GitHubAsset(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("browser_download_url")] string? BrowserDownloadUrl);

[JsonSerializable(typeof(GitHubRelease))]
internal sealed partial class GitHubReleaseJsonContext : JsonSerializerContext;
