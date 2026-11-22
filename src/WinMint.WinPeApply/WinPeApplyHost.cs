using System.Diagnostics;
using System.Text;

namespace WinMint.WinPeApply;

/// <summary>
/// Windows-subsystem WinPE host. winpeshl [LaunchApp] cannot pass arguments, so this exe
/// CREATE_NO_WINDOW-launches LaunchApply.cmd beside it. Failures reopen a console with the log —
/// disk-guard refusals must stay visible (#119).
/// ponytail: Native AOT WinExe in WinPE. The boot surface is a fullscreen black window that paints
/// the embedded dark lockup; LaunchApply stays CreateProcess. If a Source ISO WinPE lacks an API
/// the runtime needs, replace this host with a C Win32 stub; keep LaunchApply.cmd.
/// </summary>
internal static class WinPeApplyHost
{
    internal const string LaunchName = "LaunchApply.cmd";
    internal const string FormatFlagName = "winmint-format-started.txt";
    private const string QuickEditSkip = "WINMINT_QE";

    /// <summary>Escape before format stops the launcher. Escape after the format flag exists does not.</summary>
    internal static bool KillForEscape(bool requested, bool formatStarted) => requested && !formatStarted;

    private static int Main(string[] args)
    {
        ApplyBootSplash.EnablePerMonitorV2();
        return Dispatch(
            args,
            () => Run(AppContext.BaseDirectory, holdFailureConsole: true),
            ApplyBootSplash.HoldForPreview);
    }

    /// <summary>
    /// <c>--splash</c> is the host preview of the disk prompt. It does not start LaunchApply.
    /// <c>--bus-types</c> writes bus types for LaunchApply before it chooses a disk.
    /// </summary>
    internal static int Dispatch(string[] args, Func<int> runApply, Action showSplash)
    {
        // winpeshl cannot pass arguments. LaunchApply calls these modes itself before it formats.
        if (args.Length == 3 && string.Equals(args[0], "--image-fits", StringComparison.Ordinal))
        {
            return ImageFit.Run(args[1], args[2]);
        }

        if (args.Length == 2 && string.Equals(args[0], "--bus-types", StringComparison.Ordinal))
        {
            (bool complete, List<(int Disk, string Bus)> rows) = DiskBusList.Query();
            File.WriteAllText(args[1], DiskBusList.Render(rows), Encoding.ASCII);
            return complete ? 0 : 1;
        }

        if (args.Length == 1 && string.Equals(args[0], "--splash", StringComparison.Ordinal))
        {
            showSplash();
            return 0;
        }

        return runApply();
    }

    internal static int Run(string system32, bool holdFailureConsole)
    {
        string launch = Path.Combine(system32, LaunchName);
        string log = Path.Combine(Path.GetTempPath(), "winmint-apply.log");
        if (!File.Exists(launch))
        {
            File.WriteAllText(log, "WinMint: LaunchApply.cmd missing next to WinMintApply.exe");
            return ShowFailure(system32, log, holdFailureConsole, 1);
        }

        int code = 1;
        bool started = false;
        using (ApplyBootSplash.TryShow())
        {
            using Process? apply = Process.Start(HiddenLaunch(system32, log));
            if (apply is null)
            {
                File.WriteAllText(log, "WinMint: CreateProcess LaunchApply failed");
            }
            else
            {
                started = true;
                WaitForApply(apply, out code);
            }
        }

        if (!started)
        {
            return ShowFailure(system32, log, holdFailureConsole, 1);
        }

        return code == 0
            ? 0
            : ShowFailure(system32, log, holdFailureConsole, code);
    }

    /// <summary>Escape before format returns a failure. Escape after the format flag exists lets apply finish.</summary>
    private static void WaitForApply(Process apply, out int code)
    {
        bool escape = string.Equals(
            Environment.GetEnvironmentVariable(ApplyBootSplash.EscapeVariable),
            "1",
            StringComparison.Ordinal);
        if (!escape)
        {
            apply.WaitForExit();
            code = apply.ExitCode;
            return;
        }

        string formatFlag = Path.Combine(Path.GetTempPath(), FormatFlagName);
        while (!apply.HasExited)
        {
            if (KillForEscape(ApplyBootSplash.EscapeRequested, File.Exists(formatFlag)))
            {
                try
                {
                    apply.Kill(entireProcessTree: true);
                }
                catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception)
                {
                }

                apply.WaitForExit();
                code = 1;
                return;
            }

            if (apply.WaitForExit(50))
            {
                code = apply.ExitCode;
                return;
            }
        }

        code = apply.ExitCode;
    }

    private static ProcessStartInfo HiddenLaunch(string system32, string logPath)
    {
        string launch = Path.Combine(system32, LaunchName);
        ProcessStartInfo psi = new()
        {
            FileName = Path.Combine(system32, "cmd.exe"),
            WorkingDirectory = system32,
            UseShellExecute = false,
            CreateNoWindow = true,
            // ponytail: ArgumentList extra-quotes this blob; cmd /c then exits 1 and LaunchApply never runs.
            Arguments = $"/c call \"{launch}\" > \"{logPath}\" 2>&1",
        };
        psi.Environment[QuickEditSkip] = "1";
        return psi;
    }

    private static int ShowFailure(string system32, string logPath, bool hold, int code)
    {
        if (!hold)
        {
            return code;
        }

        ProcessStartInfo psi = new()
        {
            FileName = Path.Combine(system32, "cmd.exe"),
            UseShellExecute = false,
            CreateNoWindow = false,
            Arguments = $"/k echo WinMint apply failed (exit {code}) & type \"{logPath}\"",
        };
        using Process? shown = Process.Start(psi);
        shown?.WaitForExit();
        return code;
    }
}
