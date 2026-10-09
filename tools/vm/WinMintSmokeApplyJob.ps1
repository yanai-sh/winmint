#requires -Version 7.6
# Windows Job Object (KILL_ON_JOB_CLOSE) for Smoke Apply only — not Watch.

Set-StrictMode -Version Latest

if (-not ('WinMintSmokeApplyJobNative' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class WinMintSmokeApplyJobNative
{
    public const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;
    public const int JobObjectExtendedLimitInformation = 9;
    public const uint CREATE_SUSPENDED = 0x00000004;
    public const uint CREATE_NO_WINDOW = 0x08000000;

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public long Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct IO_COUNTERS
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO
    {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION
    {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetInformationJobObject(
        IntPtr hJob,
        int JobObjectInfoClass,
        IntPtr lpJobObjectInfo,
        uint cbJobObjectInfoLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(
        string lpApplicationName,
        StringBuilder lpCommandLine,
        IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes,
        bool bInheritHandles,
        uint dwCreationFlags,
        IntPtr lpEnvironment,
        string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo,
        out PROCESS_INFORMATION lpProcessInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint ResumeThread(IntPtr hThread);

    public static IntPtr CreateKillOnCloseJob()
    {
        IntPtr hJob = CreateJobObject(IntPtr.Zero, null);
        if (hJob == IntPtr.Zero)
        {
            throw new System.ComponentModel.Win32Exception();
        }

        var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        int length = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
        IntPtr extendedInfoPtr = Marshal.AllocHGlobal(length);
        try
        {
            Marshal.StructureToPtr(info, extendedInfoPtr, false);
            if (!SetInformationJobObject(hJob, JobObjectExtendedLimitInformation, extendedInfoPtr, (uint)length))
            {
                CloseHandle(hJob);
                throw new System.ComponentModel.Win32Exception();
            }
        }
        finally
        {
            Marshal.FreeHGlobal(extendedInfoPtr);
        }

        return hJob;
    }

    static void AppendArgument(StringBuilder sb, string argument)
    {
        if (string.IsNullOrEmpty(argument))
        {
            sb.Append("\"\"");
            return;
        }

        bool needsQuotes = false;
        for (int i = 0; i < argument.Length; i++)
        {
            char c = argument[i];
            if (c <= ' ' || c == '"')
            {
                needsQuotes = true;
                break;
            }
        }

        if (!needsQuotes)
        {
            sb.Append(argument);
            return;
        }

        sb.Append('"');
        for (int i = 0; i < argument.Length; i++)
        {
            int backslashes = 0;
            while (i < argument.Length && argument[i] == '\\')
            {
                backslashes++;
                i++;
            }

            if (i == argument.Length)
            {
                sb.Append('\\', backslashes * 2);
            }
            else if (argument[i] == '"')
            {
                sb.Append('\\', backslashes * 2 + 1);
                sb.Append('"');
            }
            else
            {
                sb.Append('\\', backslashes);
                sb.Append(argument[i]);
            }
        }
        sb.Append('"');
    }

    static StringBuilder BuildCommandLine(string applicationName, string[] arguments)
    {
        var cmd = new StringBuilder();
        cmd.Append('"').Append(applicationName).Append('"');
        if (arguments != null)
        {
            foreach (var arg in arguments)
            {
                cmd.Append(' ');
                AppendArgument(cmd, arg ?? string.Empty);
            }
        }
        return cmd;
    }

    public static PROCESS_INFORMATION StartSuspendedProcess(
        string applicationName,
        string workingDirectory,
        string[] arguments)
    {
        var si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        var cmd = BuildCommandLine(applicationName, arguments);
        PROCESS_INFORMATION pi;
        if (!CreateProcessW(
                applicationName,
                cmd,
                IntPtr.Zero,
                IntPtr.Zero,
                false,
                CREATE_SUSPENDED | CREATE_NO_WINDOW,
                IntPtr.Zero,
                workingDirectory,
                ref si,
                out pi))
        {
            throw new System.ComponentModel.Win32Exception();
        }

        return pi;
    }

    public static void AssignProcessHandle(IntPtr hJob, IntPtr hProcess)
    {
        if (!AssignProcessToJobObject(hJob, hProcess))
        {
            throw new System.ComponentModel.Win32Exception();
        }
    }

    public static void ResumePrimaryThread(IntPtr hThread)
    {
        if (ResumeThread(hThread) == unchecked((uint)-1))
        {
            throw new System.ComponentModel.Win32Exception();
        }
    }

    public static void AssignProcess(IntPtr hJob, int processId)
    {
        var proc = System.Diagnostics.Process.GetProcessById(processId);
        proc.Refresh();
        AssignProcessHandle(hJob, proc.Handle);
    }

    public static void CloseJob(IntPtr hJob)
    {
        if (hJob != IntPtr.Zero)
        {
            CloseHandle(hJob);
        }
    }
}
'@
}

function Invoke-WinMintSmokeApplyMaintainer {
    param(
        [Parameter(Mandatory)] [string] $Iso,
        [Parameter(Mandatory)] [string] $Work,
        [Parameter(Mandatory)] [string] $ProfilePath
    )

    $just = (Get-Command just -ErrorAction Stop).Source
    $hJob = [IntPtr]::Zero
    $pi = [WinMintSmokeApplyJobNative+PROCESS_INFORMATION]::default
    $assigned = $false
    try {
        $hJob = [WinMintSmokeApplyJobNative]::CreateKillOnCloseJob()
    }
    catch {
        throw "smokeApplyJobFailed: CreateJobObject — $($_.Exception.Message)"
    }

    try {
        try {
            $pi = [WinMintSmokeApplyJobNative]::StartSuspendedProcess(
                $just,
                (Get-Location).Path,
                @('apply-smoke-maintainer', $Iso, $Work, $ProfilePath))
        }
        catch {
            throw "smokeApplyJobFailed: CreateProcess (suspended) — $($_.Exception.Message)"
        }

        try {
            # ponytail: CREATE_BREAKAWAY_FROM_JOB can still escape descendants; upgrade path is JOB_OBJECT_LIMIT_BREAKAWAY_OK off + tooling that does not break away
            [WinMintSmokeApplyJobNative]::AssignProcessHandle($hJob, $pi.hProcess)
            $assigned = $true
        }
        catch {
            throw "smokeApplyJobFailed: AssignProcessToJobObject — $($_.Exception.Message)"
        }

        try {
            [WinMintSmokeApplyJobNative]::ResumePrimaryThread($pi.hThread)
        }
        catch {
            throw "smokeApplyJobFailed: ResumeThread — $($_.Exception.Message)"
        }
        finally {
            if ($pi.hThread -ne [IntPtr]::Zero) {
                [WinMintSmokeApplyJobNative]::CloseHandle($pi.hThread) | Out-Null
                $pi.hThread = [IntPtr]::Zero
            }
        }

        $proc = [System.Diagnostics.Process]::GetProcessById($pi.dwProcessId)
        $proc.WaitForExit()
        return $proc.ExitCode
    }
    finally {
        if (-not $assigned -and $pi.hProcess -ne [IntPtr]::Zero) {
            Stop-Process -Id $pi.dwProcessId -Force -ErrorAction SilentlyContinue
        }
        if ($pi.hProcess -ne [IntPtr]::Zero) {
            [WinMintSmokeApplyJobNative]::CloseHandle($pi.hProcess) | Out-Null
        }
        if ($null -ne $hJob -and $hJob -ne [IntPtr]::Zero) {
            [WinMintSmokeApplyJobNative]::CloseJob($hJob)
        }
    }
}
