namespace WinMint.Orchestrator;

/// <summary>
/// Locates repo/toolkit assets by walking up from the app base directory. One walk, one fallback —
/// hosts and tests must not hand-roll their own marker file.
/// </summary>
public static class ToolkitRoot
{
    /// <summary>Full path to an existing file or directory under the repo/toolkit root; null when absent.</summary>
    public static string? TryFind(params string[] relativeParts)
    {
        string relative = Path.Combine(relativeParts);
        string? root = TryFindRoot(relative);
        return root is null ? null : Path.Combine(root, relative);
    }

    /// <summary>Directory containing <paramref name="relativeParts"/>; throws when no ancestor has it.</summary>
    public static string FindRoot(params string[] relativeParts)
    {
        string relative = Path.Combine(relativeParts);
        return TryFindRoot(relative)
            ?? throw new DirectoryNotFoundException(
                $"No ancestor of '{AppContext.BaseDirectory}' contains '{relative}'.");
    }

    private static string? TryFindRoot(string relative)
    {
        string? dir = AppContext.BaseDirectory;
        while (!string.IsNullOrEmpty(dir))
        {
            if (Exists(Path.Combine(dir, relative)))
            {
                return dir;
            }

            dir = Path.GetDirectoryName(dir);
        }

        // Published toolkits can run with a cwd outside the base-directory chain.
        string cwd = Directory.GetCurrentDirectory();
        return Exists(Path.Combine(cwd, relative)) ? cwd : null;
    }

    private static bool Exists(string path) => File.Exists(path) || Directory.Exists(path);
}
