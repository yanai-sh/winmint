using Microsoft.Extensions.Logging;

namespace WinMint.Provisioning;

/// <summary>Best-effort guest self-erase after Shell Complete (ADR-008).</summary>
public sealed class Win32ResidueCleaner : IResidueCleaner
{
    private readonly Action _clearAutoLogon;
    private readonly ILogger? _logger;
    private readonly string _winMintDir;
    private readonly string _setupCompletePath;

    public Win32ResidueCleaner(
        ILogger? logger = null,
        string? windowsDirectory = null)
        : this(Win32WinlogonRegistry.ClearAutoLogon, logger, windowsDirectory)
    {
    }

    internal Win32ResidueCleaner(
        Action clearAutoLogon,
        ILogger? logger = null,
        string? windowsDirectory = null)
    {
        ArgumentNullException.ThrowIfNull(clearAutoLogon);
        _clearAutoLogon = clearAutoLogon;
        _logger = logger;
        string windir = windowsDirectory
            ?? Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        if (string.IsNullOrWhiteSpace(windir))
        {
            windir = @"C:\Windows";
        }

        _winMintDir = Path.Combine(windir, "WinMint");
        _setupCompletePath = Path.Combine(windir, "Setup", "Scripts", "SetupComplete.cmd");
    }

    public void TryEraseAfterComplete()
    {
        try
        {
            _clearAutoLogon();
            if (_logger is not null)
            {
                GuestLog.ResidueCleared(_logger);
            }
        }
        catch (Exception ex)
        {
            if (_logger is not null)
            {
                GuestLog.ResidueClearFailed(_logger, ex.Message);
            }
        }

        TryDeleteFile(_setupCompletePath);
        TryDeleteTree(_winMintDir);
    }

    private void TryDeleteFile(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
                LogDeleted(path);
            }
        }
        catch (Exception ex)
        {
            LogDeleteFailed(path, ex.Message);
        }
    }

    private void TryDeleteTree(string path)
    {
        try
        {
            if (!Directory.Exists(path))
            {
                return;
            }

            foreach (string file in Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories))
            {
                try
                {
                    File.SetAttributes(file, FileAttributes.Normal);
                    File.Delete(file);
                }
                catch (Exception ex)
                {
                    // ponytail: Supervisor.exe may still be locked while this process runs
                    LogDeleteFailed(file, ex.Message);
                }
            }

            try
            {
                Directory.Delete(path, recursive: true);
                LogDeleted(path);
            }
            catch (Exception ex)
            {
                LogDeleteFailed(path, ex.Message);
            }
        }
        catch (Exception ex)
        {
            LogDeleteFailed(path, ex.Message);
        }
    }

    private void LogDeleted(string path)
    {
        if (_logger is not null)
        {
            GuestLog.ResidueDeleted(_logger, path);
        }
    }

    private void LogDeleteFailed(string path, string message)
    {
        if (_logger is not null)
        {
            GuestLog.ResidueDeleteFailed(_logger, path, message);
        }
    }
}
