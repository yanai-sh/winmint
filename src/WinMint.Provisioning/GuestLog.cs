using Microsoft.Extensions.Logging;

namespace WinMint.Provisioning;

internal static partial class GuestLog
{
    [LoggerMessage(EventId = 1, Level = LogLevel.Error, Message = "Bundle missing: {BundlePath}")]
    public static partial void BundleMissing(ILogger logger, string bundlePath);

    [LoggerMessage(EventId = 2, Level = LogLevel.Error, Message = "{Code}: {Message}")]
    public static partial void Failure(ILogger logger, string code, string message);

    [LoggerMessage(EventId = 3, Level = LogLevel.Information, Message = "{Code}: {Message}")]
    public static partial void SessionStatus(ILogger logger, string code, string message);

    [LoggerMessage(EventId = 4, Level = LogLevel.Information, Message = "evidence: {SchemaVersion} -> {Path}")]
    public static partial void Evidence(ILogger logger, string schemaVersion, string path);

    [LoggerMessage(EventId = 5, Level = LogLevel.Error, Message = "machineSetup.crash")]
    public static partial void MachineSetupCrash(ILogger logger, Exception exception);

    [LoggerMessage(EventId = 6, Level = LogLevel.Error, Message = "shell.crash")]
    public static partial void ShellCrash(ILogger logger, Exception exception);

    [LoggerMessage(EventId = 7, Level = LogLevel.Information, Message = "{Line}")]
    public static partial void Line(ILogger logger, string line);
}
