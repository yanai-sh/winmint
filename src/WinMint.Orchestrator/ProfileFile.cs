namespace WinMint.Orchestrator;

/// <summary>
/// Host-side Profile load: read Profile JSON, parse via <see cref="BuildPlan.TryParseProfile"/>,
/// materialize <c>account.passwordPath</c> relative to the Profile file. Outside BuildPlan purity.
/// </summary>
public static class ProfileFile
{
    public static Result<Profile, IReadOnlyList<DocumentError>> TryLoad(string profilePath)
    {
        if (string.IsNullOrWhiteSpace(profilePath))
        {
            return Result.Fail<Profile, IReadOnlyList<DocumentError>>(
            [
                new DocumentError("document.unreadable", "Profile path is empty.", "profile"),
            ]);
        }

        string fullProfilePath;
        try
        {
            fullProfilePath = Path.GetFullPath(profilePath);
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            _ = ex;
            return Result.Fail<Profile, IReadOnlyList<DocumentError>>(
            [
                new DocumentError(
                    "document.unreadable",
                    $"Cannot resolve Profile path '{profilePath}'.",
                    "profile"),
            ]);
        }

        byte[] utf8;
        try
        {
            utf8 = File.ReadAllBytes(fullProfilePath);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            _ = ex;
            return Result.Fail<Profile, IReadOnlyList<DocumentError>>(
            [
                new DocumentError(
                    "document.unreadable",
                    $"Cannot read Profile '{fullProfilePath}'.",
                    "profile"),
            ]);
        }

        Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile(utf8);
        if (!parsed.IsOk)
        {
            return parsed;
        }

        Profile profile = parsed.Value;
        string? authoredPath = profile.Account.PasswordPath;
        if (authoredPath is null || !string.IsNullOrEmpty(profile.Account.Password))
        {
            return Result.Ok<Profile, IReadOnlyList<DocumentError>>(profile);
        }

        Result<string, DocumentError> resolved =
            ProfileSecrets.TryResolvePasswordPath(fullProfilePath, authoredPath);
        if (!resolved.IsOk)
        {
            return Result.Fail<Profile, IReadOnlyList<DocumentError>>([resolved.Error]);
        }

        string password;
        try
        {
            password = File.ReadAllText(resolved.Value).TrimEnd('\r', '\n');
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            _ = ex;
            return Result.Fail<Profile, IReadOnlyList<DocumentError>>(
            [
                new DocumentError(
                    "account.passwordPath.unreadable",
                    $"Cannot read account.passwordPath '{authoredPath}'.",
                    "account.passwordPath"),
            ]);
        }

        Profile materialized = profile with
        {
            Account = profile.Account with { Password = password },
        };
        return Result.Ok<Profile, IReadOnlyList<DocumentError>>(materialized);
    }
}
