using System.Text.Json.Serialization;

namespace WinMintSetupShell;

public sealed class SetupShellStatus
{
    public string Phase { get; set; } = "running";
    public string StageId { get; set; } = "ready";
    public string TaskLabel { get; set; } = "Getting things ready";
    public string DetailLabel { get; set; } = "";
    public int ItemIndex { get; set; }
    public int ItemTotal { get; set; }
    public double ProgressPct { get; set; }
    public string ProgressMode { get; set; } = "indeterminate";
    public string ProfileName { get; set; } = "";
    public long ElapsedMs { get; set; }
    public string GroupLabel { get; set; } = "";
    public string Banner { get; set; } = "";
    public string BannerKind { get; set; } = "";
    public string LogDir { get; set; } = "";
    public string UpdatedAt { get; set; } = "";
}

public sealed class SetupShellControl
{
    public string Phase { get; set; } = "running";
    public string StartedAt { get; set; } = "";
    public string UpdatedAt { get; set; } = "";
    public string ProfileName { get; set; } = "";
    public string Message { get; set; } = "";
    public string PreAgentStage { get; set; } = "";
}

public sealed class RuntimeStateAgent
{
    public string RunStatus { get; set; } = "";
    public string CurrentStep { get; set; } = "";
    public List<string>? RunningSteps { get; set; }
    public int CompletedSteps { get; set; }
    public int TotalSteps { get; set; }
    public string UpdatedAt { get; set; } = "";
}

public sealed class RuntimeStateDocument
{
    public int SchemaVersion { get; set; } = 1;
    public string UpdatedAt { get; set; } = "";
    public SetupShellControl? Control { get; set; }
    public SetupShellStatus? Display { get; set; }
    public RuntimeStateAgent? Agent { get; set; }
}

public sealed class DesignTokens
{
    public string Canvas { get; set; } = "#11161d";
    public string Ink { get; set; } = "#f4f7fb";
    public string Muted { get; set; } = "#b7c0cc";
    public string Dim { get; set; } = "#8792a1";
    public string Accent { get; set; } = "#0067c0";
    public string Warn { get; set; } = "#f0c05f";
    public string Fail { get; set; } = "#ff5f57";
    public string ProgressTrack { get; set; } = "#2e3036";
    public string ProgressFill { get; set; } = "#ebeff5";
    public string FontFamily { get; set; } = "Segoe UI";
    public LayoutTokens Layout { get; set; } = new();
}

public sealed class LayoutTokens
{
    public int DockPaddingH { get; set; } = 96;
    public int DockPaddingBottom { get; set; } = 88;
    public int DockMaxWidth { get; set; } = 540;
    public int HeroMaxWidth { get; set; } = 640;
    public int HeroMaxHeight { get; set; } = 160;
    public double HeroAreaRatio { get; set; } = 0.68;
    public float GroupFontSize { get; set; } = 13;
    public float TaskFontSize { get; set; } = 18;
    public float DetailFontSize { get; set; } = 15;
    public float ProgressHeight { get; set; } = 3;
    public int BannerOffsetBottom { get; set; } = 160;
}

[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
[JsonSerializable(typeof(SetupShellStatus))]
[JsonSerializable(typeof(SetupShellControl))]
[JsonSerializable(typeof(RuntimeStateDocument))]
[JsonSerializable(typeof(RuntimeStateAgent))]
[JsonSerializable(typeof(DesignTokens))]
[JsonSerializable(typeof(LayoutTokens))]
internal partial class SetupShellJsonContext : JsonSerializerContext;
