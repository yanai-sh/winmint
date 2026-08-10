using System.Diagnostics;
using System.Runtime.Versioning;

namespace WinMint.Provisioning;

[SupportedOSPlatform("windows")]
public sealed class Win32ProcessHost : IProcessHost
{
    public ProcessStartResult Run(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken ct = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(fileName);
        ArgumentNullException.ThrowIfNull(arguments);

        // Sync Process.Run has timeout but no mid-flight CancellationToken (RunAsync does).
        // Check before start only — callers that need kill-on-cancel must go async later.
        ct.ThrowIfCancellationRequested();

        ProcessExitStatus status = Process.Run(
            fileName,
            arguments as IList<string> ?? [.. arguments],
            silent: true,
            timeout: null);

        return new ProcessStartResult(status.ExitCode);
    }
}
