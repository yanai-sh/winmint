using Microsoft.Extensions.Logging;

namespace WinMint.Provisioning;

/// <summary>
/// Minimal <see cref="ILogger"/> for guest tenure: stderr + ProgramData file (no Console logging package).
/// </summary>
internal sealed class GuestFileLogger(string logPath) : ILogger
{
    public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

    public bool IsEnabled(LogLevel logLevel) => logLevel != LogLevel.None;

    public void Log<TState>(
        LogLevel logLevel,
        EventId eventId,
        TState state,
        Exception? exception,
        Func<TState, Exception?, string> formatter)
    {
        if (!IsEnabled(logLevel))
        {
            return;
        }

        string stamped = $"{DateTimeOffset.UtcNow:o} {formatter(state, exception)}";
        Console.Error.WriteLine(stamped);
        try
        {
            File.AppendAllText(logPath, stamped + Environment.NewLine);
        }
        catch
        {
            // ponytail: best-effort ProgramData log
        }
    }
}
