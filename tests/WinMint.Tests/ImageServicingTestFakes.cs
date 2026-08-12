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
            string workDirectory,
            CancellationToken ct)
        {
            Stages.AddRange(ReadStagesJson(workDirectory));
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

            // Minimal evidence fixture so ImageServicing.ReadEvidence can run (fake does not assemble ImageEvidence).
            string evidence = JsonSerializer.Serialize(
                new
                {
                    schemaVersion = ImageServicing.EvidenceSchemaVersion,
                    outputIsoPath = outputIso,
                    shellStampTargetPath = shellTarget,
                    digests = new Dictionary<string, string>(StringComparer.Ordinal)
                    {
                        ["outputIso.sha256"] = "test-digest",
                    },
                });
            File.WriteAllText(Path.Combine(workDirectory, "evidence.json"), evidence);
            return Task.FromResult(Result.Ok<ElevatedRunOk, Failure>(default));
        }
    }

    /// <summary>Parse <c>{work}/stages.json</c> the way Invoke-ServicingPlan.ps1 does, so the fake and pwsh share one contract.</summary>
    private static List<ServicingStage> ReadStagesJson(string workDirectory)
    {
        using JsonDocument doc = JsonDocument.Parse(
            File.ReadAllBytes(Path.Combine(workDirectory, "stages.json")));
        Assert.Equal(
            BuildPlan.StagesSchemaVersion,
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
            string workDirectory,
            CancellationToken ct)
        {
            Directory.CreateDirectory(Path.Combine(workDirectory, "logs"));
            File.WriteAllText(
                Path.Combine(workDirectory, "failure.json"),
                """{"schemaVersion":"winmint.image.evidence/v1","failed":true}""");
            return Task.FromResult(Result.Fail<ElevatedRunOk, Failure>(
                new Failure("servicing.stage.failed", "StageOobeUnattend failed (test).")));
        }
    }
}
