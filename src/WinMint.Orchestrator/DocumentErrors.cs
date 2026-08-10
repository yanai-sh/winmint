namespace WinMint.Orchestrator;

public readonly record struct DocumentError(string Code, string Message, string? Path = null);
