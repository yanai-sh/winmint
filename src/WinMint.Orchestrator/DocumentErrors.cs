namespace WinMint.Orchestrator;

public sealed record DocumentError(string Code, string Message, string? Path = null);

public sealed record DocumentErrors(IReadOnlyList<DocumentError> Issues);
