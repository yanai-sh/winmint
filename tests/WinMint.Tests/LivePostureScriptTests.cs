using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

using WinMint.Contracts;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class LivePostureScriptTests
{
    // widgets, taskview, search, and chat are the taskbar policies.
    // Family "taskbar" is the offline layout XML, which this folder does not write.
    private static readonly HashSet<string> LivePolicyFamilies = new(StringComparer.Ordinal)
    {
        "chat",
        "cloudContent",
        "device",
        "developer",
        "edge",
        "filesystem",
        "search",
        "store",
        "sudo",
        "taskview",
        "widgets",
        "wpbt",
    };

    private static readonly Dictionary<string, string> LiveOnlyRows = new(StringComparer.Ordinal)
    {
        ["EnableActivityFeed"] = @"HKLM:\SOFTWARE\Policies\Microsoft\Windows\System",
        ["PublishUserActivities"] = @"HKLM:\SOFTWARE\Policies\Microsoft\Windows\System",
        ["UploadUserActivities"] = @"HKLM:\SOFTWARE\Policies\Microsoft\Windows\System",
        ["DODownloadMode"] = @"HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization",
    };

    private static readonly string[] RegistryTasks =
    [
        "Disable-ConsumerFeatures.ps1",
        "Set-QuietTaskbar.ps1",
        "Disable-EdgePromotions.ps1",
        "Set-ExplorerView.ps1",
        "Set-SystemPolicy.ps1",
    ];

    private static readonly string[] RegistryForbidden =
    [
        "GlobalUserDisabled",
        "SvcHostSplitThresholdInKB",
        "Set-Service",
        "ConsentPromptBehaviorAdmin",
        "Set-WinHomeLocation",
        "Set-ReservedStorageState",
        "Remove-WindowsCapability",
        "OneDriveSetup.exe",
        "Remove-AppxPackage",
        "New-ItemProperty",
        "Registry.ps1",
    ];

    private static readonly Regex WriterBind = new(
        @"\$(?<var>[A-Za-z_]\w*) = Join-Path \$PSScriptRoot 'Set-RegExeValue\.ps1'",
        RegexOptions.CultureInvariant);

    private static readonly Regex QuotedAssignment = new(
        @"^\$(?<name>[A-Za-z_]\w*)\s*=\s*(?<value>'[^']*'|""[^""]*"")\s*$",
        RegexOptions.CultureInvariant);

    private static readonly Regex QuotedItem = new(
        @"^'([^']*)'$",
        RegexOptions.CultureInvariant);

    private static readonly Regex PairItem = new(
        @"^@\{ Name = '(?<name>[^']*)'; Value = '(?<value>[^']*)' \}$",
        RegexOptions.CultureInvariant);

    private static readonly Regex VariableToken = new(
        @"\$(\w+)",
        RegexOptions.CultureInvariant);

    [Fact]
    public void Registry_tasks_keep_the_curated_names()
    {
        string live = Path.Combine(TestRepo.Root, "post-install");
        string orchestrator = File.ReadAllText(Path.Combine(live, "Apply-Registry.ps1"));
        int last = -1;
        foreach (string task in RegistryTasks)
        {
            int at = orchestrator.IndexOf(task, StringComparison.Ordinal);
            Assert.True(at > last, task);
            last = at;
            string body = File.ReadAllText(Path.Combine(live, "registry", task));
            Assert.DoesNotContain("function Set-RegValue", body, StringComparison.Ordinal);
            Assert.DoesNotContain("Set-RegDword", body, StringComparison.Ordinal);
            Assert.DoesNotContain("Set-RegString", body, StringComparison.Ordinal);
            Assert.DoesNotContain("Set-RegExpand", body, StringComparison.Ordinal);
            Assert.DoesNotContain("System32\\reg.exe", body, StringComparison.Ordinal);
            Assert.DoesNotContain(". (Join-Path", body, StringComparison.Ordinal);
            Assert.DoesNotContain(". $regExe", body, StringComparison.Ordinal);
            Assert.Contains("$regExe = Join-Path $PSScriptRoot 'Set-RegExeValue.ps1'", body, StringComparison.Ordinal);
            Assert.Contains("& $regExe ", body, StringComparison.Ordinal);
            Assert.Contains("-DryRun:$DryRun", body, StringComparison.Ordinal);
        }

        string writer = File.ReadAllText(Path.Combine(live, "registry", "Set-RegExeValue.ps1"));
        Assert.Contains("System32\\reg.exe", writer, StringComparison.Ordinal);
        Assert.Contains("$ErrorActionPreference = 'Continue'", writer, StringComparison.Ordinal);
        Assert.Contains("Access is denied", writer, StringComparison.Ordinal);
        Assert.Contains("left unchanged:", writer, StringComparison.Ordinal);
        Assert.Contains("dry-run: $Path $Name = $Data", writer, StringComparison.Ordinal);
        Assert.Contains("^(HKLM|HKCU):", writer, StringComparison.Ordinal);
        Assert.Contains("& $reg add ", writer, StringComparison.Ordinal);
        Assert.Contains("[string] $Path", writer, StringComparison.Ordinal);
        Assert.Contains("[string] $Name", writer, StringComparison.Ordinal);
        Assert.Contains("[string] $Type", writer, StringComparison.Ordinal);
        Assert.Contains("[string] $Data", writer, StringComparison.Ordinal);
        Assert.DoesNotContain("function ", writer, StringComparison.Ordinal);
        Assert.DoesNotContain("PSScriptRoot", writer, StringComparison.Ordinal);
        Assert.DoesNotContain(". (Join-Path", writer, StringComparison.Ordinal);

        Assert.DoesNotContain("Set-RegExeValue.ps1", orchestrator, StringComparison.Ordinal);
        Assert.DoesNotContain("Registry.ps1", orchestrator, StringComparison.Ordinal);

        foreach (string path in Directory.GetFiles(Path.Combine(live, "registry"), "*.ps1"))
        {
            string body = File.ReadAllText(path);
            foreach (string word in RegistryForbidden)
            {
                Assert.DoesNotContain(word, body, StringComparison.Ordinal);
            }
        }
    }

    [Fact]
    public void Registry_values_match_product_posture_and_quiet_chrome()
    {
        Dictionary<string, LiveRegWrite> live = ParseLiveRegistry();
        Dictionary<string, (string Type, string Data)> expected = ExpectedOverlap();

        foreach ((string key, (string Type, string Data) row) in expected)
        {
            Assert.True(live.TryGetValue(key, out LiveRegWrite actual), key);
            Assert.Equal(row.Type, actual.Type);
            Assert.Equal(row.Data, actual.Data);
        }

        foreach ((string key, LiveRegWrite row) in live)
        {
            if (LiveOnlyRows.ContainsKey(row.Name))
            {
                Assert.False(expected.ContainsKey(key), row.Name);
                continue;
            }

            Assert.True(expected.ContainsKey(key), row.Path + " " + row.Name);
        }

        Assert.Equal(expected.Count + LiveOnlyRows.Count, live.Count);
        AssertLiveOnly(live);
        AssertNamedOverlaps(expected);
    }

    [Fact]
    public void OneDrive_script_purges_the_client_and_the_user_folder()
    {
        string script = File.ReadAllText(Path.Combine(TestRepo.Root, "post-install", "Uninstall-OneDrive.ps1"));
        Assert.Contains("OneDriveSetup.exe", script, StringComparison.Ordinal);
        Assert.Contains("/uninstall", script, StringComparison.Ordinal);
        Assert.Contains("takeown.exe", script, StringComparison.Ordinal);
        Assert.Contains("RunOnce", script, StringComparison.Ordinal);
        Assert.Contains("Microsoft.OneDrive", script, StringComparison.Ordinal);
        Assert.Contains("OneDriveTemp", script, StringComparison.Ordinal);
        Assert.Contains("OneSyncSvc", script, StringComparison.Ordinal);
        Assert.Contains("SyncRootManager", script, StringComparison.Ordinal);
        Assert.Contains("Move-OneDriveChildren", script, StringComparison.Ordinal);
        Assert.Contains("PreventNetworkTrafficPreUserSignIn", script, StringComparison.Ordinal);
        Assert.Contains("DisableFileSyncNGSC", script, StringComparison.Ordinal);
        Assert.Contains("%USERPROFILE%\\Desktop", script, StringComparison.Ordinal);
        Assert.Contains("-1978335212", script, StringComparison.Ordinal);
        Assert.Contains("$root.Name -ne 'OneDriveTemp'", script, StringComparison.Ordinal);
        Assert.Contains(@"^\.[0-9A-Fa-f]{8}-", script, StringComparison.Ordinal);
        Assert.Contains("2>&1", script, StringComparison.Ordinal);
        Assert.DoesNotContain("Generic.List", script, StringComparison.Ordinal);
        Assert.DoesNotContain("PSScriptRoot", script, StringComparison.Ordinal);
        Assert.DoesNotContain("left user folder", script, StringComparison.Ordinal);
        Assert.DoesNotContain("Remove-AppxPackage", script, StringComparison.Ordinal);
    }

    [Fact]
    public void Registry_script_lists_the_product_inbox_strip()
    {
        string script = File.ReadAllText(Path.Combine(TestRepo.Root, "post-install", "Remove-InboxApps.ps1"));
        Assert.Contains("Deprovisioned", script, StringComparison.Ordinal);
        Assert.Contains("Clipchamp.Clipchamp_yxz26nhyzhsrt", script, StringComparison.Ordinal);
        Assert.Contains("UseWindowsPowerShell", script, StringComparison.Ordinal);
        Assert.Contains("dism.exe /Online /Get-ProvisionedAppxPackages /English", script, StringComparison.Ordinal);
        Assert.Contains("/Remove-ProvisionedAppxPackage", script, StringComparison.Ordinal);
        Assert.DoesNotContain("Get-AppxProvisionedPackage", script, StringComparison.Ordinal);
        Assert.DoesNotContain("Remove-AppxProvisionedPackage", script, StringComparison.Ordinal);
        Assert.DoesNotContain("Generic.List", script, StringComparison.Ordinal);
        HashSet<string> listed = QuotedBlock(script, "$inboxIds = @(");
        HashSet<string> expected = ProductPosture.AppxIds
            .Where(id => !ProductPosture.PreserveAppxSet.Contains(id))
            .ToHashSet(StringComparer.Ordinal);

        Assert.Equal(expected.OrderBy(id => id, StringComparer.Ordinal), listed.OrderBy(id => id, StringComparer.Ordinal));
        Assert.DoesNotContain("Microsoft.Windows.PeopleExperienceHost", listed);
        Assert.DoesNotContain("Windows.CBSPreview", listed);
        Assert.Contains("Microsoft.WindowsCalculator", listed);
        Assert.Contains("MicrosoftWindows.Client.WebExperience", listed);
    }

    [Fact]
    public void Live_scripts_run_on_windows_powershell_and_powershell_7()
    {
        string live = Path.Combine(TestRepo.Root, "post-install");
        foreach (string path in Directory.GetFiles(live, "*.ps1", SearchOption.AllDirectories))
        {
            string script = File.ReadAllText(path);
            Assert.Contains("#requires -Version 5.1", script, StringComparison.Ordinal);
            Assert.DoesNotContain("#requires -Version 7", script, StringComparison.Ordinal);
            Assert.DoesNotContain("&&", script, StringComparison.Ordinal);
            Assert.DoesNotContain("??", script, StringComparison.Ordinal);
            Assert.DoesNotContain(". (Join-Path", script, StringComparison.Ordinal);
            Assert.Contains("[switch] $DryRun", script, StringComparison.Ordinal);
            string name = Path.GetFileName(path);
            if (Array.IndexOf(RegistryTasks, name) >= 0)
            {
                Assert.Contains(
                    "$regExe = Join-Path $PSScriptRoot 'Set-RegExeValue.ps1'",
                    script,
                    StringComparison.Ordinal);
                Assert.Single(Regex.Matches(script, "PSScriptRoot"));
            }
            else if (name is not "Apply-LivePosture.ps1" and not "Apply-Registry.ps1")
            {
                Assert.DoesNotContain("PSScriptRoot", script, StringComparison.Ordinal);
            }
        }

        string orchestrator = File.ReadAllText(Path.Combine(live, "Apply-LivePosture.ps1"));
        int registry = orchestrator.IndexOf("Apply-Registry.ps1", StringComparison.Ordinal);
        int oneDrive = orchestrator.IndexOf("Uninstall-OneDrive.ps1", StringComparison.Ordinal);
        int inbox = orchestrator.IndexOf("Remove-InboxApps.ps1", StringComparison.Ordinal);
        int drivers = orchestrator.LastIndexOf("Install-SurfaceDrivers.ps1", StringComparison.Ordinal);
        Assert.True(registry >= 0 && registry < oneDrive && oneDrive < inbox && inbox < drivers);
        Assert.Contains("[switch] $Drivers", orchestrator, StringComparison.Ordinal);
        Assert.Contains("Missing $Name next to this script.", orchestrator, StringComparison.Ordinal);
        string registryOrchestrator = File.ReadAllText(Path.Combine(live, "Apply-Registry.ps1"));
        Assert.Contains("Missing $Name next to this script.", registryOrchestrator, StringComparison.Ordinal);
        Assert.DoesNotContain("Registry.ps1", registryOrchestrator, StringComparison.Ordinal);
        string driverScript = File.ReadAllText(Path.Combine(live, "Install-SurfaceDrivers.ps1"));
        Assert.Contains("surface-laptop-7", driverScript, StringComparison.Ordinal);
        Assert.Contains("msiexec.exe", driverScript, StringComparison.Ordinal);
        Assert.Contains("1638", driverScript, StringComparison.Ordinal);
        Assert.Contains("1641", driverScript, StringComparison.Ordinal);
    }

    private static void AssertLiveOnly(Dictionary<string, LiveRegWrite> live)
    {
        HashSet<string> productNames = ProductPosture.ComposePolicies(includeBraveDebloat: false)
            .Concat(ProductPosture.ComposeDefaultUserRows())
            .Select(static row => row.Name)
            .ToHashSet(StringComparer.Ordinal);
        foreach ((string name, string path) in LiveOnlyRows)
        {
            Assert.DoesNotContain(name, productNames);
            LiveRegWrite row = live.Values.Single(candidate => candidate.Name == name);
            Assert.Equal(path, row.Path);
            Assert.Equal("REG_DWORD", row.Type);
            Assert.Equal("0", row.Data);
        }
    }

    private static void AssertNamedOverlaps(Dictionary<string, (string Type, string Data)> expected)
    {
        foreach (OfflinePolicyRow row in ProductPosture.ComposePolicies(includeBraveDebloat: false))
        {
            if (row.Family == "edge" || row.Family is "widgets" or "taskview" or "search" or "chat")
            {
                Assert.True(expected.ContainsKey(Canonical(ProductPath(row), row.Name)), row.Name);
            }
        }

        foreach (string name in QuietChromeFacts.ContentDeliveryManagerDwords)
        {
            Assert.True(
                expected.Keys.Any(key => key.EndsWith(@"\ContentDeliveryManager|" + name, StringComparison.Ordinal)),
                name);
        }

        foreach ((string name, int value) in QuietChromeFacts.ExplorerAdvancedDwords)
        {
            string key = expected.Keys.Single(candidate =>
                candidate.EndsWith(@"\Explorer\Advanced|" + name, StringComparison.Ordinal));
            Assert.Equal("REG_DWORD", expected[key].Type);
            Assert.Equal(value.ToString(CultureInfo.InvariantCulture), expected[key].Data);
        }
    }

    private static Dictionary<string, (string Type, string Data)> ExpectedOverlap()
    {
        Dictionary<string, (string Type, string Data)> required = new(StringComparer.Ordinal);
        foreach (OfflinePolicyRow row in ProductPosture.ComposePolicies(includeBraveDebloat: false))
        {
            if (LivePolicyFamilies.Contains(row.Family))
            {
                AddRequired(required, row);
            }
        }

        foreach (OfflinePolicyRow row in ProductPosture.ComposeDefaultUserRows())
        {
            if (row.SubKey.Contains("User Shell Folders", StringComparison.OrdinalIgnoreCase)
                || row.SubKey.StartsWith(@"Control Panel\Desktop", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            AddRequired(required, row);
        }

        OfflinePolicyRow advanced = ProductPosture.ComposeDefaultUserRows()
            .First(static row => row.SubKey.EndsWith(@"\Explorer\Advanced", StringComparison.Ordinal));
        string advancedPath = ProductPath(advanced);
        foreach ((string name, int value) in QuietChromeFacts.ExplorerAdvancedDwords)
        {
            AddRequired(
                required,
                Canonical(advancedPath, name),
                "REG_DWORD",
                value.ToString(CultureInfo.InvariantCulture));
        }

        return required;
    }

    private static void AddRequired(
        Dictionary<string, (string Type, string Data)> required,
        OfflinePolicyRow row)
    {
        AddRequired(required, Canonical(ProductPath(row), row.Name), row.RegType, row.Data);
    }

    private static void AddRequired(
        Dictionary<string, (string Type, string Data)> required,
        string key,
        string type,
        string data)
    {
        if (required.TryGetValue(key, out (string Type, string Data) existing))
        {
            Assert.Equal(existing.Type, type);
            Assert.Equal(existing.Data, data);
            return;
        }

        required.Add(key, (type, data));
    }

    private static Dictionary<string, LiveRegWrite> ParseLiveRegistry()
    {
        Dictionary<string, LiveRegWrite> live = new(StringComparer.Ordinal);
        string registry = Path.Combine(TestRepo.Root, "post-install", "registry");
        foreach (string task in RegistryTasks)
        {
            foreach (LiveRegWrite row in ParseRegWrites(File.ReadAllText(Path.Combine(registry, task)), task))
            {
                string key = Canonical(row.Path, row.Name);
                if (live.TryGetValue(key, out LiveRegWrite prior))
                {
                    Assert.Equal(prior.Type, row.Type);
                    Assert.Equal(prior.Data, row.Data);
                    continue;
                }

                live.Add(key, row);
            }
        }

        return live;
    }

    private static List<LiveRegWrite> ParseRegWrites(string script, string fileName)
    {
        string body = StripBlockComments(script);
        Match bind = Assert.Single(WriterBind.Matches(body));
        string variable = bind.Groups["var"].Value;
        Dictionary<string, string> variables = new(StringComparer.Ordinal);
        List<LiveRegWrite> rows = [];
        string[] lines = body.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n').Split('\n');
        for (int i = 0; i < lines.Length; i++)
        {
            string line = StripComment(lines[i]).Trim();
            if (line.Length == 0)
            {
                continue;
            }

            if (line.StartsWith("foreach ($name in @(", StringComparison.Ordinal))
            {
                i = ParseNameLoop(lines, i, variable, variables, rows, fileName);
                continue;
            }

            if (line.StartsWith("foreach ($pair in @(", StringComparison.Ordinal))
            {
                i = ParsePairLoop(lines, i, variable, variables, rows, fileName);
                continue;
            }

            if (line.StartsWith("foreach ", StringComparison.Ordinal))
            {
                Assert.Fail(fileName + ": " + line);
            }

            Match assign = QuotedAssignment.Match(line);
            if (assign.Success)
            {
                variables[assign.Groups["name"].Value] = ExpandToken(
                    assign.Groups["value"].Value,
                    variables,
                    pairName: null,
                    pairValue: null);
                continue;
            }

            if (line.StartsWith("& $" + variable, StringComparison.Ordinal))
            {
                rows.Add(ParseCall(line, variable, variables, pairName: null, pairValue: null));
                continue;
            }

            if (line.Contains("& $", StringComparison.Ordinal))
            {
                Assert.Fail(fileName + ": " + line);
            }
        }

        Assert.NotEmpty(rows);
        return rows;
    }

    private static int ParseNameLoop(
        string[] lines,
        int start,
        string variable,
        Dictionary<string, string> variables,
        List<LiveRegWrite> rows,
        string fileName)
    {
        List<string> names = [];
        int i = start;
        while (true)
        {
            i++;
            Assert.True(i < lines.Length, fileName);
            string line = StripComment(lines[i]).Trim();
            if (line.StartsWith(')'))
            {
                break;
            }

            if (line.Length == 0)
            {
                continue;
            }

            Match item = QuotedItem.Match(line);
            Assert.True(item.Success, fileName + ": " + line);
            names.Add(item.Groups[1].Value);
        }

        string call = ReadFollowingCall(lines, ref i, variable, fileName);
        foreach (string name in names)
        {
            variables["name"] = name;
            rows.Add(ParseCall(call, variable, variables, pairName: null, pairValue: null));
        }

        variables.Remove("name");
        Assert.NotEmpty(names);
        return i;
    }

    private static int ParsePairLoop(
        string[] lines,
        int start,
        string variable,
        Dictionary<string, string> variables,
        List<LiveRegWrite> rows,
        string fileName)
    {
        List<(string Name, string Value)> pairs = [];
        int i = start;
        while (true)
        {
            i++;
            Assert.True(i < lines.Length, fileName);
            string line = StripComment(lines[i]).Trim();
            if (line.StartsWith(')'))
            {
                break;
            }

            if (line.Length == 0)
            {
                continue;
            }

            Match item = PairItem.Match(line);
            Assert.True(item.Success, fileName + ": " + line);
            pairs.Add((item.Groups["name"].Value, item.Groups["value"].Value));
        }

        string call = ReadFollowingCall(lines, ref i, variable, fileName);
        foreach ((string name, string value) in pairs)
        {
            rows.Add(ParseCall(call, variable, variables, name, value));
        }

        Assert.NotEmpty(pairs);
        return i;
    }

    private static string ReadFollowingCall(string[] lines, ref int i, string variable, string fileName)
    {
        string prefix = "& $" + variable;
        while (true)
        {
            i++;
            Assert.True(i < lines.Length, fileName + " missing reg.exe call");
            string line = StripComment(lines[i]).Trim();
            if (line.StartsWith(prefix, StringComparison.Ordinal))
            {
                return line;
            }

            Assert.True(line.Length == 0, fileName + ": " + line);
        }
    }

    private static LiveRegWrite ParseCall(
        string line,
        string variable,
        IReadOnlyDictionary<string, string> variables,
        string? pairName,
        string? pairValue)
    {
        string pattern =
            "^" + Regex.Escape("& $" + variable)
            + @" -Path (?<path>.+?) -Name (?<name>.+?) -Type '(?<type>REG_[A-Z0-9_]+)' -Data (?<data>.+?) -DryRun:\$DryRun$";
        Match match = Regex.Match(line, pattern, RegexOptions.CultureInvariant);
        Assert.True(match.Success, line);
        return new LiveRegWrite(
            ExpandToken(match.Groups["path"].Value, variables, pairName, pairValue),
            ExpandToken(match.Groups["name"].Value, variables, pairName, pairValue),
            match.Groups["type"].Value,
            ExpandToken(match.Groups["data"].Value, variables, pairName, pairValue));
    }

    private static string ExpandToken(
        string token,
        IReadOnlyDictionary<string, string> variables,
        string? pairName,
        string? pairValue)
    {
        token = token.Trim();
        if (token == "$pair.Name")
        {
            Assert.NotNull(pairName);
            return pairName;
        }

        if (token == "$pair.Value")
        {
            Assert.NotNull(pairValue);
            return pairValue;
        }

        if (token.Length >= 2 && token[0] == '\'' && token[^1] == '\'')
        {
            return token[1..^1];
        }

        if (token.Length >= 2 && token[0] == '"' && token[^1] == '"')
        {
            return VariableToken.Replace(token[1..^1], match =>
            {
                string name = match.Groups[1].Value;
                Assert.True(variables.TryGetValue(name, out string? value), "$" + name);
                return value ?? throw new InvalidOperationException(name);
            });
        }

        if (token.StartsWith('$') && variables.TryGetValue(token[1..], out string? direct))
        {
            return direct;
        }

        Assert.Fail(token);
        throw new InvalidOperationException(token);
    }

    private static string StripBlockComments(string script)
    {
        StringBuilder builder = new();
        int i = 0;
        while (i < script.Length)
        {
            int start = script.IndexOf("<#", i, StringComparison.Ordinal);
            if (start < 0)
            {
                builder.Append(script[i..]);
                break;
            }

            builder.Append(script[i..start]);
            int end = script.IndexOf("#>", start + 2, StringComparison.Ordinal);
            Assert.True(end > start);
            i = end + 2;
        }

        return builder.ToString();
    }

    private static string StripComment(string line)
    {
        bool quoted = false;
        char quote = '\0';
        for (int i = 0; i < line.Length; i++)
        {
            char c = line[i];
            if (quoted)
            {
                if (c == quote)
                {
                    quoted = false;
                }

                continue;
            }

            if (c is '\'' or '"')
            {
                quoted = true;
                quote = c;
                continue;
            }

            if (c == '#')
            {
                return line[..i];
            }
        }

        return line;
    }

    private static string ProductPath(OfflinePolicyRow row)
    {
        string root = row.Hive switch
        {
            "SOFTWARE" => @"HKLM:\SOFTWARE",
            "SYSTEM" => @"HKLM:\SYSTEM",
            "NTUSER" => "HKCU:",
            _ => throw new InvalidOperationException(row.Hive),
        };

        return root + "\\" + row.SubKey.TrimStart('\\');
    }

    private static string Canonical(string path, string name)
    {
        string normalized = path.Replace('/', '\\').Replace(":", "", StringComparison.Ordinal);
        normalized = normalized.Replace(
            @"\CurrentControlSet\",
            @"\ControlSet001\",
            StringComparison.OrdinalIgnoreCase);
        return normalized + "|" + name;
    }

    private static HashSet<string> QuotedBlock(string script, string marker)
    {
        int start = script.IndexOf(marker, StringComparison.Ordinal);
        Assert.True(start >= 0, marker);
        start += marker.Length;
        int end = script.IndexOf(')', start);
        Assert.True(end > start);
        HashSet<string> set = new(StringComparer.Ordinal);
        foreach (Match match in Regex.Matches(script[start..end], "'([^']*)'"))
        {
            set.Add(match.Groups[1].Value);
        }

        return set;
    }

    private readonly record struct LiveRegWrite(string Path, string Name, string Type, string Data);
}
