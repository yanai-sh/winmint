using System.Diagnostics;
using System.Globalization;

namespace WinMint.WinPeApply;

/// <summary>Compares install.wim index 1 to the Windows volume before that volume is formatted.</summary>
internal static class ImageFit
{
    internal static int Decide(long imageBytes, long volumeBytes)
    {
        if (imageBytes <= 0 || volumeBytes <= 0)
        {
            return 1;
        }

        return imageBytes <= volumeBytes ? 0 : 2;
    }

    internal static bool TryParseDismSize(string text, out long bytes)
    {
        bytes = 0;
        foreach (string raw in text.Split('\n'))
        {
            string line = raw.Trim();
            if (!line.EndsWith("bytes", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            int colon = line.IndexOf(':');
            if (colon < 0)
            {
                continue;
            }

            string number = line[(colon + 1)..]
                .Replace("bytes", "", StringComparison.OrdinalIgnoreCase)
                .Replace(",", "", StringComparison.Ordinal)
                .Trim();
            if (long.TryParse(number, NumberStyles.None, CultureInfo.InvariantCulture, out long parsed) && parsed > 0)
            {
                bytes = parsed;
                return true;
            }
        }

        return false;
    }

    internal static int Run(string wim, string letter)
    {
        if (!TryDismBytes(wim, out long image) || !TryVolumeBytes(letter, out long volume))
        {
            return 1;
        }

        return Decide(image, volume);
    }

    private static bool TryDismBytes(string wim, out long bytes)
    {
        bytes = 0;
        using Process? process = Process.Start(new ProcessStartInfo
        {
            FileName = Path.Combine(Environment.SystemDirectory, "dism.exe"),
            Arguments = "/English /Get-WimInfo /Index:1 /WimFile:\"" + wim + "\"",
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
        });
        if (process is null)
        {
            return false;
        }

        string output = process.StandardOutput.ReadToEnd();
        if (!process.WaitForExit(120_000))
        {
            try
            {
                process.Kill(entireProcessTree: true);
            }
            catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception)
            {
            }

            return false;
        }

        return process.ExitCode == 0 && TryParseDismSize(output, out bytes);
    }

    private static bool TryVolumeBytes(string letter, out long bytes)
    {
        bytes = 0;
        string root = letter.Trim().TrimEnd('\\');
        if (root.Length == 1)
        {
            root += ":\\";
        }
        else if (root.Length == 2 && root[1] == ':')
        {
            root += "\\";
        }

        try
        {
            bytes = new DriveInfo(root).TotalSize;
            return bytes > 0;
        }
        catch (Exception ex) when (ex is ArgumentException or IOException or UnauthorizedAccessException or DriveNotFoundException)
        {
            return false;
        }
    }
}
