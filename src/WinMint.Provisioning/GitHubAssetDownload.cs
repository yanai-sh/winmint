using System.Security.Cryptography;
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

        (string Name, string Url)? picked = PickReleaseAsset(
            release.Assets.Select(a => (a.Name, a.BrowserDownloadUrl)),
            assetNameCandidates);
        if (picked is null)
        {
            return null;
        }

        string assetLeaf = Path.GetFileName(picked.Value.Name);
        string tempDir = Path.Combine(Path.GetTempPath(), "WinMint", "wsl");
        Directory.CreateDirectory(tempDir);
        string destination = Path.Combine(tempDir, assetLeaf);
        using HttpResponseMessage assetResponse = await client.GetAsync(picked.Value.Url, ct)
            .ConfigureAwait(false);
        assetResponse.EnsureSuccessStatusCode();
        await using FileStream stream = File.Create(destination);
        await assetResponse.Content.CopyToAsync(stream, ct).ConfigureAwait(false);
        return destination;
    }

    internal static (string Name, string Url)? PickReleaseAsset(
        IEnumerable<(string Name, string? BrowserDownloadUrl)> assets,
        IReadOnlyList<string> assetNameCandidates)
    {
        foreach (string candidate in assetNameCandidates)
        {
            List<(string Name, string Url)> matches = [];
            foreach ((string name, string? url) in assets)
            {
                if (string.IsNullOrWhiteSpace(url))
                {
                    continue;
                }

                string leaf = Path.GetFileName(name);
                if (string.IsNullOrWhiteSpace(leaf)
                    || !string.Equals(leaf, name, StringComparison.Ordinal))
                {
                    continue;
                }

                if (!name.Contains(candidate, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                matches.Add((name, url));
            }

            (string Name, string Url)? preferred = matches
                .Where(m => m.Name.EndsWith(".wsl", StringComparison.OrdinalIgnoreCase))
                .Select(m => ((string Name, string Url)?)m)
                .FirstOrDefault();
            if (preferred is not null)
            {
                return preferred;
            }

            if (matches.Count > 0)
            {
                return matches[0];
            }
        }

        return null;
    }

    public async Task<string?> TryDownloadVerifiedAsync(
        string url,
        string sha256Hex,
        string destinationDirectory,
        string fileName,
        CancellationToken ct = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(url);
        ArgumentException.ThrowIfNullOrWhiteSpace(sha256Hex);
        ArgumentException.ThrowIfNullOrWhiteSpace(destinationDirectory);
        ArgumentException.ThrowIfNullOrWhiteSpace(fileName);

        try
        {
            using HttpClient client = new();
            client.DefaultRequestHeaders.UserAgent.ParseAdd("WinMint-Provisioning/1.0");
            using HttpResponseMessage response = await client.GetAsync(url, ct).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                return null;
            }

            Directory.CreateDirectory(destinationDirectory);
            string destination = Path.Combine(destinationDirectory, fileName);
            await using FileStream stream = File.Create(destination);
            await response.Content.CopyToAsync(stream, ct).ConfigureAwait(false);
            await stream.FlushAsync(ct).ConfigureAwait(false);
            stream.Position = 0;
            byte[] hash = await SHA256.HashDataAsync(stream, ct).ConfigureAwait(false);
            string actual = Convert.ToHexString(hash);
            if (!actual.Equals(sha256Hex, StringComparison.OrdinalIgnoreCase))
            {
                File.Delete(destination);
                return null;
            }

            return destination;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return null;
        }
    }
}

internal sealed record GitHubRelease(
    [property: JsonPropertyName("assets")] GitHubAsset[]? Assets);

internal sealed record GitHubAsset(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("browser_download_url")] string? BrowserDownloadUrl);

[JsonSerializable(typeof(GitHubRelease))]
internal sealed partial class GitHubReleaseJsonContext : JsonSerializerContext;
