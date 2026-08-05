namespace WinMint.Provisioning;

/// <summary>Best-effort guest self-erase after Shell Complete (ADR-008).</summary>
public sealed class Win32ResidueCleaner : IResidueCleaner
{
    private readonly IWinlogonRegistry _winlogon;
    private readonly Action<string>? _log;
    private readonly string _winMintDir;
    private readonly string _setupCompletePath;

    public Win32ResidueCleaner(
        IWinlogonRegistry winlogon,
        Action<string>? log = null,
        string? windowsDirectory = null)
    {
        _winlogon = winlogon;
        _log = log;
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
            _winlogon.ClearAutoLogon();
            _log?.Invoke("residue: cleared AutoAdminLogon stamps");
        }
        catch (Exception ex)
        {
            _log?.Invoke($"residue: ClearAutoLogon failed: {ex.Message}");
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
                _log?.Invoke($"residue: deleted {path}");
            }
        }
        catch (Exception ex)
        {
            _log?.Invoke($"residue: delete file failed ({path}): {ex.Message}");
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
                    _log?.Invoke($"residue: delete file failed ({file}): {ex.Message}");
                }
            }

            try
            {
                Directory.Delete(path, recursive: true);
                _log?.Invoke($"residue: deleted {path}");
            }
            catch (Exception ex)
            {
                _log?.Invoke($"residue: delete tree failed ({path}): {ex.Message}");
            }
        }
        catch (Exception ex)
        {
            _log?.Invoke($"residue: delete tree failed ({path}): {ex.Message}");
        }
    }
}
