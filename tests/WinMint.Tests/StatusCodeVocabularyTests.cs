using System.Text.RegularExpressions;

namespace WinMint.Tests;

/// <summary>
/// Status codes and evidence phases are one vocabulary (CONTRACTS): dotted <c>area.token</c>, every
/// segment camelCase. Two dialects once split this repo almost 50/50 — this is what stops the drift.
/// </summary>
public partial class StatusCodeVocabularyTests
{
    /// <summary>Areas from CONTRACTS. A literal outside this set is not a status code.</summary>
    private static readonly string[] Areas =
    [
        "machineSetup", "shell", "settle", "jobs", "checkpoint", "session", "servicing",
        "account", "document", "dma", "debloat", "packages", "policies", "drivers", "wim", "hostCompile",
    ];

    [Fact]
    public void Emitted_codes_are_dotted_camelCase()
    {
        List<string> offenders = [];
        HashSet<string> scanned = new(StringComparer.Ordinal);
        foreach (string file in SourceFiles())
        {
            foreach (Match m in DottedLiteral().Matches(File.ReadAllText(file)))
            {
                string code = m.Groups["code"].Value;
                if (!Areas.Contains(code.Split('.')[0], StringComparer.Ordinal))
                {
                    continue;
                }

                scanned.Add(code);
                if (code.Contains('_', StringComparison.Ordinal))
                {
                    offenders.Add($"{Path.GetFileName(file)}: {code}");
                }
            }
        }

        // A regex that matches nothing would pass silently; the suite emits far more codes than this.
        Assert.True(scanned.Count > 40, $"only found {scanned.Count} codes — the scan is broken, not clean");
        Assert.True(
            offenders.Count == 0,
            $"snake_case status codes — CONTRACTS says dotted camelCase: {string.Join(", ", offenders)}");
    }

    private static IEnumerable<string> SourceFiles() =>
        Directory
            .EnumerateFiles(Path.Combine(TestRepo.Root, "src"), "*.cs", SearchOption.AllDirectories)
            .Where(static f =>
                !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}", StringComparison.Ordinal)
                && !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}", StringComparison.Ordinal));

    [GeneratedRegex("\"(?<code>[a-z][a-zA-Z0-9]*(?:\\.[a-zA-Z0-9_]+)+)\"")]
    private static partial Regex DottedLiteral();
}
