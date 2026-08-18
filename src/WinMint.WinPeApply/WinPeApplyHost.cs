using System.Diagnostics;

namespace WinMint.WinPeApply;

/// <summary>
/// Windows-subsystem WinPE host. winpeshl [LaunchApp] cannot pass arguments, so this exe
/// CREATE_NO_WINDOW-launches LaunchApply.cmd beside it. Failures reopen a console with the log —
/// disk-guard refusals must stay visible (#119).
/// ponytail: Native AOT WinExe in WinPE — kernel32 CreateProcess only. If a Source ISO WinPE
/// lacks an API the runtime needs, replace this host with a C Win32 stub; keep LaunchApply.cmd.
/// </summary>
internal static class WinPeApplyHost
{
    internal const string LaunchName = "LaunchApply.cmd";
    private const string QuickEditSkip = "WINMINT_QE";

    private static int Main()
    {
        return Run(AppContext.BaseDirectory, holdFailureConsole: true);
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

        using Process? apply = Process.Start(HiddenLaunch(system32, log));
        if (apply is null)
        {
            File.WriteAllText(log, "WinMint: CreateProcess LaunchApply failed");
            return ShowFailure(system32, log, holdFailureConsole, 1);
        }

        apply.WaitForExit();
        return apply.ExitCode == 0
            ? 0
            : ShowFailure(system32, log, holdFailureConsole, apply.ExitCode);
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
