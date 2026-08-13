using System.Diagnostics;
using System.Text;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class SourceMediaProbeTests
{
    private const string MultiEditionGolden = """
        Index : 1
        Name : Windows 11 Home
        Architecture : ARM64
        Edition : Core
        Version : 10.0.26100.1
        ServicePack Build : 26100

        Index : 3
        Name : Windows 11 Pro
        Architecture : ARM64
        Edition : Professional
        Installation : Client
        ProductType : WinNT
        Version : 10.0.26100.1
        ServicePack Build : 26100
        """;

    [Fact]
    public async Task ListIndexes_missing_path_fails_closed()
    {
        Result<IReadOnlyList<WimIndexInfo>, Failure> result =
            await SourceMediaProbe.Instance.ListIndexesAsync(
                @"C:\winmint-missing-" + Guid.NewGuid().ToString("N") + ".iso",
                TestContext.Current.CancellationToken);

        Assert.False(result.IsOk);
        Assert.Equal("wim.probe.isoMissing", result.Error.Code);
    }

    [Fact]
    public void ListFromGoldenText_via_WimMetadata_returns_ordered_rows()
    {
        string json = RunListFromText(MultiEditionGolden);
        Result<IReadOnlyList<WimIndexInfo>, Failure> parsed = PwshWimIndexSource.ParseListJson(json);

        Assert.True(parsed.IsOk, parsed.IsOk ? null : $"{parsed.Error.Code}: {parsed.Error.Message}");
        Assert.Equal(2, parsed.Value.Count);
        Assert.Equal(1, parsed.Value[0].Index);
        Assert.Equal("Windows 11 Home", parsed.Value[0].Name);
        Assert.Equal("Core", parsed.Value[0].Edition);
        Assert.Equal(3, parsed.Value[1].Index);
        Assert.Equal("Windows 11 Pro", parsed.Value[1].Name);
        Assert.Equal("Professional", parsed.Value[1].Edition);
        Assert.Equal("ARM64", parsed.Value[1].Architecture);
        Assert.Equal("26100", parsed.Value[1].Build);
    }

    [Fact]
    public void ListFromGoldenText_refuses_undefined_Name()
    {
        string bad = """
            Index : 1
            Name : <undefined>
            Architecture : ARM64
            Edition : Core
            """;

        ProcessResult proc = RunListFromTextProcess(bad);
        Assert.NotEqual(0, proc.ExitCode);
        Assert.Contains("wim.probe.incompleteName", proc.Stdout + proc.Stderr, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ParseListJson_empty_indexes_fails()
    {
        Result<IReadOnlyList<WimIndexInfo>, Failure> parsed =
            PwshWimIndexSource.ParseListJson("""{"indexes":[]}""");
        Assert.False(parsed.IsOk);
        Assert.Equal("wim.probe.empty", parsed.Error.Code);
    }

    [Theory]
    [InlineData("<undefined>")]
    [InlineData("undefined")]
    [InlineData("")]
    public void ParseListJson_refuses_undefined_Name(string name)
    {
        string json = $$"""{"indexes":[{"index":1,"name":"{{name}}","architecture":"ARM64"}]}""";
        Result<IReadOnlyList<WimIndexInfo>, Failure> parsed = PwshWimIndexSource.ParseListJson(json);
        Assert.False(parsed.IsOk);
        Assert.Equal("wim.probe.incompleteName", parsed.Error.Code);
    }

    [Theory]
    [InlineData(1, false, 1, 1)]
    [InlineData(3, false, 1, 1)]
    [InlineData(3, true, 1, 3)]
    [InlineData(5, true, 1, 1)]
    [InlineData(5, true, 9, 9)]
    [InlineData(1, false, 9, 9)]
    public void ResolveSelection_respects_deliberate_choice(
        int current,
        bool userChose,
        int hostDefault,
        int expected)
    {
        WimIndexInfo[] rows =
        [
            new(1, "Home", "ARM64", "Core", null, "26100"),
            new(3, "Pro", "ARM64", "Professional", null, "26100"),
        ];

        int picked = WimIndexInfo.ResolveSelection(rows, current, userChose, hostDefault);
        Assert.Equal(expected, picked);
    }

    private static string RunListFromText(string text)
    {
        ProcessResult proc = RunListFromTextProcess(text);
        Assert.True(proc.ExitCode == 0, $"exit={proc.ExitCode}\nstdout={proc.Stdout}\nstderr={proc.Stderr}");
        return proc.Stdout.Trim();
    }

    private static ProcessResult RunListFromTextProcess(string text)
    {
        string repo = TestRepo.Root;
        string script = Path.Combine(repo, "servicing", "Get-WimMetadata.ps1");
        string tmp = Path.Combine(Path.GetTempPath(), "winmint-wiminfo-" + Guid.NewGuid().ToString("N") + ".txt");
        File.WriteAllText(tmp, text, Encoding.UTF8);
        try
        {
            ProcessStartInfo psi = new()
            {
                FileName = "pwsh",
                ArgumentList = { "-NoProfile", "-File", script, "-ListFromTextPath", tmp },
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = repo,
            };
            using Process p = Process.Start(psi) ?? throw new InvalidOperationException("pwsh failed to start");
            string stdout = p.StandardOutput.ReadToEnd();
            string stderr = p.StandardError.ReadToEnd();
            Assert.True(p.WaitForExit(60_000), "ListFromText timed out");
            return new ProcessResult(p.ExitCode, stdout, stderr);
        }
        finally
        {
            try { File.Delete(tmp); } catch { /* ponytail: temp cleanup */ }
        }
    }

    private sealed record ProcessResult(int ExitCode, string Stdout, string Stderr);
}
