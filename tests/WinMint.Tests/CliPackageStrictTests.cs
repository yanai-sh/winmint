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
}
