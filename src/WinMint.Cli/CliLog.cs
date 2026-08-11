using Microsoft.Extensions.Logging;
using WinMint.Orchestrator;

namespace WinMint.Cli;

internal static partial class CliLog
{
    [LoggerMessage(EventId = 1, Level = LogLevel.Information, Message = "Profile OK; plan OK.")]
    public static partial void ProfileOk(ILogger logger);

    [LoggerMessage(EventId = 2, Level = LogLevel.Information, Message = "Wrote plan artifacts to {OutDir}")]
    public static partial void WrotePlanArtifacts(ILogger logger, string outDir);

    [LoggerMessage(EventId = 3, Level = LogLevel.Warning, Message = "ImageQuality=Release uses compression=max + cleanup=full — prefer Test for iterative builds. Without --package-strict this is not Gate B wipe media; use just primary-gate (or pass --package-strict) before flashing for Primary.")]
    public static partial void ReleaseLaneWarning(ILogger logger);

    [LoggerMessage(EventId = 4, Level = LogLevel.Error, Message = "{Code}: {Message}")]
    public static partial void Failure(ILogger logger, string code, string message);

    [LoggerMessage(EventId = 5, Level = LogLevel.Error, Message = "Work directory preserved: {WorkDir}")]
    public static partial void WorkPreserved(ILogger logger, string workDir);

    [LoggerMessage(EventId = 6, Level = LogLevel.Information, Message = "Image OK: {IsoPath}")]
    public static partial void ImageOk(ILogger logger, string isoPath);

    [LoggerMessage(EventId = 7, Level = LogLevel.Information, Message = "Shell stamp: {ShellPath}")]
    public static partial void ShellStamp(ILogger logger, string shellPath);

    [LoggerMessage(EventId = 8, Level = LogLevel.Information, Message = "Lane: {Lane}")]
    public static partial void Lane(ILogger logger, ImageQualityLane lane);

    [LoggerMessage(EventId = 9, Level = LogLevel.Error, Message = "Unsupported --image-quality '{Raw}' (expected Test|Release).")]
    public static partial void UnsupportedImageQuality(ILogger logger, string raw);

    [LoggerMessage(EventId = 10, Level = LogLevel.Error, Message = "Profile not found: {Path}")]
    public static partial void ProfileNotFound(ILogger logger, string path);

    [LoggerMessage(EventId = 11, Level = LogLevel.Error, Message = "{Code}: {Message}{PathSuffix}")]
    public static partial void DocumentIssue(ILogger logger, string code, string message, string pathSuffix);

    [LoggerMessage(EventId = 12, Level = LogLevel.Warning, Message = "{Line}")]
    public static partial void HonestyWarning(ILogger logger, string line);

    [LoggerMessage(EventId = 13, Level = LogLevel.Information, Message = "{Line}")]
    public static partial void HonestyLine(ILogger logger, string line);
}
