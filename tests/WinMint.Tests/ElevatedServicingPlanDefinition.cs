namespace WinMint.Tests;

/// <summary>
/// Invoke-ServicingPlan takes Global\WinMint.ImageServicing.v1 — serialize pwsh plan-loop tests.
/// </summary>
[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class ElevatedServicingPlanDefinition
{
    public const string Name = "ElevatedServicingPlan";
}
