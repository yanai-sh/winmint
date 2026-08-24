using System.Text.Json.Serialization;

namespace WinMint.Provisioning;

public sealed record ShellChromeEvidenceFile(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("wallpaperPath")] string WallpaperPath,
    [property: JsonPropertyName("startPinIds")] string[] StartPinIds,
    [property: JsonPropertyName("taskbarPinIds")] string[] TaskbarPinIds,
    [property: JsonPropertyName("quietDwords")] IReadOnlyDictionary<string, int> QuietDwords)
{
    public const string SchemaVersionValue = "winmint.shell.chrome/v1";
}
