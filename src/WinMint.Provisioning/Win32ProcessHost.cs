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

        ProcessStartInfo psi = new()
        {
            FileName = fileName,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (string arg in arguments)
        {
            psi.ArgumentList.Add(arg);
        }

        using Process process = Process.Start(psi)
            ?? throw new InvalidOperationException($"Failed to start process '{fileName}'.");

        using (ct.Register(() =>
        {
            try
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                }
            }
            catch
            {
                // ponytail: best-effort cancel kill
            }
        }))
        {
            process.WaitForExit();
        }

        return new ProcessStartResult(process.ExitCode);
    }
}
