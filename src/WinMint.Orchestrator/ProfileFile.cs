namespace WinMint.Orchestrator;

/// <summary>
/// Host-side Profile load: read Profile JSON, parse via <see cref="BuildPlan.TryParseProfile"/>,
/// materialize <c>account.passwordPath</c> relative to the Profile file. Outside BuildPlan purity.
/// </summary>
public static class ProfileFile
{
    public static Result<Profile, DocumentErrors> TryLoad(string profilePath)
    {
        if (string.IsNullOrWhiteSpace(profilePath))
        {
            return Result.Fail<Profile, DocumentErrors>(new DocumentErrors(
            [
                new DocumentError("document.unreadable", "Profile path is empty.", "profile"),
            ]));
        }

        string fullProfilePath;
        try
        {
            fullProfilePath = Path.GetFullPath(profilePath);
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            _ = ex;
            return Result.Fail<Profile, DocumentErrors>(new DocumentErrors(
            [
                new DocumentError(
                    "document.unreadable",
                    $"Cannot resolve Profile path '{profilePath}'.",
                    "profile"),
            ]));
        }

        byte[] utf8;
        try
        {
            utf8 = File.ReadAllBytes(fullProfilePath);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            _ = ex;
            return Result.Fail<Profile, DocumentErrors>(new DocumentErrors(
            [
                new DocumentError(
                    "document.unreadable",
                    $"Cannot read Profile '{fullProfilePath}'.",
                    "profile"),
            ]));
        }

        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(utf8);
        if (!parsed.IsOk)
        {
            return parsed;
        }

        Profile profile = parsed.Value;
        string? authoredPath = profile.Account.PasswordPath;
        if (authoredPath is null || !string.IsNullOrEmpty(profile.Account.Password))
        {
            return Result.Ok<Profile, DocumentErrors>(profile);
        }

        if (!TryResolvePasswordPath(fullProfilePath, authoredPath, out string resolved, out DocumentError? pathError))
        {
            return Result.Fail<Profile, DocumentErrors>(new DocumentErrors([pathError!]));
        }

        string password;
        try
        {
            password = File.ReadAllText(resolved).TrimEnd('\r', '\n');
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            _ = ex;
            return Result.Fail<Profile, DocumentErrors>(new DocumentErrors(
            [
                new DocumentError(
                    "account.passwordPath.unreadable",
                    $"Cannot read account.passwordPath '{authoredPath}'.",
                    "account.passwordPath"),
            ]));
        }

        Profile materialized = profile with
        {
            Account = profile.Account with { Password = password },
        };
        return Result.Ok<Profile, DocumentErrors>(materialized);
    }

    private static bool TryResolvePasswordPath(
        string fullProfilePath,
        string authoredPath,
        out string resolved,
        out DocumentError? error)
    {
        resolved = "";
        error = null;

        // Fully qualified stays fully qualified. Root-relative / drive-relative ambient forms fail closed.
        if (Path.IsPathFullyQualified(authoredPath))
        {
            resolved = authoredPath;
            return true;
        }

        if (Path.IsPathRooted(authoredPath))
        {
            error = new DocumentError(
                "account.passwordPath.unreadable",
                $"Cannot read account.passwordPath '{authoredPath}'.",
                "account.passwordPath");
            return false;
        }

        string profileDir = Path.GetDirectoryName(fullProfilePath) ?? "";
        resolved = Path.GetFullPath(Path.Combine(profileDir, authoredPath));
        return true;
    }
}
