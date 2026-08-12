using System.Diagnostics;

namespace WinMint.Tests;

public class WimMetadataSelfCheckTests
{
    [Fact]
    public void Wim_Metadata_ps1_SelfCheck_exits_zero()
    {
        string repo = TestRepo.Root;
        string script = Path.Combine(repo, "servicing", "Get-WimMetadata.ps1");
        Assert.True(File.Exists(script), script);

        ProcessStartInfo psi = new()
        {
            FileName = "pwsh",
            ArgumentList = { "-NoProfile", "-File", script, "-SelfCheck" },
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = repo,
        };
        using Process p = Process.Start(psi) ?? throw new InvalidOperationException("pwsh failed to start");
        string stdout = p.StandardOutput.ReadToEnd();
        string stderr = p.StandardError.ReadToEnd();
        Assert.True(p.WaitForExit(60_000), "SelfCheck timed out");
        Assert.True(p.ExitCode == 0, $"exit={p.ExitCode}\nstdout={stdout}\nstderr={stderr}");
        Assert.Contains("Get-WimMetadata SelfCheck ok", stdout, StringComparison.Ordinal);
    }

}
