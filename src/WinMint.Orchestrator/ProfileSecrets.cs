namespace WinMint.Orchestrator;

/// <summary>
/// Host secret materialization for Profile accounts. BuildPlan stays pure over already-materialized
/// profiles; Compose / Station pack / emit call this module.
/// </summary>
public static class ProfileSecrets
{
    /// <summary>
    /// Resolve an authored passwordPath relative to a Profile file (or reject rooted ambient paths).
    /// Fully qualified paths pass through.
    /// </summary>
    public static Result<string, DocumentError> TryResolvePasswordPath(
        string fullProfilePath,
        string authoredPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(fullProfilePath);
        ArgumentException.ThrowIfNullOrWhiteSpace(authoredPath);

        if (Path.IsPathFullyQualified(authoredPath))
        {
            return Result.Ok<string, DocumentError>(authoredPath);
        }

        if (Path.IsPathRooted(authoredPath))
        {
            return Result.Fail<string, DocumentError>(
                new DocumentError(
                    "account.passwordPath.unreadable",
                    $"Cannot read account.passwordPath '{authoredPath}'.",
                    "account.passwordPath"));
        }

        string profileDir = Path.GetDirectoryName(fullProfilePath) ?? "";
        return Result.Ok<string, DocumentError>(
            Path.GetFullPath(Path.Combine(profileDir, authoredPath)));
    }

    /// <summary>
    /// Prefer an existing fully-qualified sidecar, else combine with a source directory
    /// (Station pack export from a Profile folder).
    /// </summary>
    public static Result<string, Failure> TryResolveSidecarSource(
        string authoredPath,
        string? passwordSourceDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(authoredPath);
        string trimmed = authoredPath.Trim();

        if (Path.IsPathFullyQualified(trimmed) && File.Exists(trimmed))
        {
            return Result.Ok<string, Failure>(trimmed);
        }

        if (!string.IsNullOrWhiteSpace(passwordSourceDirectory))
        {
            string combined = Path.GetFullPath(Path.Combine(passwordSourceDirectory.Trim(), trimmed));
            if (File.Exists(combined))
            {
                return Result.Ok<string, Failure>(combined);
            }
        }

        return Result.Fail<string, Failure>(
            new Failure(
                "stationPack.password.missing",
                $"Cannot copy account.passwordPath '{authoredPath}' into the Station pack."));
    }

    /// <summary>Safe sidecar leaf under a pack/export directory.</summary>
    public static string SidecarLeaf(string? authoredPath, string fallbackLeaf)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(fallbackLeaf);
        if (!string.IsNullOrWhiteSpace(authoredPath))
        {
            string candidate = Path.GetFileName(authoredPath.Trim());
            if (!string.IsNullOrEmpty(candidate)
                && candidate is not ("." or "..")
                && candidate.IndexOfAny(Path.GetInvalidFileNameChars()) < 0)
            {
                return candidate;
            }
        }

        return fallbackLeaf;
    }
}
