namespace WinMint.Orchestrator;

public sealed record DocumentError(string Code, string Message, string? Path = null);
