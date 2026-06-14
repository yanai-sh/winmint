# SetupComplete machine-phase module: form-factor-aware power profile.
# Dot-sourced by SetupComplete.ps1; relies on its script-scope $logDir,
# $powerFormFactor, $powerDisableHibernationOnDesktop, $powerDesktopPlan.

function Test-ScIsLaptopChassis {
    # Win32_SystemEnclosure ChassisTypes codes for portable/laptop/notebook/handheld/tablet/convertible/detachable.
    try {
        $types = @((Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop).ChassisTypes)
    }
    catch {
        return $false
    }
    $laptopCodes = @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32)
    foreach ($t in $types) {
        if ([int]$t -in $laptopCodes) { return $true }
    }
    return $false
}

function Invoke-ScPowerProfile {
    $result = [ordered]@{ formFactor = $powerFormFactor; effective = ''; actions = @(); failed = @() }
    $effective = $powerFormFactor
    if ($effective -eq 'Auto') {
        $effective = if (Test-ScIsLaptopChassis) { 'Laptop' } else { 'Desktop' }
    }
    $result.effective = $effective
    if ($effective -ne 'Desktop') {
        Write-ScLog "Power profile: form factor '$effective' — keeping battery-friendly defaults."
        $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $logDir 'SetupComplete_Power.json') -Encoding UTF8
        return
    }
    $powercfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
    if ($powerDisableHibernationOnDesktop) {
        try {
            & $powercfg /hibernate off | Out-Null
            $result.actions += 'hibernate-off'
            Write-ScLog 'Power profile: hibernation disabled (desktop).'
        }
        catch {
            $result.failed += [ordered]@{ action = 'HibernateOff'; error = [string]$_ }
            "powercfg hibernate off failed: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
        }
    }
    if ($powerDesktopPlan -eq 'HighPerformance') {
        try {
            # High Performance scheme GUID (built-in on client SKUs).
            & $powercfg /setactive '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' | Out-Null
            $result.actions += 'plan-highperformance'
            Write-ScLog 'Power profile: High Performance plan activated (desktop).'
        }
        catch {
            $result.failed += [ordered]@{ action = 'SetActivePlan'; error = [string]$_ }
            "powercfg setactive failed: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
        }
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $logDir 'SetupComplete_Power.json') -Encoding UTF8
}
