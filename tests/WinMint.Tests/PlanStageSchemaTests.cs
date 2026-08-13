using System.Text.Json;
using System.Text.Json.Nodes;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class PlanStageSchemaTests
{
    [Fact]
    public void Plan_dump_and_materialized_stages_have_distinct_schema_ids()
    {
        ServicingStageList stages = new([]);

        Assert.Equal(
            "winmint.plan.stages/v1",
            Schema(BuildPlan.SerializePlanStagesFile(stages)));
        Assert.Equal(
            "winmint.servicing.stages/v1",
            Schema(ImageServicing.SerializeServicingStagesFile(
                Array.Empty<(ServicingOpcode, JsonObject)>())));
    }

    private static string Schema(string json)
    {
        using JsonDocument parsed = JsonDocument.Parse(json);
        return parsed.RootElement.GetProperty("schemaVersion").GetString()!;
    }
}
