namespace WinMint.Orchestrator;

/// <summary>Operator-facing Apply failure text (paths only — no secrets).</summary>
public static class ApplyOperatorMessages
{
    public static string FormatFailed(
        string workDirectory,
        string? opcode,
        string? message,
        string? stage,
        string? logPath)
    {
        string body = string.IsNullOrWhiteSpace(message) ? "(no message)" : message.Trim();
        if (!string.IsNullOrWhiteSpace(opcode))
        {
            body = $"{opcode.Trim()}: {body}";
        }

        List<string> parts = [body, $"work={workDirectory}"];
        if (!string.IsNullOrWhiteSpace(stage))
        {
            parts.Add($"stage={stage.Trim()}");
        }

        if (!string.IsNullOrWhiteSpace(logPath))
        {
            parts.Add($"log={logPath.Trim()}");
        }

        return string.Join(" | ", parts);
    }

    public static string FormatCrashed(string workDirectory, int exitCode) =>
        $"Invoke-ServicingPlan exited {exitCode} without writing failure.json. work={workDirectory}; see apply-status.txt / elevated window.";
}
