using Microsoft.Win32;
using WinMint.Orchestrator;

namespace WinMint.Wizard;

/// <summary>
/// Host OS edition → default install.wim index on consumer multi-edition ISOs
/// (Home=1, Home SL=2, Pro=3). Wizard defaults to Home unless the host running
/// the Wizard is a Pro SKU.
/// </summary>
internal static class BuildMachineEdition
{
    public const int HomeWimIndex = 1;

    public static int DefaultWimIndex() =>
        DefaultWimIndexForEditionId(TryReadEditionId());

    public static int DefaultWimIndexForEditionId(string? editionId) =>
        IsProEditionId(editionId) ? ImageServicing.DefaultProWimIndex : HomeWimIndex;

    public static bool IsProEditionId(string? editionId)
    {
        if (string.IsNullOrWhiteSpace(editionId))
        {
            return false;
        }

        // EditionID examples: Professional, ProfessionalN, ProfessionalWorkstation,
        // Core (Home), CoreN, Enterprise, Education, …
        return editionId.StartsWith("Professional", StringComparison.OrdinalIgnoreCase)
            || string.Equals(editionId, "Pro", StringComparison.OrdinalIgnoreCase);
    }

    private static string? TryReadEditionId()
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }

        try
        {
            using RegistryKey? key = Registry.LocalMachine.OpenSubKey(
                @"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
            return key?.GetValue("EditionID") as string;
        }
        catch
        {
            return null;
        }
    }
}
