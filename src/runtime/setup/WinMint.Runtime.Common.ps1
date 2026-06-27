#Requires -Version 5.1

function Initialize-WinMintConsoleEncoding {
    try {
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [Console]::InputEncoding = $utf8
        [Console]::OutputEncoding = $utf8
        $global:OutputEncoding = $utf8
        $global:PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
        $global:PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
        $global:PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
    }
    catch { }
    try {
        $chcpExe = Join-Path $env:SystemRoot 'System32\chcp.com'
        $null = & $chcpExe 65001 2>$null
    }
    catch { }
}

function Resolve-WinMintPowerShell7Host {
    if ($script:WinMintPowerShell7HostOverride) {
        $override = [string]$script:WinMintPowerShell7HostOverride
        if (Test-Path -LiteralPath $override) { return $override }
    }

    $pwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    if (Test-Path -LiteralPath $pwsh) { return $pwsh }

    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath) -and
        (Test-Path -LiteralPath $PSCommandPath) -and
        [string]::Equals([IO.Path]::GetFileName($PSCommandPath), 'pwsh.exe', [StringComparison]::OrdinalIgnoreCase)) {
        return $PSCommandPath
    }

    try {
        $current = (Get-Process -Id $PID).Path
        if ($current -and (Test-Path -LiteralPath $current) -and
            [string]::Equals([IO.Path]::GetFileName($current), 'pwsh.exe', [StringComparison]::OrdinalIgnoreCase)) {
            return $current
        }
    }
    catch { }

    $cmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
        return $cmd.Source
    }

    throw "PowerShell 7 is required for WinMint but was not found: $pwsh"
}

function Test-WinMintProcessElevated {
    if (-not ('WinMint.TokenElevation' -as [type])) {
        Add-Type -Namespace WinMint -Name TokenElevation -MemberDefinition @'
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct TOKEN_ELEVATION {
    public int TokenIsElevated;
}
[System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError = true)]
public static extern bool OpenProcessToken(System.IntPtr ProcessHandle, uint DesiredAccess, out System.IntPtr TokenHandle);
[System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError = true)]
public static extern bool GetTokenInformation(System.IntPtr TokenHandle, int TokenInformationClass, out TOKEN_ELEVATION TokenInformation, int TokenInformationLength, out int ReturnLength);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern bool CloseHandle(System.IntPtr hObject);
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern System.IntPtr GetCurrentProcess();
'@
    }

    $TOKEN_QUERY = 0x0008
    $TokenElevation = 20
    $tokenHandle = [IntPtr]::Zero
    if (-not [WinMint.TokenElevation]::OpenProcessToken([WinMint.TokenElevation]::GetCurrentProcess(), [uint32]$TOKEN_QUERY, [ref]$tokenHandle)) {
        return $false
    }

    try {
        $elevation = New-Object WinMint.TokenElevation+TOKEN_ELEVATION
        $returnLength = 0
        $size = [System.Runtime.InteropServices.Marshal]::SizeOf($elevation)
        if ([WinMint.TokenElevation]::GetTokenInformation($tokenHandle, $TokenElevation, [ref]$elevation, $size, [ref]$returnLength)) {
            return ($elevation.TokenIsElevated -ne 0)
        }
        return $false
    }
    finally {
        if ($tokenHandle -ne [IntPtr]::Zero) {
            [WinMint.TokenElevation]::CloseHandle($tokenHandle) | Out-Null
        }
    }
}

function Save-WinMintAtomicJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Data,
        [int]$Depth = 12,
        [switch]$RemoveDestinationFirst
    )

    $json = $Data | ConvertTo-Json -Depth $Depth
    $tmp = "$Path.tmp"
    $json | Set-Content -LiteralPath $tmp -Encoding UTF8
    $null = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($RemoveDestinationFirst -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Force
    }
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Read-WinMintJsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        $Fallback = $null,
        [scriptblock]$OnError = $null
    )

    try {
        if (Test-Path -LiteralPath $Path) {
            return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    }
    catch {
        if ($OnError) { & $OnError $_ }
    }
    return $Fallback
}

function Import-WinMintRuntimeCommon {
    param([Parameter(Mandatory)][string]$AgentRoot)

    if (Get-Command Save-WinMintAtomicJson -ErrorAction SilentlyContinue) { return }

    foreach ($candidate in @(
            Join-Path (Split-Path -Parent $AgentRoot) 'WinMint.Runtime.Common.ps1'
            Join-Path $AgentRoot 'WinMint.Runtime.Common.ps1'
        )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            . $candidate
            return
        }
    }
    throw "WinMint.Runtime.Common.ps1 is missing for agent root '$AgentRoot'."
}
