using System.Text.Json;
using WinMint.Orchestrator;

namespace WinMint.Tests;

internal static class ImageServicingTestFakes
{
    internal sealed class RecordingElevatedPlanRunner : IElevatedPlanRunner
    {
        public List<ServicingStage> Stages { get; } = [];
        public IEnumerable<ServicingOpcode> Opcodes => Stages.Select(s => s.Opcode);

        public Task<Result<ElevatedRunOk, Failure>> ExecuteAsync(
            ServicingWorkspace workspace,
            CancellationToken ct)
        {
            Stages.AddRange(ReadStagesJson(workspace));
            IReadOnlyList<ServicingStage> stages = Stages;
            ServicingStage? stamp = stages.FirstOrDefault(s => s.Opcode == ServicingOpcode.StampOfflineShell);
            if (stamp is null
                || !stamp.Parameters.TryGetValue(StageParams.ShellTarget, out string? shellTarget)
                || string.IsNullOrWhiteSpace(shellTarget))
            {
                return Task.FromResult(Result.Fail<ElevatedRunOk, Failure>(
                    new Failure(
                        "servicing.shellStamp.missing",
                        "StampOfflineShell stage missing or incomplete.")));
            }

            ServicingStage? buildIso = stages.FirstOrDefault(s => s.Opcode == ServicingOpcode.BuildIso);
            if (buildIso is null
                || !buildIso.Parameters.TryGetValue(StageParams.OutputIso, out string? outputIso)
                || string.IsNullOrWhiteSpace(outputIso))
            {
                return Task.FromResult(Result.Fail<ElevatedRunOk, Failure>(
                    new Failure("servicing.outputIso.missing", "BuildIso stage missing outputIso.")));
            }

            ServicingStage? exportWim = stages.FirstOrDefault(s => s.Opcode == ServicingOpcode.ExportWim);
            if (exportWim is null
                || !exportWim.Parameters.TryGetValue(StageParams.Lane, out string? lane)
                || string.IsNullOrWhiteSpace(lane))
            {
                return Task.FromResult(Result.Fail<ElevatedRunOk, Failure>(
                    new Failure("servicing.lane.missing", "ExportWim stage missing lane.")));
            }

            Directory.CreateDirectory(Path.GetDirectoryName(outputIso)!);
            if (!File.Exists(outputIso))
            {
                File.WriteAllText(outputIso, "fake-iso");
            }

            Directory.CreateDirectory(workspace.Logs);
            File.WriteAllText(
                workspace.Digests,
                JsonSerializer.Serialize(new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    ["outputIso.sha256"] = new string('a', 64),
                }));
            return Task.FromResult(Result.Ok<ElevatedRunOk, Failure>(default));
        }
    }

    internal sealed class EvidenceElevatedPlanRunner(string evidence) : IElevatedPlanRunner
    {
        public Task<Result<ElevatedRunOk, Failure>> ExecuteAsync(
            ServicingWorkspace workspace,
            CancellationToken ct)
        {
            File.WriteAllText(workspace.Evidence, evidence);
            return Task.FromResult(Result.Ok<ElevatedRunOk, Failure>(default));
        }
    }

    internal sealed class SuccessfulElevatedPlanRunner : IElevatedPlanRunner
    {
        public Task<Result<ElevatedRunOk, Failure>> ExecuteAsync(
            ServicingWorkspace workspace,
            CancellationToken ct) =>
            Task.FromResult(Result.Ok<ElevatedRunOk, Failure>(default));
    }

    internal static string PrepareSuccessfulServicingFinalizer(string workDirectory)
    {
        string servicing = Path.Combine(workDirectory, "fake-servicing");
        Directory.CreateDirectory(servicing);
        string runner = Path.Combine(servicing, "Invoke-ServicingPlan.ps1");
        File.Copy(
            Path.Combine(TestRepo.Root, "servicing", "Invoke-ServicingPlan.ps1"),
            runner);
        File.Copy(
            Path.Combine(TestRepo.Root, "servicing", "Resolve-WinMintMount.ps1"),
            Path.Combine(servicing, "Resolve-WinMintMount.ps1"));
        File.Copy(
            Path.Combine(TestRepo.Root, "servicing", "Get-WinMintServicingWorkspace.ps1"),
            Path.Combine(servicing, "Get-WinMintServicingWorkspace.ps1"));

        const string noOp = """
            param(
                [string] $ShellTarget,
                [string] $MountDir,
                [string] $Lane,
                [string] $MediaDir,
                [string] $WimOut,
                [string] $WorkDirectory,
                [string] $Compression,
                [string] $Cleanup
            )
            exit 0
            """;
        File.WriteAllText(Path.Combine(servicing, "Stamp-OfflineShell.ps1"), noOp);
        File.WriteAllText(Path.Combine(servicing, "Export-Wim.ps1"), noOp);
        File.WriteAllText(
            Path.Combine(servicing, "Build-Iso.ps1"),
            """
            param(
                [Parameter(Mandatory)] [string] $OutputIso,
                [string] $MediaDir
            )
            Set-Content -LiteralPath $OutputIso -Value 'fake-iso' -Encoding utf8
            exit 0
            """);

        string outputIso = Path.Combine(workDirectory, "output.iso");
        File.WriteAllText(
            Path.Combine(workDirectory, "stages.json"),
            JsonSerializer.Serialize(new
            {
                schemaVersion = BuildPlan.ServicingStagesSchemaVersion,
                stages = new object[]
                {
                    new
                    {
                        opcode = "StampOfflineShell",
                        parameters = new Dictionary<string, string>
                        {
                            [StageParams.ShellTarget] = ImageServicing.ShellStampGuestPath,
                        },
                    },
                    new
                    {
                        opcode = "ExportWim",
                        parameters = new Dictionary<string, string> { [StageParams.Lane] = "Test" },
                    },
                    new
                    {
                        opcode = "BuildIso",
                        parameters = new Dictionary<string, string> { [StageParams.OutputIso] = outputIso },
                    },
                },
            }));
        return runner;
    }

    /// <summary>Parse <c>{work}/stages.json</c> the way Invoke-ServicingPlan.ps1 does, so the fake and pwsh share one contract.</summary>
    private static List<ServicingStage> ReadStagesJson(ServicingWorkspace workspace)
    {
        using JsonDocument doc = JsonDocument.Parse(
            File.ReadAllBytes(workspace.Stages));
        Assert.Equal(
            BuildPlan.ServicingStagesSchemaVersion,
            doc.RootElement.GetProperty("schemaVersion").GetString());

        List<ServicingStage> stages = [];
        foreach (JsonElement stage in doc.RootElement.GetProperty("stages").EnumerateArray())
        {
            Dictionary<string, string> parameters = new(StringComparer.Ordinal);
            foreach (JsonProperty p in stage.GetProperty("parameters").EnumerateObject())
            {
                parameters[p.Name] = p.Value.GetString()!;
            }

            stages.Add(new ServicingStage(
                Enum.Parse<ServicingOpcode>(stage.GetProperty("opcode").GetString()!),
                parameters));
        }

        return stages;
    }

    internal sealed class FailingElevatedPlanRunner : IElevatedPlanRunner
    {
        public Task<Result<ElevatedRunOk, Failure>> ExecuteAsync(
            ServicingWorkspace workspace,
            CancellationToken ct)
        {
            Directory.CreateDirectory(workspace.Logs);
            File.WriteAllText(
                workspace.Failure,
                """{"schemaVersion":"winmint.image.evidence/v1","failed":true}""");
            return Task.FromResult(Result.Fail<ElevatedRunOk, Failure>(
                new Failure("servicing.stage.failed", "StageOobeUnattend failed (test).")));
        }
    }
}
