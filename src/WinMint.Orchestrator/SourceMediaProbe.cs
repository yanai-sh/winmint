using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Orchestrator;

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
            if (!string.IsNullOrWhiteSpace(Architecture)) bits.Add(Architecture);
            if (!string.IsNullOrWhiteSpace(Edition)) bits.Add(Edition);
            if (!string.IsNullOrWhiteSpace(Build)) bits.Add(Build);
            else if (!string.IsNullOrWhiteSpace(Version)) bits.Add(Version);
            string suffix = bits.Count == 0 ? "" : $" ({string.Join(", ", bits)})";
            return $"{Index} — {Name}{suffix}";
        }
    }
}

public sealed record SelectedWim(
    int Index,
    string Name,
    string? Architecture,
    string? Edition,
    string? Version,
    string? Build);

public sealed record SourceMediaReview(
    string SourceIsoPath,
    string SourceIsoSha256,
    IReadOnlyList<WimIndexInfo> Indexes,
    SelectedWim? Selected,
    SourceMediaSelectionMismatch? SelectionMismatch = null);

public sealed record SourceMediaSelectionMismatch(
    int RequestedWimIndex,
    string Code,
    string Message);

/// <summary>Unelevated Source ISO identity and WIM metadata seam.</summary>
public interface ISourceMediaProbe
{
    Task<Result<SourceMediaReview, Failure>> ProbeAsync(
        string sourceIsoPath,
        int wimIndex,
        CancellationToken cancellationToken = default);

    /// <summary>WIM index list only — must not SHA-256 the ISO. Compose hashes once via <see cref="ProbeAsync"/>.</summary>
    Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> ListIndexesAsync(
        string sourceIsoPath,
        CancellationToken cancellationToken = default)
    {
        async Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> FromProbe()
        {
            Result<SourceMediaReview, Failure> probed =
                await ProbeAsync(sourceIsoPath, ImageServicing.DefaultProWimIndex, cancellationToken)
                    .ConfigureAwait(false);
            return probed.IsOk
                ? Result.Ok<IReadOnlyList<WimIndexInfo>, Failure>(probed.Value.Indexes)
                : Result.Fail<IReadOnlyList<WimIndexInfo>, Failure>(probed.Error);
        }

        return FromProbe();
    }
}

public sealed class SourceMediaProbe : ISourceMediaProbe
{
    public static SourceMediaProbe Instance { get; } = new();

    public Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> ListIndexesAsync(
        string sourceIsoPath,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(sourceIsoPath) || !File.Exists(sourceIsoPath.Trim()))
        {
            return Task.FromResult(Result.Fail<IReadOnlyList<WimIndexInfo>, Failure>(
                new Failure("wim.probe.isoMissing", $"Source ISO not found: {sourceIsoPath}")));
        }

        return PwshWimIndexSource.ListFromIsoAsync(Path.GetFullPath(sourceIsoPath.Trim()), cancellationToken);
    }

    public async Task<Result<SourceMediaReview, Failure>> ProbeAsync(
        string sourceIsoPath,
        int wimIndex,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(sourceIsoPath) || !File.Exists(sourceIsoPath.Trim()))
        {
            return Result.Fail<SourceMediaReview, Failure>(
                new Failure("wim.probe.isoMissing", $"Source ISO not found: {sourceIsoPath}"));
        }

        string fullPath = Path.GetFullPath(sourceIsoPath.Trim());
        Result<IReadOnlyList<WimIndexInfo>, Failure> listed =
            await PwshWimIndexSource.ListFromIsoAsync(fullPath, cancellationToken).ConfigureAwait(false);
        if (!listed.IsOk)
        {
            return Result.Fail<SourceMediaReview, Failure>(listed.Error);
        }

        WimIndexInfo? selected = listed.Value.FirstOrDefault(row => row.Index == wimIndex);

        try
        {
            await using FileStream stream = new(
                fullPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 1024 * 1024,
                useAsync: true);
            byte[] hash = await SHA256.HashDataAsync(stream, cancellationToken).ConfigureAwait(false);
            return Result.Ok<SourceMediaReview, Failure>(
                new SourceMediaReview(
                    fullPath,
                    Convert.ToHexStringLower(hash),
                    Array.AsReadOnly(listed.Value.ToArray()),
                    selected is null
                        ? null
                        : new SelectedWim(
                            selected.Index,
                            selected.Name,
                            selected.Architecture,
                            selected.Edition,
                            selected.Version,
                            selected.Build),
                    selected is null
                        ? new SourceMediaSelectionMismatch(
                            wimIndex,
                            "wim.probe.indexMissing",
                            $"Source ISO does not contain WIM index {wimIndex}.")
                        : null));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return Result.Fail<SourceMediaReview, Failure>(
                new Failure("sourceMedia.hash.unreadable", ex.Message));
        }
    }
}

/// <summary>Wizard list-only facade over the HostCompile source-media adapter.</summary>
public static class SourceWimProbe
{
    public static async Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> TryProbeIsoAsync(
        string isoPath,
        ISourceMediaProbe? source = null,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(isoPath) || !File.Exists(isoPath.Trim()))
        {
            return Result.Fail<IReadOnlyList<WimIndexInfo>, Failure>(
                new Failure("wim.probe.isoMissing", $"Source ISO not found: {isoPath}"));
        }

        Result<IReadOnlyList<WimIndexInfo>, Failure> listed =
            await (source ?? SourceMediaProbe.Instance)
                .ListIndexesAsync(isoPath.Trim(), cancellationToken)
                .ConfigureAwait(false);
        return listed;
    }

    public static Result<IReadOnlyList<WimIndexInfo>, Failure> ParseListJson(string json)
    {
        try
        {
            WimIndexListFile? file = JsonSerializer.Deserialize(json, SourceMediaJsonContext.Default.WimIndexListFile);
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
                        new Failure("wim.probe.incompleteName", $"Index {row.Index} Name is missing or undefined."));
                }

                rows.Add(new(
                    row.Index,
                    row.Name!.Trim(),
                    NullIfEmpty(row.Architecture),
                    NullIfEmpty(row.Edition),
                    NullIfEmpty(row.Version),
                    NullIfEmpty(row.Build)));
            }

            return Result.Ok<IReadOnlyList<WimIndexInfo>, Failure>(Array.AsReadOnly(rows.ToArray()));
        }
        catch (JsonException ex)
        {
            return Result.Fail<IReadOnlyList<WimIndexInfo>, Failure>(
                new Failure("wim.probe.unreadable", ex.Message));
        }
    }

    public static int ResolveSelection(
        IReadOnlyList<WimIndexInfo> rows,
        int currentIndex,
        bool userChose,
        int hostDefault) =>
        userChose && rows.Any(row => row.Index == currentIndex) ? currentIndex : hostDefault;

    internal static bool IsUndefinedName(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return true;
        string trimmed = value.Trim();
        return trimmed.Equals("undefined", StringComparison.OrdinalIgnoreCase)
            || trimmed.Equals("<undefined>", StringComparison.OrdinalIgnoreCase);
    }

    private static string? NullIfEmpty(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}

internal static class PwshWimIndexSource
{
    public static async Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> ListFromIsoAsync(
        string isoPath,
        CancellationToken cancellationToken = default)
    {
        string? script = ToolkitRoot.TryFind("servicing", "Get-WimMetadata.ps1");
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
            using CancellationTokenSource timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(120));
            ProcessTextOutput captured = await Process.RunAndCaptureTextAsync(psi, timeout.Token).ConfigureAwait(false);
            if (captured.ExitStatus.Canceled || timeout.IsCancellationRequested)
            {
                string message = cancellationToken.IsCancellationRequested
                    ? "WIM probe cancelled."
                    : "WIM probe timed out.";
                return Result.Fail<IReadOnlyList<WimIndexInfo>, Failure>(
                    new Failure("wim.probe.unreadable", message));
            }

            if (captured.ExitStatus.ExitCode != 0)
            {
                string combined = (captured.StandardOutput + "\n" + captured.StandardError).Trim();
                return Result.Fail<IReadOnlyList<WimIndexInfo>, Failure>(
                    new Failure(
                        ExtractProbeCode(combined) ?? "wim.probe.unreadable",
                        string.IsNullOrWhiteSpace(combined)
                            ? $"WIM probe exited {captured.ExitStatus.ExitCode}."
                            : combined));
            }

            return SourceWimProbe.ParseListJson(captured.StandardOutput.Trim());
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
        if (at < 0) return null;
        int end = at;
        while (end < text.Length
            && (char.IsLetterOrDigit(text[end]) || text[end] is '.' or '_'))
        {
            end++;
        }
        return text[at..end];
    }
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
internal sealed partial class SourceMediaJsonContext : JsonSerializerContext;
