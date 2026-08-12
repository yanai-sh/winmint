using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>Repo root for fixture and script paths. One marker for the whole suite.</summary>
internal static class TestRepo
{
    internal static string Root { get; } = ToolkitRoot.FindRoot("WinMint.slnx");
}
