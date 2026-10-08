#requires -Version 7.6
Set-StrictMode -Version Latest

function Write-SmokeStatus {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Phase,
        [Parameter(Mandatory)][string] $VmName,
        $VmState = $null,
        $Cpu = $null,
        $Heartbeat = $null,
        $VhdFileSizeMB = $null,
        [int] $StallMinutesLeft = 0,
        [int] $WallMinutesLeft = 0,
        [string] $LastHostLine = '',
        $OutputIso = $null,
        [int] $WaiterPid = 0,
        [string] $RunId = '',
        [int] $SetupRebootCount = 0
    )
    try {
        $dir = Split-Path -Parent $Path
        if ($dir) { New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null }
        if ($WaiterPid -le 0) { $WaiterPid = [int]$PID }
        $doc = [ordered]@{
            schemaVersion    = 'winmint.smoke.status/v1'
            updatedAt        = [datetime]::UtcNow.ToString('o')
            runId            = $RunId
            phase            = $Phase
            vmName           = $VmName
            vmState          = $VmState
            cpu              = $Cpu
            heartbeat        = $Heartbeat
            vhdFileSizeMB    = $VhdFileSizeMB
            stallMinutesLeft = $StallMinutesLeft
            wallMinutesLeft  = $WallMinutesLeft
            lastHostLine     = $LastHostLine
            outputIso        = $OutputIso
            waiterPid         = $WaiterPid
            setupRebootCount  = $SetupRebootCount
        }
        ($doc | ConvertTo-Json -Compress) | Set-Content -LiteralPath $Path -Encoding utf8 -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not write Smoke status: $($_.Exception.Message)"
    }
}

function Start-SmokeMonitor {
    param(
        [Parameter(Mandatory)][string] $VmName,
        [string] $ConnectExe = (Join-Path $env:WINDIR 'System32\vmconnect.exe'),
        [scriptblock] $Launcher = {
            param($Exe, $Name)
            Start-Process -FilePath $Exe -ArgumentList @('localhost', $Name)
        }
    )
    if (-not (Test-Path -LiteralPath $ConnectExe)) {
        Write-Warning "vmconnect.exe not found; continuing headless"
        return
    }
    try {
        & $Launcher $ConnectExe $VmName
    }
    catch {
        Write-Warning "Could not start VMConnect: $($_.Exception.Message)"
    }
}

function ConvertTo-WinMintBmp565 {
    <#
    .SYNOPSIS
      Wrap a raw RGB565 pixel buffer (Msvm thumbnail wire format) as a top-down 16bpp
      BI_BITFIELDS BMP. Pure — no Hyper-V.
    #>
    param(
        [Parameter(Mandatory)] [byte[]] $PixelData,
        [Parameter(Mandatory)] [int] $Width,
        [Parameter(Mandatory)] [int] $Height
    )
    $stride = $Width * 2
    if ($stride % 4 -ne 0) {
        throw "ConvertTo-WinMintBmp565 needs a 4-byte-aligned row (width $Width is not)"
    }
    if ($PixelData.Length -ne ($stride * $Height)) {
        throw "pixel buffer $($PixelData.Length) bytes != ${Width}x${Height}x2"
    }
    $headerSize = 14 + 40 + 12
    $ms = [IO.MemoryStream]::new()
    $bw = [IO.BinaryWriter]::new($ms)
    try {
        $bw.Write([byte]0x42); $bw.Write([byte]0x4D)          # 'BM'
        $bw.Write([int]($headerSize + $PixelData.Length))     # file size
        $bw.Write([int]0)                                     # reserved
        $bw.Write([int]$headerSize)                           # pixel offset
        $bw.Write([int]40)                                    # BITMAPINFOHEADER size
        $bw.Write([int]$Width)
        $bw.Write([int](-$Height))                            # negative height = top-down rows
        $bw.Write([int16]1)                                   # planes
        $bw.Write([int16]16)                                  # bpp
        $bw.Write([int]3)                                     # BI_BITFIELDS
        $bw.Write([int]$PixelData.Length)
        $bw.Write([int]2835); $bw.Write([int]2835)            # 72 DPI
        $bw.Write([int]0); $bw.Write([int]0)                  # palette
        $bw.Write([int]0xF800); $bw.Write([int]0x07E0); $bw.Write([int]0x001F)
        $bw.Write($PixelData)
        $bw.Flush()
        return , $ms.ToArray()
    }
    finally {
        $bw.Dispose()
        $ms.Dispose()
    }
}

function Save-SmokeVmScreenshot {
    <#
    .SYNOPSIS
      Best-effort VM console screenshot for post-mortem (which screen was the guest on?).
      Diagnostics only — never an acceptance input (witnessed-smoke spec).
    #>
    param(
        [Parameter(Mandatory)] [string] $VmName,
        [Parameter(Mandatory)] [string] $Path,
        [int] $Width = 640,
        [int] $Height = 480
    )
    try {
        $vmCs = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem `
            -Filter "ElementName='$VmName'" -ErrorAction Stop
        if ($null -eq $vmCs) { return $false }
        $svc = Get-CimInstance -Namespace root\virtualization\v2 `
            -ClassName Msvm_VirtualSystemManagementService -ErrorAction Stop
        $result = Invoke-CimMethod -InputObject $svc -MethodName GetVirtualSystemThumbnailImage -Arguments @{
            HeightPixels = [uint16]$Height
            WidthPixels  = [uint16]$Width
            TargetSystem = $vmCs
        }
        if ($null -eq $result -or $result.ReturnValue -ne 0 -or -not $result.ImageData) { return $false }
        $dir = Split-Path -Parent $Path
        if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $bmp = ConvertTo-WinMintBmp565 -PixelData ([byte[]]$result.ImageData) -Width $Width -Height $Height
        [IO.File]::WriteAllBytes($Path, $bmp)
        Write-Host "VM console screenshot → $Path"
        return $true
    }
    catch {
        Write-Warning "Could not capture VM console screenshot: $($_.Exception.Message)"
        return $false
    }
}

function Get-SmokeWatchVerdict {
    <#
    .SYNOPSIS
      Watch-only verdict from Hyper-V-native signals + status freshness. Never infers death from PIDs.
    .NOTES
      Invoke-Smoke throws on empty-vhd. Watchers must not Stop-VM / Remove-VM;
      harness-stale stays watch-only.
      External watchers pass -PriorRunId (runId of any status present at watch
      start; empty when none) so a carried-over terminal status reads as
      awaiting-run, never done. Invoke-Smoke's own wait loop omits it.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Phase,
        [string] $VmState = '',
        [int] $VhdFileSizeMB = 0,
        [int] $StatusAgeSeconds = 0,
        [int] $EmptyVhdRunningSeconds = 0,
        [int] $EmptyVhdFailAfterSeconds = 480,
        [int] $HarnessStaleAfterSeconds = 120,
        [string] $StatusRunId = '',
        [string] $PriorRunId = ''
    )
    # Run identity first: a status left by a prior run must never be this run's outcome.
    if ($PSBoundParameters.ContainsKey('PriorRunId') -and $StatusRunId -eq $PriorRunId) {
        return 'awaiting-run'
    }
    if ($Phase -in @('green', 'failed', 'assert')) {
        return 'done'
    }
    # DISM Apply can run for hours without a status refresh.
    if ($Phase -eq 'apply') {
        return 'continue'
    }
    if ($VmState -eq 'Running' -and $VhdFileSizeMB -lt 1024 -and
        $EmptyVhdRunningSeconds -ge $EmptyVhdFailAfterSeconds) {
        return 'empty-vhd'
    }
    if ($StatusAgeSeconds -gt $HarnessStaleAfterSeconds) {
        return 'harness-stale'
    }
    return 'continue'
}
