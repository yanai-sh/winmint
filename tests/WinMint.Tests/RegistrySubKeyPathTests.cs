using System.Text.RegularExpressions;

namespace WinMint.Tests;

/// <summary>
/// A subkey name handed to Registry.* is relative to the hive. A leading backslash is not a root
/// marker — RegCreateKeyEx rejects it with ERROR_BAD_PATHNAME, and .NET surfaces that as IOException.
/// One such constant shipped in Win32DmaSetupRegion and broke every DMA-enabled FirstLogon.
/// </summary>
public partial class RegistrySubKeyPathTests
{
    [Fact]
    public void No_registry_subkey_constant_starts_with_a_separator()
    {
        List<string> offenders = [];
        int scanned = 0;
        foreach (string file in Directory.EnumerateFiles(
                     Path.Combine(TestRepo.Root, "src"),
                     "*.cs",
                     SearchOption.AllDirectories))
        {
            if (file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}", StringComparison.Ordinal)
                || file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}", StringComparison.Ordinal))
            {
                continue;
            }

            foreach (Match m in SubKeyConstant().Matches(File.ReadAllText(file)))
            {
                scanned++;
                if (m.Groups["value"].Value.StartsWith('\\'))
                {
                    offenders.Add($"{Path.GetFileName(file)}: {m.Groups["name"].Value}");
                }
            }
        }

        Assert.True(scanned > 0, "found no subkey constants — the scan is broken, not clean");
        Assert.True(
            offenders.Count == 0,
            $"registry subkey constants must be hive-relative (no leading backslash): {string.Join(", ", offenders)}");
    }

    [GeneratedRegex("""const\s+string\s+(?<name>\w*SubKey\w*)\s*=\s*@?"(?<value>[^"]*)"\s*;""")]
    private static partial Regex SubKeyConstant();
}
