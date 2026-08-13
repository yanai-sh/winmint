using System.Security.Cryptography;

namespace WinMint.Orchestrator;

internal readonly record struct MediaCacheIdentity(
    string SourceIsoSha256,
    long SourceIsoLength,
    int WimIndex,
    int Schema)
{
    internal const int CurrentSchema = 1;

    internal static string Root { get; } =
        Path.Combine(ImageServicing.HostServicingRoot, "media-cache");

    internal string RelativeEntryPath =>
        Path.Combine($"v{Schema}", SourceIsoSha256, $"index-{WimIndex}");

    internal static bool TryFromFile(
        string sourceIsoPath,
        int wimIndex,
        out MediaCacheIdentity identity,
        out Failure error)
    {
        identity = default;
        error = default!;
        if (wimIndex <= 0)
        {
            error = new Failure("servicing.wimIndex.invalid", "WIM index must be a positive integer.");
            return false;
        }

        if (string.IsNullOrWhiteSpace(sourceIsoPath) || !File.Exists(sourceIsoPath))
        {
            error = new Failure("servicing.sourceIso.missing", $"Source ISO not found: {sourceIsoPath}");
            return false;
        }

        FileInfo info = new(sourceIsoPath);
        using FileStream stream = File.OpenRead(sourceIsoPath);
        string sha = Convert.ToHexStringLower(SHA256.HashData(stream));
        return TryCreate(sha, info.Length, wimIndex, CurrentSchema, out identity, out error);
    }

    internal static bool TryCreate(
        string sourceIsoSha256,
        long sourceIsoLength,
        int wimIndex,
        int schema,
        out MediaCacheIdentity identity,
        out Failure error)
    {
        identity = default;
        error = default!;
        if (wimIndex <= 0)
        {
            error = new Failure("servicing.wimIndex.invalid", "WIM index must be a positive integer.");
            return false;
        }

        if (sourceIsoLength < 0
            || sourceIsoSha256 is not { Length: 64 }
            || sourceIsoSha256.Any(static c => c is not (>= '0' and <= '9') and not (>= 'a' and <= 'f')))
        {
            error = new Failure("servicing.sourceIso.hash.invalid", "Source ISO SHA-256 must be lowercase 64-character hex.");
            return false;
        }

        identity = new MediaCacheIdentity(sourceIsoSha256, sourceIsoLength, wimIndex, schema);
        return true;
    }
}
