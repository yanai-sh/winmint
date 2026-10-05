using System.Text.Json.Serialization;

namespace WinMint.Provisioning;

public sealed record ShellDesktopEvidenceFile(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("taskbarSurface")] string? TaskbarSurface,
    [property: JsonPropertyName("komorebi")] bool Komorebi,
    [property: JsonPropertyName("yasbOk")] bool YasbOk,
    [property: JsonPropertyName("thideOk")] bool ThideOk,
    [property: JsonPropertyName("komorebiOk")] bool KomorebiOk,
    [property: JsonPropertyName("recoveredTaskbar")] bool RecoveredTaskbar,
    [property: JsonPropertyName("notes")] IReadOnlyList<string> Notes)
{
    public const string SchemaVersionValue = "winmint.shell.desktop/v1";
}
