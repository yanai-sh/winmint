using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace WinMintSetupShell;

internal static class WizardBridge
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = null,
        WriteIndented = true
    };

    public static string ResolveRepoRoot(string hint, string startDir)
    {
        var current = string.IsNullOrWhiteSpace(hint) ? startDir : hint;
        for (var i = 0; i < 12 && !string.IsNullOrWhiteSpace(current); i++)
        {
            if (File.Exists(Path.Combine(current, "WinMint-CLI.ps1")))
            {
                return Path.GetFullPath(current);
            }

            var parent = Directory.GetParent(current)?.FullName;
            if (string.IsNullOrWhiteSpace(parent) || string.Equals(parent, current, StringComparison.OrdinalIgnoreCase))
            {
                break;
            }

            current = parent;
        }

        throw new InvalidOperationException("Could not resolve WinMint repository root.");
    }

    public static string WizardSettingsPath(string repoRoot) =>
        Path.Combine(repoRoot, "output", "gui", "wizard-settings.json");

    public static string IntentPath(string repoRoot) => WizardSettingsPath(repoRoot);

    public static string ProfilePath(string repoRoot) =>
        Path.Combine(repoRoot, "output", "gui", "BuildProfile.json");

    public static string BridgeScriptPath(string repoRoot, string name) =>
        Path.Combine(repoRoot, "tools", "ui-bridge", name);

    public static void SaveWizardSettings(string repoRoot, JsonNode settings)
    {
        var path = WizardSettingsPath(repoRoot);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, settings.ToJsonString(JsonOptions), Encoding.UTF8);
    }

    public static void SaveIntent(string repoRoot, JsonNode intent)
    {
        SaveWizardSettings(repoRoot, intent);
    }

    public static JsonNode RunBridgeScript(string repoRoot, string scriptName, IReadOnlyList<string> extraArgs, bool includeRepositoryRoot = true)
    {
        var scriptPath = BridgeScriptPath(repoRoot, scriptName);
        if (!File.Exists(scriptPath))
        {
            throw new FileNotFoundException($"UI bridge script missing: {scriptPath}");
        }

        var pwsh = FindPwsh();
        var args = new List<string>
        {
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", scriptPath
        };
        if (includeRepositoryRoot)
        {
            args.Add("-RepositoryRoot");
            args.Add(repoRoot);
        }
        args.AddRange(extraArgs);

        var psi = new ProcessStartInfo
        {
            FileName = pwsh,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = repoRoot
        };
        foreach (var arg in args)
        {
            psi.ArgumentList.Add(arg);
        }

        using var process = Process.Start(psi) ?? throw new InvalidOperationException("Could not start pwsh.");
        var stdout = process.StandardOutput.ReadToEnd();
        var stderr = process.StandardError.ReadToEnd();
        process.WaitForExit();

        if (process.ExitCode != 0)
        {
            var detail = string.IsNullOrWhiteSpace(stderr) ? stdout.Trim() : stderr.Trim();
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(detail)
                ? $"Bridge script failed: {scriptName}"
                : detail);
        }

        return ParseLastJson(stdout) ?? JsonNode.Parse("{}")!;
    }

    public static JsonNode SummarizeBuildDelta(string path)
    {
        if (!File.Exists(path))
        {
            return JsonNode.Parse("""{"totalRecords":0,"userControlledRecords":0,"phaseCounts":{},"highlightedRecords":[]}""")!;
        }

        var doc = JsonNode.Parse(File.ReadAllText(path)) as JsonObject;
        var records = doc?["records"] as JsonArray ?? new JsonArray();
        var phaseCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var userControlled = 0;
        var highlighted = new JsonArray();

        foreach (var item in records)
        {
            if (item is not JsonObject record)
            {
                continue;
            }

            var phase = record["phase"]?.GetValue<string>() ?? "";
            if (!string.IsNullOrWhiteSpace(phase))
            {
                phaseCounts[phase] = phaseCounts.GetValueOrDefault(phase) + 1;
            }

            if (record["userControlled"]?.GetValue<bool>() == true)
            {
                userControlled++;
            }

            if (highlighted.Count < 8)
            {
                var changes = record["changes"] as JsonArray;
                highlighted.Add(new JsonObject
                {
                    ["title"] = record["title"]?.GetValue<string>() ?? "",
                    ["phase"] = phase,
                    ["kind"] = record["kind"]?.GetValue<string>() ?? "",
                    ["changeCount"] = changes?.Count ?? 0
                });
            }
        }

        var phases = new JsonObject();
        foreach (var pair in phaseCounts.OrderBy(static p => p.Key, StringComparer.OrdinalIgnoreCase))
        {
            phases[pair.Key] = pair.Value;
        }

        return new JsonObject
        {
            ["totalRecords"] = records.Count,
            ["userControlledRecords"] = userControlled,
            ["phaseCounts"] = phases,
            ["highlightedRecords"] = highlighted
        };
    }

    private static string FindPwsh()
    {
        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (var segment in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            var candidate = Path.Combine(segment.Trim(), "pwsh.exe");
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new InvalidOperationException("PowerShell 7 (pwsh) was not found on PATH.");
    }

    private static JsonNode? ParseLastJson(string stdout)
    {
        foreach (var line in stdout.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).Reverse())
        {
            if (!line.StartsWith("{", StringComparison.Ordinal))
            {
                continue;
            }

            try
            {
                return JsonNode.Parse(line);
            }
            catch (JsonException)
            {
                // ponytail: last-line JSON heuristic; multi-line JSON would need a different parser
            }
        }

        return null;
    }
}
