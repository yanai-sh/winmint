using System.CommandLine;

using WinMint.Orchestrator;

using CliProgram = WinMint.Cli.Program;

namespace WinMint.Tests;

public class CliPackageStrictTests
{
    [Theory]
    [InlineData(false, PackageStrictOverride.FromLane)]
    [InlineData(true, PackageStrictOverride.Force)]
    public void Package_strict_flag_preserves_absence(
        bool flag,
        PackageStrictOverride expected)
    {
        Option<bool> option = new("--package-strict");
        RootCommand root = new() { option };
        ParseResult parsed = root.Parse(flag ? ["--package-strict"] : []);

        Assert.Equal(expected, CliProgram.ParsePackageStrictOverride(parsed, option));
    }

    [Fact]
    public void Build_does_not_define_reuse_media()
    {
        string cli = File.ReadAllText(Path.Combine(TestRepo.Root, "src", "WinMint.Cli", "Program.cs"));
        string just = File.ReadAllText(Path.Combine(TestRepo.Root, "Justfile"));
        Assert.DoesNotContain("--reuse-media", cli, StringComparison.Ordinal);
        Assert.DoesNotContain("--reuse-media", just, StringComparison.Ordinal);
    }
}
