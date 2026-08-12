using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;
using WinMint.Orchestrator;

namespace WinMint.Wizard;

/// <summary>Unelevated Source ISO → install.wim index list (Avalonia-free). Parser lives in Get-WimMetadata.ps1.</summary>
internal static class SourceWimProbe
{
    public static async Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> TryProbeIsoAsync(
        string isoPath,
        IWimIndexSource? source = null,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(isoPath) || !File.Exists(isoPath.Trim()))
        {
            return Result.Fail<IReadOnlyList<WimIndexInfo>, Failure>(
                new Failure("wim.probe.isoMissing", $"Source ISO not found: {isoPath}"));
        }

        IWimIndexSource adapter = source ?? PwshWimIndexSource.Instance;
        return await adapter.ListFromIsoAsync(isoPath.Trim(), cancellationToken).ConfigureAwait(true);
    }

    public static Result<IReadOnlyList<WimIndexInfo>, Failure> ParseListJson(string json)
    {
        try
        {
            WimIndexListFile? file = JsonSerializer.Deserialize(json, WimIndexJsonContext.Default.WimIndexListFile);
            if (file?.Indexes is null || file.Indexes.Count == 0)
            {
                return Result.Fail<IReadOnlyList<WimIndexInfo>, Failure>(
                    new Failure("wim.probe.empty", "Get-WimInfo returned no indexes."));
            }

            List<WimIndexInfo> rows = [];
            foreach (WimIndexFile row in file.Indexes)
            {
                if (row.Index <= 0 || IsUndefinedName(row.Name))
                {
                    return Result.Fail<IReadOnlyList<WimIndexInfo>, Failure>(
                        new Failure(
                            "wim.probe.incompleteName",
                            $"Index {row.Index} Name is missing or undefined."));
                }

                rows.Add(new WimIndexInfo(
                    row.Index,
                    row.Name!.Trim(),
                    NullIfEmpty(row.Architecture),
                    NullIfEmpty(row.Edition),
                    NullIfEmpty(row.Version),
                    NullIfEmpty(row.Build)));
            }

            return Result.Ok<IReadOnlyList<WimIndexInfo>, Failure>(rows.ToArray());
        }
        catch (JsonException ex)
        {
            return Result.Fail<IReadOnlyList<WimIndexInfo>, Failure>(
                new Failure("wim.probe.unreadable", ex.Message));
        }
    }

    /// <summary>
    /// Host default until the author picks; deliberate picks survive re-probe when still listed.
    /// Does not invent a substitute index when the host default is absent from the media.
    /// </summary>
    public static int ResolveSelection(
        IReadOnlyList<WimIndexInfo> rows,
        int currentIndex,
        bool userChose,
        int hostDefault)
    {
        if (userChose && Contains(rows, currentIndex))
        {
            return currentIndex;
        }

        return hostDefault;
    }

    /// <summary>Mirrors Get-WimMetadata <c>Test-WimMetadataUndefined</c>.</summary>
    internal static bool IsUndefinedName(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return true;
        }

        string t = value.Trim();
        return t.Equals("undefined", StringComparison.OrdinalIgnoreCase)
            || t.Equals("<undefined>", StringComparison.OrdinalIgnoreCase);
    }

    private static bool Contains(IReadOnlyList<WimIndexInfo> rows, int index)
    {
        for (int i = 0; i < rows.Count; i++)
        {
            if (rows[i].Index == index)
            {
                return true;
            }
        }

        return false;
    }

    private static string? NullIfEmpty(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}

internal sealed class WimIndexListFile
{
    public List<WimIndexFile>? Indexes { get; set; }
}

internal sealed class WimIndexFile
{
    public int Index { get; set; }
    public string? Name { get; set; }
    public string? Architecture { get; set; }
    public string? Edition { get; set; }
    public string? Version { get; set; }
    public string? Build { get; set; }
}

[JsonSerializable(typeof(WimIndexListFile))]
[JsonSerializable(typeof(WimIndexFile))]
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    PropertyNameCaseInsensitive = true)]
internal sealed partial class WimIndexJsonContext : JsonSerializerContext;

public sealed record WimIndexInfo(
    int Index,
    string Name,
    string? Architecture,
    string? Edition,
    string? Version,
    string? Build)
{
    public string DisplayLabel
    {
        get
        {
            List<string> bits = [];
            if (!string.IsNullOrWhiteSpace(Architecture))
            {
                bits.Add(Architecture);
            }

            if (!string.IsNullOrWhiteSpace(Edition))
            {
                bits.Add(Edition);
            }

            if (!string.IsNullOrWhiteSpace(Build))
            {
                bits.Add(Build);
            }
            else if (!string.IsNullOrWhiteSpace(Version))
            {
                bits.Add(Version);
            }

            string suffix = bits.Count == 0 ? "" : $" ({string.Join(", ", bits)})";
            return $"{Index} — {Name}{suffix}";
        }
    }
}

/// <summary>Port for ISO → WIM index list. Real adapter shells to Get-WimMetadata.ps1; tests ship a fake.</summary>
internal interface IWimIndexSource
{
    Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> ListFromIsoAsync(
        string isoPath,
        CancellationToken cancellationToken = default);
}

internal sealed class PwshWimIndexSource : IWimIndexSource
{
    public static PwshWimIndexSource Instance { get; } = new();

    public async Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> ListFromIsoAsync(
        string isoPath,
        CancellationToken cancellationToken = default)
    {
        string? script = FindWimMetadataScript();
        if (script is null)
        {
            return Result.Fail<IReadOnlyList<WimIndexInfo>, Failure>(
                new Failure("wim.probe.unreadable", "servicing/Get-WimMetadata.ps1 not found."));
        }

        ProcessStartInfo psi = new()
        {
            FileName = "pwsh",
            ArgumentList = { "-NoProfile", "-File", script, "-ListFromIso", isoPath },
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = Path.GetDirectoryName(script)!,
        };

        try
        {
            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeoutCts.CancelAfter(TimeSpan.FromSeconds(120));

            ProcessTextOutput captured = await Process.RunAndCaptureTextAsync(psi, timeoutCts.Token)
                .ConfigureAwait(false);
            string stdout = captured.StandardOutput;
            string stderr = captured.StandardError;

            if (captured.ExitStatus.Canceled || timeoutCts.IsCancellationRequested)
            {
                if (cancellationToken.IsCancellationRequested)
                {
                    return Result.Fail<IReadOnlyList<WimIndexInfo>, Failure>(
                        new Failure("wim.probe.unreadable", "WIM probe cancelled."));
                }

                return Result.Fail<IReadOnlyList<WimIndexInfo>, Failure>(
                    new Failure("wim.probe.unreadable", "WIM probe timed out."));
            }

            if (captured.ExitStatus.ExitCode != 0)
            {
                string combined = (stdout + "\n" + stderr).Trim();
                string code = ExtractProbeCode(combined) ?? "wim.probe.unreadable";
                string message = string.IsNullOrWhiteSpace(combined)
                    ? $"WIM probe exited {captured.ExitStatus.ExitCode}."
                    : combined;
                return Result.Fail<IReadOnlyList<WimIndexInfo>, Failure>(
                    new Failure(code, message));
            }

            return SourceWimProbe.ParseListJson(stdout.Trim());
        }
        catch (OperationCanceledException)
        {
            return Result.Fail<IReadOnlyList<WimIndexInfo>, Failure>(
                new Failure("wim.probe.unreadable", "WIM probe cancelled."));
        }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            return Result.Fail<IReadOnlyList<WimIndexInfo>, Failure>(
                new Failure("wim.probe.unreadable", ex.Message));
        }
    }

    private static string? ExtractProbeCode(string text)
    {
        const string prefix = "wim.probe.";
        int at = text.IndexOf(prefix, StringComparison.OrdinalIgnoreCase);
        if (at < 0)
        {
            return null;
        }

        int end = at;
        while (end < text.Length)
        {
            char c = text[end];
            if (char.IsLetterOrDigit(c) || c is '.' or '_')
            {
                end++;
                continue;
            }

            break;
        }

        return text[at..end];
    }

    private static string? FindWimMetadataScript() =>
        ToolkitRoot.TryFind("servicing", "Get-WimMetadata.ps1");
}
