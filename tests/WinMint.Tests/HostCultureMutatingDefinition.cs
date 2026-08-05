namespace WinMint.Tests;

/// <summary>
/// Host culture / locale mutation is process-global — serialize these tests.
/// </summary>
[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class HostCultureMutatingDefinition
{
    public const string Name = "HostCultureMutating";
}
