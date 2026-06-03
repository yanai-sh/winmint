# SetupComplete machine-phase module: remove the Microsoft Edge browser via the
# DMA-supported in-OS uninstall. This runs while the device is still in the EEA
# setup region (Ireland/en-IE), before FirstLogon restores the user's region —
# the only EULA-blessed window in which Edge is uninstallable. WebView2 / Edge
# *runtime* is never touched. We do NOT patch IntegratedServicesRegionPolicySet.
# Dot-sourced by SetupComplete.ps1; relies on its script-scope $logDir and the
# parsed $edgeRemove / $edgeKeep / $edgeDmaEnabled variables.

function Invoke-ScEdgeRemoval {
    $result = [ordered]@{
        generatedAt = Get-Date -Format o
        removeRequested = $edgeRemove
        keepEdge = $edgeKeep
        dmaInteropEnabled = $edgeDmaEnabled
        action = ''
        uninstallers = @()
        exitCodes = @()
        failed = @()
    }

    if (-not $edgeRemove) {
        $result.action = if ($edgeKeep) {
            'skipped: Edge kept (-KeepEdge); WinMint still applies the Edge debloat policies'
        }
        elseif (-not $edgeDmaEnabled) {
            'skipped: DMA interop disabled, no EEA uninstall window — Edge left installed'
        }
        else {
            'skipped: removal not requested'
        }
        Write-ScLog "Edge removal $($result.action)."
        $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $logDir 'SetupComplete_Edge.json') -Encoding UTF8
        return
    }

    # Locate the per-version Edge installer (system-level). WebView2 lives under
    # \EdgeWebView\ and is deliberately excluded.
    $installers = @()
    foreach ($base in @(
            "${env:ProgramFiles(x86)}\Microsoft\Edge\Application",
            "$env:ProgramFiles\Microsoft\Edge\Application"
        )) {
        if ([string]::IsNullOrWhiteSpace($base) -or -not (Test-Path -LiteralPath $base)) { continue }
        $installers += @(
            Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^\d' } |
                ForEach-Object { Join-Path $_.FullName 'Installer\setup.exe' } |
                Where-Object { Test-Path -LiteralPath $_ }
        )
    }
    $installers = @($installers | Select-Object -Unique)

    if ($installers.Count -eq 0) {
        $result.action = 'no Edge system-level setup.exe found; nothing to uninstall'
        Write-ScLog $result.action
        $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $logDir 'SetupComplete_Edge.json') -Encoding UTF8
        return
    }

    $result.action = 'uninstalling Edge browser (DMA EEA window); WebView2 runtime preserved'
    foreach ($setup in $installers) {
        try {
            $p = Start-Process -FilePath $setup -ArgumentList @(
                '--uninstall', '--msedge', '--system-level', '--verbose-logging', '--force-uninstall'
            ) -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
            $result.uninstallers += $setup
            $result.exitCodes += [int]$p.ExitCode
            Write-ScLog "Edge uninstall '$setup' exit $($p.ExitCode)."
        }
        catch {
            $result.failed += [ordered]@{ target = $setup; error = [string]$_ }
            "Edge uninstall failed for ${setup}: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
        }
    }

    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $logDir 'SetupComplete_Edge.json') -Encoding UTF8
}
