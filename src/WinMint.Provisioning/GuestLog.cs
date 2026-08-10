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

    [LoggerMessage(EventId = 8, Level = LogLevel.Information, Message = "residue: cleared AutoAdminLogon stamps")]
    public static partial void ResidueCleared(ILogger logger);

    [LoggerMessage(EventId = 9, Level = LogLevel.Warning, Message = "residue: ClearAutoLogon failed: {Message}")]
    public static partial void ResidueClearFailed(ILogger logger, string message);

    [LoggerMessage(EventId = 10, Level = LogLevel.Information, Message = "residue: deleted {Path}")]
    public static partial void ResidueDeleted(ILogger logger, string path);

    [LoggerMessage(EventId = 11, Level = LogLevel.Warning, Message = "residue: delete failed ({Path}): {Message}")]
    public static partial void ResidueDeleteFailed(ILogger logger, string path, string message);

    [LoggerMessage(EventId = 12, Level = LogLevel.Information, Message = "Secret wipe: redacted password in {BundlePath}")]
    public static partial void SecretWiped(ILogger logger, string bundlePath);

    [LoggerMessage(EventId = 13, Level = LogLevel.Information, Message = "winget.acl: skip — not SYSTEM")]
    public static partial void WingetAclSkip(ILogger logger);

    [LoggerMessage(EventId = 14, Level = LogLevel.Information, Message = "winget.acl: found {Count} under {Root}")]
    public static partial void WingetAclFound(ILogger logger, int count, string root);

    [LoggerMessage(EventId = 15, Level = LogLevel.Warning, Message = "winget.acl: FAILED {Dir}: {Message}")]
    public static partial void WingetAclFailed(ILogger logger, string dir, string message);

    [LoggerMessage(EventId = 16, Level = LogLevel.Information, Message = "winget.acl: none matched Microsoft.UI.Xaml.2.8_* / Microsoft.VCLibs.140.00_*")]
    public static partial void WingetAclNoneMatched(ILogger logger);

    [LoggerMessage(EventId = 17, Level = LogLevel.Information, Message = "winget.acl: skip missing {PackageDirectory}")]
    public static partial void WingetAclSkipMissing(ILogger logger, string packageDirectory);

    [LoggerMessage(EventId = 18, Level = LogLevel.Information, Message = "winget.acl: granted SYSTEM FullControl on {PackageDirectory}")]
    public static partial void WingetAclGranted(ILogger logger, string packageDirectory);
}
