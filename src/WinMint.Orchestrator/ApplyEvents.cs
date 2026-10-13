using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Orchestrator;

/// <summary>Operator apply-events.jsonl (wide events). Shared by Wizard and Watch.</summary>
public static class ApplyEvents
{
    public const string FileName = "apply-events.jsonl";

    /// <summary>Monospace opcode field for <see cref="FormatRow"/> (covers every ServicingOpcode).</summary>
    public const int OpcodeFieldWidth = 24;

    public static string PathFor(string workDirectory) =>
        System.IO.Path.Combine(workDirectory, FileName);

    public static IReadOnlyList<ApplyEvent> ReadTail(string path, int maxEvents = 40)
    {
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            return [];
        }

        try
        {
            using FileStream stream = new(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using StreamReader reader = new(stream);
            List<ApplyEvent> all = [];
            while (reader.ReadLine() is { } line)
            {
                if (string.IsNullOrWhiteSpace(line))
                {
                    continue;
                }

                ApplyEvent? ev = TryParse(line);
                if (ev is not null)
                {
                    all.Add(ev);
                }
            }

            if (all.Count <= maxEvents)
            {
                return all;
            }

            return [.. all.TakeLast(maxEvents)];
        }
        catch (IOException)
        {
            return [];
        }
        catch (UnauthorizedAccessException)
        {
            return [];
        }
    }

    public static ApplyEvent? TryParse(string line)
    {
        try
        {
            return JsonSerializer.Deserialize(line, ApplyEventJsonContext.Default.ApplyEvent);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// <summary>
    /// Operator table rows: keep non-proof events; keep only the latest proof per (opcode, label);
    /// then take the last <paramref name="maxRows"/> so proof ticks cannot evict stage history.
    /// </summary>
    public static IReadOnlyList<ApplyEvent> ForDisplay(IEnumerable<ApplyEvent> events, int maxRows = 40)
    {
        List<ApplyEvent> rows = [];
        Dictionary<string, int> proofSlot = new(StringComparer.Ordinal);
        foreach (ApplyEvent ev in events)
        {
            if (string.Equals(ev.Kind, "proof", StringComparison.Ordinal))
            {
                string key = (ev.Opcode ?? string.Empty) + "\0" + (ev.Label ?? string.Empty);
                if (proofSlot.TryGetValue(key, out int index))
                {
                    rows[index] = ev;
                }
                else
                {
                    proofSlot[key] = rows.Count;
                    rows.Add(ev);
                }

                continue;
            }

            rows.Add(ev);
        }

        if (rows.Count <= maxRows)
        {
            return rows;
        }

        return [.. rows.TakeLast(maxRows)];
    }

    public static string DisplayTime(ApplyEvent ev) => TryFormatTime(ev.Ts);

    public static string DisplayOpcode(ApplyEvent ev) =>
        string.IsNullOrWhiteSpace(ev.Opcode) ? ev.Kind : ev.Opcode;

    public static string DisplayOutcome(ApplyEvent ev) =>
        string.IsNullOrWhiteSpace(ev.Outcome) ? "-" : ev.Outcome;

    public static string DisplaySummary(ApplyEvent ev, int summaryWidth = 60)
    {
        string summary = ev.Summary ?? string.Empty;
        string opcode = DisplayOpcode(ev);
        if (opcode.Length > 0
            && summary.StartsWith(opcode, StringComparison.Ordinal)
            && summary.Length > opcode.Length
            && summary[opcode.Length] == ' ')
        {
            summary = summary[(opcode.Length + 1)..];
        }

        return Clip(summary, Math.Max(8, summaryWidth));
    }

    public static string FormatRow(ApplyEvent ev, int summaryWidth = 60)
    {
        string time = DisplayTime(ev);
        string opcode = Clip(DisplayOpcode(ev), OpcodeFieldWidth);
        string outcome = DisplayOutcome(ev);
        string summary = DisplaySummary(ev, summaryWidth);
        return $"{time}  {opcode,-24}  {outcome,-4}  {summary}";
    }

    public static IReadOnlyList<string> FormatRows(IEnumerable<ApplyEvent> events, int summaryWidth = 60) =>
        [.. ForDisplay(events).Select(e => FormatRow(e, summaryWidth))];

    public static double? TryLatestProofPercent(IEnumerable<ApplyEvent> events)
    {
        foreach (ApplyEvent ev in events.Reverse())
        {
            if (!string.Equals(ev.Kind, "proof", StringComparison.Ordinal)
                || ev.Percent is null)
            {
                continue;
            }

            return Math.Clamp(ev.Percent.Value, 0, 100);
        }

        return null;
    }

    public static string? TryLatestStepCue(IEnumerable<ApplyEvent> events)
    {
        foreach (ApplyEvent ev in events.Reverse())
        {
            if (!string.Equals(ev.Kind, "opcode.end", StringComparison.Ordinal)
                || ev.Index is null
                || ev.Count is null
                || ev.Index <= 0
                || ev.Count <= 0)
            {
                continue;
            }

            return $"Step {ev.Index} of {ev.Count}";
        }

        return null;
    }

    private static string TryFormatTime(string? ts)
    {
        if (string.IsNullOrWhiteSpace(ts))
        {
            return "--:--:--";
        }

        if (DateTimeOffset.TryParse(ts, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out DateTimeOffset dto))
        {
            return dto.ToLocalTime().ToString("HH:mm:ss", CultureInfo.InvariantCulture);
        }

        return ts.Length >= 8 ? ts[^8..] : ts;
    }

    private static string Clip(string text, int max)
    {
        if (text.Length <= max)
        {
            return text;
        }

        return text[..(max - 1)] + "…";
    }
}

public sealed record ApplyEvent(
    [property: JsonPropertyName("ts")] string? Ts = null,
    [property: JsonPropertyName("runId")] string? RunId = null,
    [property: JsonPropertyName("kind")] string Kind = "",
    [property: JsonPropertyName("opcode")] string? Opcode = null,
    [property: JsonPropertyName("index")] int? Index = null,
    [property: JsonPropertyName("count")] int? Count = null,
    [property: JsonPropertyName("outcome")] string? Outcome = null,
    [property: JsonPropertyName("durationMs")] int? DurationMs = null,
    [property: JsonPropertyName("summary")] string? Summary = null,
    [property: JsonPropertyName("label")] string? Label = null,
    [property: JsonPropertyName("percent")] double? Percent = null,
    [property: JsonPropertyName("error")] ApplyEventError? Error = null);

public sealed record ApplyEventError(
    [property: JsonPropertyName("message")] string? Message = null,
    [property: JsonPropertyName("transcriptHint")] string? TranscriptHint = null);

[JsonSerializable(typeof(ApplyEvent))]
[JsonSourceGenerationOptions(PropertyNameCaseInsensitive = true)]
internal partial class ApplyEventJsonContext : JsonSerializerContext;
