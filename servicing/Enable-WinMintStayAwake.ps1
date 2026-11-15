#requires -Version 7.6
# Keep the host out of idle sleep for the calling thread. Process exit drops the request.
Set-StrictMode -Version Latest

function Enable-WinMintStayAwake {
    if (-not ('WinMint.HostStayAwake' -as [type])) {
        Add-Type -Namespace WinMint -Name HostStayAwake -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern uint SetThreadExecutionState(uint esFlags);
'@
    }
    # ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED
    $on = [uint32]2147483648 -bor [uint32]1 -bor [uint32]64
    [void][WinMint.HostStayAwake]::SetThreadExecutionState($on)
}

function Disable-WinMintStayAwake {
    if (-not ('WinMint.HostStayAwake' -as [type])) { return }
    [void][WinMint.HostStayAwake]::SetThreadExecutionState([uint32]2147483648)
}
