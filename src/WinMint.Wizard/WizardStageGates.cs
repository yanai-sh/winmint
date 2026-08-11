namespace WinMint.Wizard;

/// <summary>Source/Account/Software/Review stage navigation gates (Avalonia-free).</summary>
public static class WizardStageGates
{
    public const int Source = 0, Account = 1, Software = 2, Review = 3;

    /// <summary>Non-whitespace path that exists on disk. VM should pass the result as <c>sourceReady</c> to gate methods.</summary>
    public static bool SourceReady(string? isoPath) =>
        !string.IsNullOrWhiteSpace(isoPath) && File.Exists(isoPath.Trim());

    public static bool IdentityReady(string? username, string? password) =>
        !string.IsNullOrWhiteSpace(username?.Trim()) && !string.IsNullOrEmpty(password);

    public static bool CanGoTo(int targetIndex, bool sourceReady, bool identityReady)
    {
        if (targetIndex is < Source or > Review)
        {
            return false;
        }

        if (targetIndex == Source)
        {
            return true;
        }

        if (!sourceReady)
        {
            return false;
        }

        if (targetIndex >= Review && !identityReady)
        {
            return false;
        }

        return true;
    }

    public static bool CanAdvance(int currentIndex, bool sourceReady, bool identityReady)
    {
        if (currentIndex is < Source or >= Review)
        {
            return false;
        }

        // Account→Software needs source alone; Software→Review needs source + identity.
        return currentIndex switch
        {
            Source => sourceReady,
            Account => sourceReady,
            Software => sourceReady && identityReady,
            _ => false,
        };
    }

    /// <param name="profileReady">Saved profile path or in-memory Plan bytes (Build auto-saves to the workdir).</param>
    public static bool CanBuild(bool sourceReady, bool identityReady, bool profileReady, bool isBusy) =>
        sourceReady && identityReady && profileReady && !isBusy;
}
