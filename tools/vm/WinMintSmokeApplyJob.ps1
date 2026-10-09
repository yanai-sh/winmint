#requires -Version 7.6
# Windows Job Object (KILL_ON_JOB_CLOSE) for Smoke Apply only — not Watch.

Set-StrictMode -Version Latest

if (-not ('WinMintSmokeApplyJobNative' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class WinMintSmokeApplyJobNative
{
    public const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;
    public const int JobObjectExtendedLimitInformation = 9;

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

    public static void AssignProcess(IntPtr hJob, int processId)
    {
        var proc = System.Diagnostics.Process.GetProcessById(processId);
        proc.Refresh();
        if (!AssignProcessToJobObject(hJob, proc.Handle))
        {
            throw new System.ComponentModel.Win32Exception();
        }
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
    $proc = $null
    try {
        $hJob = [WinMintSmokeApplyJobNative]::CreateKillOnCloseJob()
    }
    catch {
        throw "smokeApplyJobFailed: CreateJobObject — $($_.Exception.Message)"
    }

    try {
        try {
            $proc = Start-Process -FilePath $just -WorkingDirectory (Get-Location) -PassThru -NoNewWindow `
                -ArgumentList @('apply-smoke-maintainer', $Iso, $Work, $ProfilePath)
        }
        catch {
            throw "smokeApplyJobFailed: Start-Process just — $($_.Exception.Message)"
        }

        try {
            [WinMintSmokeApplyJobNative]::AssignProcess($hJob, $proc.Id)
        }
        catch {
            throw "smokeApplyJobFailed: AssignProcessToJobObject — $($_.Exception.Message)"
        }

        Wait-Process -Id $proc.Id
        return $proc.ExitCode
    }
    finally {
        if ($null -ne $hJob -and $hJob -ne [IntPtr]::Zero) {
            [WinMintSmokeApplyJobNative]::CloseJob($hJob)
        }
    }
}
