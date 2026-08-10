using Microsoft.Extensions.Logging;

namespace WinMint.Cli;

/// <summary>Minimal <see cref="ILogger"/> that writes Info to stdout and Warning+ to stderr (no Console package).</summary>
internal sealed class ConsoleCliLogger : ILogger
{
    public static ConsoleCliLogger Instance { get; } = new();

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

        string line = formatter(state, exception);
        if (logLevel >= LogLevel.Warning)
        {
            Console.Error.WriteLine(line);
        }
        else
        {
            Console.WriteLine(line);
        }
    }
}
