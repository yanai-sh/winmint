using System.Diagnostics;
using System.Runtime.Versioning;

namespace WinMint.Provisioning;

[SupportedOSPlatform("windows")]
internal static class Win32WslLinuxUsername
{
    internal static string? TryResolve(string distroInstallId)
    {
        if (string.IsNullOrWhiteSpace(distroInstallId))
        {
            return null;
        }

        try
        {
            using Process process = new()
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = "wsl.exe",
                    ArgumentList = { "-d", distroInstallId.Trim(), "-e", "whoami" },
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                },
            };
            if (!process.Start())
            {
                return null;
            }

            string output = process.StandardOutput.ReadToEnd();
            if (!process.WaitForExit(15_000))
            {
                try
                {
                    process.Kill(entireProcessTree: true);
                }
                catch
                {
                    // ponytail: best-effort timeout cleanup
                }

                return null;
            }

            if (process.ExitCode != 0 || string.IsNullOrWhiteSpace(output))
            {
                return null;
            }

            return output.Trim();
        }
        catch
        {
            return null;
        }
    }
}
