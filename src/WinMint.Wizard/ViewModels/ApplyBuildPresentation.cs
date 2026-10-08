using System.Text.Json;

using WinMint.Orchestrator;

namespace WinMint.Wizard.ViewModels;

internal readonly record struct ApplyBuildPresentation(
    string StageLine,
    string AliveLine,
    string StatusTail,
    double? ProgressPercent,
    bool IsProgressIndeterminate,
    string? StepCue,
    string? FailureDetail,
    string? TranscriptHint)
{
    public override string ToString() =>
        string.IsNullOrEmpty(StatusTail)
            ? StageLine
            : StageLine + Environment.NewLine + StatusTail;
}

internal static class ApplyBuildPresentationFormat
{
    private static readonly JsonSerializerOptions FailureJsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    internal static ApplyBuildPresentation? FromApplyProgress(
        ApplyProgress? snapshot,
        Func<string, int, IReadOnlyList<ApplyEvent>>? readEventsTail = null,
        int maxEvents = 40,
        string? workDirectory = null)
    {
        if (snapshot is null || string.IsNullOrWhiteSpace(snapshot.Value.Stage))
        {
            return null;
        }

        string stage = snapshot.Value.Stage;
        if (stage.Equals("idle", StringComparison.OrdinalIgnoreCase)
            || stage.Equals("done", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        bool failed = stage.StartsWith("failed:", StringComparison.OrdinalIgnoreCase);
        string display = failed ? stage["failed:".Length..] : stage;
        string stageLine = failed ? $"Failed: {display}" : $"Building: {display}";

        string? eventsPath = !string.IsNullOrWhiteSpace(snapshot.Value.LogPath)
            ? snapshot.Value.LogPath
            : string.IsNullOrWhiteSpace(workDirectory) ? null : ApplyEvents.PathFor(workDirectory);

        IReadOnlyList<ApplyEvent> events = [];
        if (!string.IsNullOrWhiteSpace(eventsPath))
        {
            try
            {
                Func<string, int, IReadOnlyList<ApplyEvent>> reader = readEventsTail ?? ApplyEvents.ReadTail;
                events = reader(eventsPath, maxEvents);
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }

        double? progressPercent = ApplyEvents.TryLatestProofPercent(events);
        string? stepCue = ApplyEvents.TryLatestStepCue(events);
        string statusTail = string.Join(Environment.NewLine, ApplyEvents.FormatRows(events));

        string? failureDetail = null;
        string? transcriptHint = null;
        if (!string.IsNullOrWhiteSpace(workDirectory))
        {
            if (failed)
            {
                failureDetail = TryReadFailureMessage(workDirectory);
            }

            string transcriptPath = Path.Combine(workDirectory, "dism-transcript.log");
            if (File.Exists(transcriptPath))
            {
                transcriptHint = $"DISM transcript: {transcriptPath}";
            }
        }

        return new ApplyBuildPresentation(
            stageLine,
            "working…",
            statusTail,
            progressPercent,
            progressPercent is null,
            stepCue,
            failureDetail,
            transcriptHint);
    }

    private static string? TryReadFailureMessage(string workDirectory)
    {
        string path = Path.Combine(workDirectory, ServicingWorkspace.FailureFileName);
        if (!File.Exists(path))
        {
            return null;
        }

        try
        {
            using FileStream stream = new(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            FailureMessageDto? dto = JsonSerializer.Deserialize<FailureMessageDto>(stream, FailureJsonOptions);
            return string.IsNullOrWhiteSpace(dto?.Message) ? null : dto.Message.Trim();
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private sealed record FailureMessageDto(string? Message);
}
