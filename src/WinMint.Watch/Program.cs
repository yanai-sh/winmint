using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

using Spectre.Console;
using Spectre.Console.Rendering;

using WinMint.Orchestrator;

namespace WinMint.Watch;

internal static class Program
{
    private const int RefreshSeconds = 2;
    private const int DoneTicksToExit = 3;

    private static int Main(string[] args)
    {
        if (!TryParseArgs(args, out string work, out string kind, out string priorRunId, out string markerPath))
        {
            AnsiConsole.MarkupLine("[red]Usage:[/] WinMint.Watch --work <dir> [--kind smoke|apply] [--prior-run-id id] [--marker-path file]");
            return 2;
        }

        if (!Directory.Exists(work))
        {
            AnsiConsole.MarkupLine($"[red]Work directory not found:[/] {Markup.Escape(work)}");
            return 2;
        }

        work = Path.GetFullPath(work);
        string applyStatusPath = Path.Combine(work, ServicingWorkspace.ApplyStatusFileName);
        string smokeStatusPath = Path.Combine(work, "smoke-status.json");
        bool isSmoke = string.Equals(kind, "smoke", StringComparison.OrdinalIgnoreCase);
        string title = isSmoke ? $"WinMint host watch — {work}" : $"WinMint apply watch — {work}";

        if (!string.IsNullOrWhiteSpace(markerPath))
        {
            try
            {
                File.WriteAllText(markerPath, Environment.ProcessId.ToString(CultureInfo.InvariantCulture));
            }
            catch (IOException)
            {
                // ponytail: marker is best-effort for spawn polling
            }
        }

        using CancellationTokenSource cts = new();
        Console.CancelKeyPress += (_, e) =>
        {
            e.Cancel = true;
            cts.Cancel();
        };

        System.Diagnostics.Stopwatch? statusAge = null;
        string lastSmokeFingerprint = string.Empty;
        int doneTicks = 0;

        try
        {
            AnsiConsole.Live(new Markup("…"))
                .AutoClear(false)
                .Overflow(VerticalOverflow.Ellipsis)
                .Start(ctx =>
                {
                    while (!cts.Token.IsCancellationRequested)
                    {
                        ApplyStatusSnap apply = ReadApplyStatus(applyStatusPath);
                        SmokeStatusSnap? smoke = isSmoke ? ReadSmokeStatus(smokeStatusPath) : null;
                        string eventsPath = !string.IsNullOrWhiteSpace(apply.Log) ? apply.Log : ApplyEvents.PathFor(work);
                        IReadOnlyList<ApplyEvent> events = ApplyEvents.ReadTail(eventsPath);
                        int summaryWidth = Math.Max(24, Math.Min(80, Console.WindowWidth - 44));
                        IReadOnlyList<string> rows = ApplyEvents.FormatRows(events, summaryWidth);

                        string verdict = string.Empty;
                        string phase = string.Empty;
                        int stallLeft = 0;
                        int wallLeft = 0;
                        int smokeStatusAgeSeconds = 0;
                        string lastHostLine = string.Empty;
                        if (isSmoke && smoke is not null)
                        {
                            string fp = $"{smoke.RunId}|{smoke.Phase}|{smoke.UpdatedAt}|{smoke.VmState}|{smoke.VhdFileSizeMB}";
                            if (!string.Equals(fp, lastSmokeFingerprint, StringComparison.Ordinal))
                            {
                                lastSmokeFingerprint = fp;
                                statusAge = System.Diagnostics.Stopwatch.StartNew();
                            }

                            smokeStatusAgeSeconds = statusAge is null ? 0 : (int)statusAge.Elapsed.TotalSeconds;
                            int emptyVhdSeconds = smoke.VmState == "Running" && smoke.VhdFileSizeMB < 1024 ? smokeStatusAgeSeconds : 0;
                            verdict = GetSmokeWatchVerdict(
                                smoke.Phase,
                                smoke.VmState,
                                smoke.VhdFileSizeMB,
                                smokeStatusAgeSeconds,
                                emptyVhdSeconds,
                                smoke.RunId,
                                priorRunId);
                            phase = smoke.Phase;
                            stallLeft = smoke.StallMinutesLeft;
                            wallLeft = smoke.WallMinutesLeft;
                            lastHostLine = smoke.LastHostLine ?? string.Empty;
                        }

                        string alive = FormatAlive(apply.Updated);
                        double? proofPct = ApplyEvents.TryLatestProofPercent(events);
                        ctx.UpdateTarget(BuildFrame(
                            title,
                            apply.Stage,
                            alive,
                            proofPct,
                            isSmoke,
                            verdict,
                            phase,
                            stallLeft,
                            wallLeft,
                            smokeStatusAgeSeconds,
                            lastHostLine,
                            rows,
                            work,
                            events));

                        if (isSmoke && string.Equals(verdict, "done", StringComparison.Ordinal))
                        {
                            doneTicks++;
                            if (doneTicks >= DoneTicksToExit)
                            {
                                break;
                            }
                        }
                        else
                        {
                            doneTicks = 0;
                        }

                        Thread.Sleep(TimeSpan.FromSeconds(RefreshSeconds));
                    }
                });
        }
        catch (OperationCanceledException)
        {
            // Ctrl+C
        }

        return 0;
    }

    private static Rows BuildFrame(
        string title,
        string applyStage,
        string alive,
        double? proofPct,
        bool isSmoke,
        string verdict,
        string phase,
        int stallLeft,
        int wallLeft,
        int smokeStatusAgeSeconds,
        string lastHostLine,
        IReadOnlyList<string> rows,
        string work,
        IReadOnlyList<ApplyEvent> events)
    {
        List<IRenderable> header = [new Markup($"[bold]{Markup.Escape(title)}[/]")];
        if (isSmoke)
        {
            header.Add(new Markup(SmokeWatchDisplay.BuildSmokeHeaderMarkup(
                verdict, phase, stallLeft, wallLeft, smokeStatusAgeSeconds)));
            if (SmokeWatchDisplay.IsAlarmVerdict(verdict) && !string.IsNullOrWhiteSpace(lastHostLine))
            {
                int clipWidth = Math.Max(24, Math.Min(80, Console.WindowWidth - 44));
                string clipped = SmokeWatchDisplay.ClipHostLine(lastHostLine.Trim(), clipWidth);
                header.Add(new Markup($"last  {Markup.Escape(clipped)}"));
            }
        }

        applyStage ??= string.Empty;
        rows ??= [];
        events ??= [];

        string stageLine = string.IsNullOrWhiteSpace(applyStage) ? "-" : applyStage;
        string proof = proofPct is null ? string.Empty : $"  proof {proofPct.Value:0.#}%";
        header.Add(new Markup($"stage [cyan]{Markup.Escape(stageLine)}[/]  {Markup.Escape(alive)}{proof}"));

        Table table = new();
        table.AddColumn("Time");
        table.AddColumn("Opcode");
        table.AddColumn("Outcome");
        table.AddColumn("Summary");
        table.Border(TableBorder.Rounded);
        foreach (string row in rows)
        {
            if (string.IsNullOrEmpty(row))
            {
                continue;
            }

            string[] parts = SplitRow(row);
            table.AddRow(
                new Markup(Markup.Escape(parts[0])),
                new Markup(Markup.Escape(parts[1])),
                ColorOutcome(parts[2]),
                new Markup(Markup.Escape(parts[3])));
        }

        string footer = "[dim]Ctrl+C to quit[/]";
        ApplyEvent? lastFail = events.LastOrDefault(e =>
            e is not null
            && string.Equals(e.Kind, "opcode.end", StringComparison.Ordinal)
            && string.Equals(e.Outcome, "fail", StringComparison.Ordinal));
        if (lastFail is not null)
        {
            string hint = lastFail.Error?.TranscriptHint ?? lastFail.Error?.Message ?? lastFail.Summary ?? "failed";
            footer = $"[red]{Markup.Escape(hint)}[/]  " + footer;
        }
        else if (applyStage.StartsWith("failed", StringComparison.OrdinalIgnoreCase))
        {
            string failPath = Path.Combine(work, ServicingWorkspace.FailureFileName);
            footer = File.Exists(failPath)
                ? $"[red]see {Markup.Escape(failPath)}[/]  " + footer
                : "[red]Apply failed[/]  " + footer;
        }

        return new Rows([.. header, new Rule(), table, new Markup(footer)]);
    }

    private static Markup ColorOutcome(string outcome)
    {
        if (string.Equals(outcome, "ok", StringComparison.OrdinalIgnoreCase))
        {
            return new Markup($"[green]{Markup.Escape(outcome)}[/]");
        }

        if (string.Equals(outcome, "fail", StringComparison.OrdinalIgnoreCase))
        {
            return new Markup($"[red]{Markup.Escape(outcome)}[/]");
        }

        return new Markup(Markup.Escape(outcome));
    }

    private static string[] SplitRow(string row)
    {
        // FormatRow: "{time}  {opcode,-22}  {outcome,-4}  {summary}"
        ReadOnlySpan<char> span = row.AsSpan().TrimEnd();
        int i = 0;
        while (i < span.Length && span[i] != ' ')
        {
            i++;
        }

        string time = span[..i].ToString();
        span = span[i..].TrimStart();
        string opcode = TakeToken(ref span, 22);
        string outcome = TakeToken(ref span, 4);
        string summary = span.TrimStart().ToString();
        return [time, opcode.Trim(), outcome.Trim(), summary];
    }

    private static string TakeToken(ref ReadOnlySpan<char> span, int fieldWidth)
    {
        if (span.IsEmpty)
        {
            return string.Empty;
        }

        int end = Math.Min(span.Length, fieldWidth);
        while (end > 0 && span[end - 1] == ' ')
        {
            end--;
        }

        string token = span[..end].ToString();
        span = span.Length > fieldWidth ? span[fieldWidth..].TrimStart() : [];
        return token;
    }

    private static string FormatAlive(DateTimeOffset? updated)
    {
        if (updated is null)
        {
            return "alive -";
        }

        double seconds = Math.Max(0, (DateTimeOffset.UtcNow - updated.Value).TotalSeconds);
        return seconds > 120 ? $"status stale {seconds:0}s" : $"alive {seconds:0}s";
    }

    private static string GetSmokeWatchVerdict(
        string phase,
        string vmState,
        int vhdFileSizeMb,
        int statusAgeSeconds,
        int emptyVhdRunningSeconds,
        string statusRunId,
        string priorRunId)
    {
        if (!string.IsNullOrEmpty(priorRunId) && string.Equals(statusRunId, priorRunId, StringComparison.Ordinal))
        {
            return "awaiting-run";
        }

        if (phase is "green" or "failed" or "assert")
        {
            return "done";
        }

        if (string.Equals(phase, "apply", StringComparison.Ordinal))
        {
            return "continue";
        }

        if (string.Equals(vmState, "Running", StringComparison.Ordinal)
            && vhdFileSizeMb < 1024
            && emptyVhdRunningSeconds >= 480)
        {
            return "empty-vhd";
        }

        if (statusAgeSeconds > 120)
        {
            return "harness-stale";
        }

        return "continue";
    }

    private static ApplyStatusSnap ReadApplyStatus(string path)
    {
        if (!File.Exists(path))
        {
            return new ApplyStatusSnap(string.Empty, string.Empty, null);
        }

        try
        {
            string stage = string.Empty;
            string log = string.Empty;
            DateTimeOffset? updated = null;
            foreach (string line in File.ReadLines(path))
            {
                if (line.StartsWith("stage=", StringComparison.Ordinal))
                {
                    stage = line[6..];
                }
                else if (line.StartsWith("log=", StringComparison.Ordinal))
                {
                    log = line[4..];
                }
                else if (line.StartsWith("updated=", StringComparison.Ordinal)
                    && DateTimeOffset.TryParse(line[8..], CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out DateTimeOffset dto))
                {
                    updated = dto;
                }
            }

            return new ApplyStatusSnap(stage, log, updated);
        }
        catch (IOException)
        {
            return new ApplyStatusSnap(string.Empty, string.Empty, null);
        }
        catch (UnauthorizedAccessException)
        {
            return new ApplyStatusSnap(string.Empty, string.Empty, null);
        }
    }

    private static SmokeStatusSnap? ReadSmokeStatus(string path)
    {
        if (!File.Exists(path))
        {
            return null;
        }

        try
        {
            using FileStream stream = new(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            return JsonSerializer.Deserialize(stream, SmokeStatusJsonContext.Default.SmokeStatusSnap);
        }
        catch (JsonException)
        {
            return null;
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }

    private static bool TryParseArgs(
        string[] args,
        out string work,
        out string kind,
        out string priorRunId,
        out string markerPath)
    {
        work = string.Empty;
        kind = "apply";
        priorRunId = string.Empty;
        markerPath = string.Empty;
        for (int i = 0; i < args.Length; i++)
        {
            string arg = args[i];
            if (string.Equals(arg, "--work", StringComparison.Ordinal) && i + 1 < args.Length)
            {
                work = args[++i];
                continue;
            }

            if (string.Equals(arg, "--kind", StringComparison.Ordinal) && i + 1 < args.Length)
            {
                kind = args[++i];
                continue;
            }

            if (string.Equals(arg, "--prior-run-id", StringComparison.Ordinal) && i + 1 < args.Length)
            {
                priorRunId = args[++i];
                continue;
            }

            if (string.Equals(arg, "--marker-path", StringComparison.Ordinal) && i + 1 < args.Length)
            {
                markerPath = args[++i];
            }
        }

        return !string.IsNullOrWhiteSpace(work)
            && (string.Equals(kind, "smoke", StringComparison.OrdinalIgnoreCase)
                || string.Equals(kind, "apply", StringComparison.OrdinalIgnoreCase));
    }

    private readonly record struct ApplyStatusSnap(string Stage, string Log, DateTimeOffset? Updated);
}

internal sealed record SmokeStatusSnap(
    [property: JsonPropertyName("runId")] string RunId = "",
    [property: JsonPropertyName("phase")] string Phase = "",
    [property: JsonPropertyName("updatedAt")] string UpdatedAt = "",
    [property: JsonPropertyName("vmState")] string VmState = "",
    [property: JsonPropertyName("vhdFileSizeMB")] int VhdFileSizeMB = 0,
    [property: JsonPropertyName("stallMinutesLeft")] int StallMinutesLeft = 0,
    [property: JsonPropertyName("wallMinutesLeft")] int WallMinutesLeft = 0,
    [property: JsonPropertyName("lastHostLine")] string? LastHostLine = null);

[JsonSerializable(typeof(SmokeStatusSnap))]
internal sealed partial class SmokeStatusJsonContext : JsonSerializerContext;
