# SetupComplete machine-phase module: small one-shot system hygiene steps.
# Dot-sourced by SetupComplete.ps1; relies on its script-scope $logDir.

function Invoke-ScTimeSync {
    try {
        Start-Service w32time -ErrorAction SilentlyContinue
        w32tm.exe /config /update | Out-Null
        w32tm.exe /resync /force | Out-Null
    }
    catch {
        "Time sync failed: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
    }
}

function Invoke-ScDesktopShortcutCleanup {
    foreach ($p in @('C:\Users\Default\Desktop\*.lnk', 'C:\Users\Public\Desktop\*.lnk')) {
        Remove-Item -Path $p -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-ScBitLockerNote {
    try {
        $bitLockerVolume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
        if ($bitLockerVolume -and $bitLockerVolume.ProtectionStatus -eq 'On') {
            Write-ScLog 'Leaving active BitLocker protection enabled; WinMint only prevents automatic device encryption.'
        }
    }
    catch { }
}

function Invoke-ScBootTimeout {
    if ((bcdedit.exe | Select-String 'path').Count -eq 2) {
        $null = & bcdedit.exe /set '{bootmgr}' timeout 2
    }
}

function Invoke-ScActivationCheck {
    Start-Sleep -Seconds 15
    $log = Join-Path $logDir 'Activation.log'
    "$(Get-Date -Format s) Activation check" | Out-File $log
    $r = & cscript.exe //nologo "$env:SystemRoot\System32\slmgr.vbs" /xpr 2>&1
    $r | Out-File $log -Append
    if ($r -notmatch 'permanently activated|will expire') {
        'WARN: not activated.' | Out-File $log -Append
    }
}

function Invoke-ScNpuDetection {
    try {
        $log = Join-Path $logDir 'NPU.log'
        "$(Get-Date -Format s) NPU detection" | Out-File $log
        $npu = Get-PnpDevice -ErrorAction Stop |
            Where-Object { $_.FriendlyName -match 'Hexagon|Qualcomm.*NPU|Qualcomm.*Compute|Neural' }
        if ($npu) {
            'OK: NPU device(s) found:' | Out-File $log -Append
            $npu | ForEach-Object { "  $($_.Status) - $($_.FriendlyName)" | Out-File $log -Append }
        }
        else {
            'WARN: No NPU device detected.' | Out-File $log -Append
        }
    }
    catch { }
}
