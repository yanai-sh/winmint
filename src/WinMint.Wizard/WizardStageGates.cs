namespace WinMint.Wizard;

/// <summary>Media/You/Taste/Included stage navigation gates (Avalonia-free).</summary>
public static class WizardStageGates
{
    public const int Media = 0, You = 1, Taste = 2, Included = 3;

    /// <summary>Non-whitespace path that exists on disk. VM should pass the result as <c>sourceReady</c> to gate methods.</summary>
    public static bool SourceReady(string? isoPath) =>
        !string.IsNullOrWhiteSpace(isoPath) && File.Exists(isoPath.Trim());

    public static bool IdentityReady(string? username, string? password) =>
        !string.IsNullOrWhiteSpace(username?.Trim()) && !string.IsNullOrEmpty(password);

    public static bool CanGoTo(int targetIndex, bool sourceReady, bool identityReady)
    {
        if (targetIndex is < Media or > Included)
        {
            return false;
        }

        if (targetIndex == Media)
        {
            return true;
        }

        if (!sourceReady)
        {
            return false;
        }

        if (targetIndex >= Included && !identityReady)
        {
            return false;
        }

        return true;
    }

    public static bool CanAdvance(int currentIndex, bool sourceReady, bool identityReady)
    {
        if (currentIndex is < Media or >= Included)
        {
            return false;
        }

        // Password gates Included only (moodboard canGo); You→Taste needs source alone.
        return currentIndex switch
        {
            Media => sourceReady,
            You => sourceReady,
            Taste => identityReady,
            _ => false,
        };
    }

    public static bool CanBuild(bool sourceReady, bool identityReady, bool savedProfileReady, bool isBusy) =>
        sourceReady && identityReady && savedProfileReady && !isBusy;
}
