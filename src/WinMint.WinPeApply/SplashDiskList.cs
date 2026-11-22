using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace WinMint.WinPeApply;

/// <summary>Number, size, and model for the host splash preview. Read-only.</summary>
internal readonly record struct SplashDisk(int Number, string Size, string Model);

/// <summary>Reads disks for the splash preview. diskpart is only asked to list and detail.</summary>
internal static partial class SplashDiskList
{
    internal const string ListScript = "list disk\r\nexit\r\n";

    internal static string DetailScript(int number)
    {
        if (number is < 0 or > 999)
        {
            throw new ArgumentOutOfRangeException(nameof(number));
        }

        return string.Create(CultureInfo.InvariantCulture, $"select disk {number}\r\ndetail disk\r\nexit\r\n");
    }

    internal static bool IsListOnly(string script)
    {
        foreach (string raw in script.Split(["\r\n", "\n"], StringSplitOptions.None))
        {
            string line = raw.Trim();
            if (line.Length == 0
                || line.Equals("list disk", StringComparison.OrdinalIgnoreCase)
                || line.Equals("detail disk", StringComparison.OrdinalIgnoreCase)
                || line.Equals("exit", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (!line.StartsWith("select disk ", StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            if (!int.TryParse(line.AsSpan("select disk ".Length), NumberStyles.None, CultureInfo.InvariantCulture, out int number)
                || number is < 0 or > 999)
            {
                return false;
            }
        }

        return true;
    }

    internal static IReadOnlyList<SplashDisk> Read(out string? note)
    {
        note = null;
        if (TryDiskpart(out IReadOnlyList<SplashDisk> disks) && disks.Count > 0)
        {
            return disks;
        }

        if (TryCim(out disks) && disks.Count > 0)
        {
            return disks;
        }

        return [];
    }

    internal static IReadOnlyList<SplashDisk> ParseList(string output)
    {
        List<SplashDisk> rows = [];
        foreach (Match match in ListRow().Matches(output))
        {
            if (!int.TryParse(match.Groups["n"].Value, NumberStyles.None, CultureInfo.InvariantCulture, out int number))
            {
                continue;
            }

            rows.Add(new SplashDisk(number, match.Groups["size"].Value.Trim(), ""));
        }

        return rows;
    }

    internal static string ParseModel(string detail)
    {
        foreach (string raw in detail.Split('\n'))
        {
            string line = raw.Trim();
            if (line.Length == 0
                || line.StartsWith("Microsoft DiskPart", StringComparison.Ordinal)
                || line.StartsWith("Copyright", StringComparison.Ordinal)
                || line.StartsWith("On computer:", StringComparison.Ordinal)
                || line.StartsWith("Disk ", StringComparison.Ordinal)
                || line.StartsWith("Volume", StringComparison.Ordinal)
                || line.StartsWith('-')
                || line.Contains(':', StringComparison.Ordinal))
            {
                continue;
            }

            return line.Length > 120 ? line[..120] : line;
        }

        return "";
    }

    internal static string FormatSize(ulong bytes)
    {
        const double gb = 1024d * 1024d * 1024d;
        const double mb = 1024d * 1024d;
        if (bytes >= (ulong)gb)
        {
            return string.Create(CultureInfo.InvariantCulture, $"{Math.Round(bytes / gb):0} GB");
        }

        if (bytes >= (ulong)mb)
        {
            return string.Create(CultureInfo.InvariantCulture, $"{Math.Round(bytes / mb):0} MB");
        }

        return string.Create(CultureInfo.InvariantCulture, $"{bytes} B");
    }

    private static bool TryDiskpart(out IReadOnlyList<SplashDisk> disks)
    {
        disks = [];
        string? listed = RunDiskpart(ListScript);
        if (listed is null)
        {
            return false;
        }

        List<SplashDisk> rows = [.. ParseList(listed)];
        for (int i = 0; i < rows.Count; i++)
        {
            string? detail = RunDiskpart(DetailScript(rows[i].Number));
            if (detail is null)
            {
                continue;
            }

            rows[i] = rows[i] with { Model = ParseModel(detail) };
        }

        disks = rows;
        return true;
    }

    private static string? RunDiskpart(string script)
    {
        if (!IsListOnly(script))
        {
            throw new InvalidOperationException("Splash diskpart is list and detail only.");
        }

        string path = Path.Combine(Path.GetTempPath(), "winmint-splash-list-" + Guid.NewGuid().ToString("N") + ".txt");
        try
        {
            File.WriteAllText(path, script, Encoding.ASCII);
            return Run(Path.Combine(Environment.SystemDirectory, "diskpart.exe"), "/s \"" + path + "\"", 8000);
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
        finally
        {
            try
            {
                File.Delete(path);
            }
            catch (IOException)
            {
            }
        }
    }

    private static bool TryCim(out IReadOnlyList<SplashDisk> disks)
    {
        disks = [];
        string? output = Run(
            Path.Combine(Environment.SystemDirectory, "WindowsPowerShell\\v1.0\\powershell.exe"),
            "-NoProfile -NonInteractive -Command \"Get-CimInstance -ClassName Win32_DiskDrive | ForEach-Object { '{0}|{1}|{2}' -f $_.Index, $_.Size, (($_.Model) -replace '[\\r\\n|]',' ') }\"",
            8000);
        if (output is null)
        {
            return false;
        }

        List<SplashDisk> rows = [];
        foreach (string raw in output.Split('\n'))
        {
            string[] parts = raw.Trim().Split('|');
            if (parts.Length < 3
                || !int.TryParse(parts[0], NumberStyles.None, CultureInfo.InvariantCulture, out int number)
                || !ulong.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out ulong bytes))
            {
                continue;
            }

            rows.Add(new SplashDisk(number, FormatSize(bytes), parts[2].Trim()));
        }

        disks = rows;
        return true;
    }

    private static string? Run(string fileName, string arguments, int timeoutMs)
    {
        if (!File.Exists(fileName))
        {
            return null;
        }

        using Process process = new()
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = fileName,
                Arguments = arguments,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            },
        };

        StringBuilder output = new();
        process.OutputDataReceived += (_, e) =>
        {
            if (e.Data is not null)
            {
                _ = output.AppendLine(e.Data);
            }
        };
        process.ErrorDataReceived += (_, _) => { };
        try
        {
            if (!process.Start())
            {
                return null;
            }
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            return null;
        }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        if (!process.WaitForExit(timeoutMs))
        {
            try
            {
                process.Kill(entireProcessTree: true);
            }
            catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception)
            {
            }

            return null;
        }

        process.WaitForExit();
        return output.ToString();
    }

    [GeneratedRegex(@"^\s*Disk\s+(?<n>\d+)\s+.+?\s{2,}(?<size>\d+(?:\.\d+)?\s*(?:TB|GB|MB|KB|B))\b", RegexOptions.Multiline | RegexOptions.CultureInvariant)]
    private static partial Regex ListRow();
}
