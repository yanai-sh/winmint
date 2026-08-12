using WinMint.Contracts;
using WinMint.Orchestrator;
using WinMint.Provisioning;

namespace WinMint.Tests;

public class ShellStampTests
{
    [Fact]
    public void StampPowerShellSkel_writes_missing_files_and_keeps_existing()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-shell-stamp-" + Guid.NewGuid().ToString("N"));
        string skel = Path.Combine(root, "skel");
        string dest = Path.Combine(root, "Documents", "PowerShell");
        Directory.CreateDirectory(skel);
        File.WriteAllText(Path.Combine(skel, "Microsoft.PowerShell_profile.ps1"), "# profile");
        File.WriteAllText(Path.Combine(skel, "powershell.config.json"), "{}");
        File.WriteAllText(Path.Combine(skel, "starship.toml"), "add_newline = false");
        Directory.CreateDirectory(dest);
        File.WriteAllText(Path.Combine(dest, "starship.toml"), "keep-me");

        List<string> notes = [];
        ShellStamp.StampPowerShellSkelForTests(skel, dest, notes);

        Assert.Equal("# profile", File.ReadAllText(Path.Combine(dest, "Microsoft.PowerShell_profile.ps1")));
        Assert.Equal("{}", File.ReadAllText(Path.Combine(dest, "powershell.config.json")));
        Assert.Equal("keep-me", File.ReadAllText(Path.Combine(dest, "starship.toml")));
        Assert.Contains(notes, n => n.Contains("starship.toml kept", StringComparison.Ordinal));
        Assert.Contains(notes, n => n.Contains("Microsoft.PowerShell_profile.ps1 stamped", StringComparison.Ordinal));
    }

    [Fact]
    public void Plan_emits_shell_stamp_after_scoop_batch()
    {
        Profile profile = new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget(true, "en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            []);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "arm64" });

        Assert.True(result.IsOk, result.IsOk ? null : result.Error.Message);
        IReadOnlyList<ProvisionJob> jobs = result.Value.Jobs.Jobs;
        int scoop = jobs.ToList().FindIndex(j => j.Kind == ProvisionJobKind.ScoopBatch);
        int stamp = jobs.ToList().FindIndex(j => j.Kind == ProvisionJobKind.ShellStamp);
        Assert.True(scoop >= 0);
        Assert.True(stamp > scoop);
    }
}
