namespace WinMint.Tests;

public class ScaffoldTests
{
    [Fact]
    public void SetupComplete_cmd_exists()
    {
        Assert.True(File.Exists(Path.Combine(RepoRoot(), "payload", "scripts", "SetupComplete.cmd")));
    }

    [Fact]
    public void Cli_project_references_Orchestrator()
    {
        string csproj = File.ReadAllText(
            Path.Combine(RepoRoot(), "src", "WinMint.Cli", "WinMint.Cli.csproj"));
        Assert.Contains("WinMint.Orchestrator.csproj", csproj, StringComparison.Ordinal);
    }

    private static string RepoRoot()
    {
        DirectoryInfo? dir = new(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "WinMint.slnx")))
        {
            dir = dir.Parent;
        }

        return dir!.FullName;
    }
}
