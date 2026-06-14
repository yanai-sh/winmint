# SetupComplete machine-phase module: remove the Edge browser like a normal app when
# DMA setup makes the supported uninstaller available. WebView2 / Edge runtime is
# preserved. We do NOT patch IntegratedServicesRegionPolicySet.
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
        normalUninstallAttempts = @()
        before = $null
        after = $null
    }

    if (-not $edgeRemove) {
        $result.action = if ($edgeKeep) {
            'skipped: Edge kept (-KeepEdge); WinMint still applies the Edge debloat policies'
        }
        else {
            'skipped: removal not requested'
        }
        Write-ScLog "Edge removal $($result.action)."
        $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $logDir 'SetupComplete_Edge.json') -Encoding UTF8
        return
    }

    function Get-ScEdgeBrowserProbe {
        $programFilesX86 = ${env:ProgramFiles(x86)}
        $edgePaths = @(
            if ($programFilesX86) { Join-Path $programFilesX86 'Microsoft\Edge\Application' }
            if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Microsoft\Edge\Application' }
        )
        $webViewPaths = @(
            if ($programFilesX86) { Join-Path $programFilesX86 'Microsoft\EdgeWebView\Application' }
            if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Microsoft\EdgeWebView\Application' }
        )
        [ordered]@{
            edgeApplicationPaths = @($edgePaths | ForEach-Object {
                    [ordered]@{ path = $_; exists = [bool](Test-Path -LiteralPath $_ -PathType Container) }
                })
            webView2ApplicationPaths = @($webViewPaths | ForEach-Object {
                    [ordered]@{ path = $_; exists = [bool](Test-Path -LiteralPath $_ -PathType Container) }
                })
            edgeStableAppx = @(Get-AppxPackage -AllUsers -Name 'Microsoft.MicrosoftEdge.Stable' -ErrorAction SilentlyContinue |
                Select-Object Name, PackageFullName, PackageUserInformation, NonRemovable, InstallLocation)
            edgeUninstallEntries = @(Get-ChildItem -LiteralPath @(
                        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
                    ) -ErrorAction SilentlyContinue |
                ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue } |
                Where-Object { [string]$_.DisplayName -eq 'Microsoft Edge' } |
                Select-Object DisplayName, DisplayVersion, UninstallString)
        }
    }

    function Get-ScEdgeSetupUninstallers {
        $setupPaths = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in @((Get-ScEdgeBrowserProbe).edgeUninstallEntries)) {
            $uninstall = [string]$entry.UninstallString
            if ($uninstall -match '"([^"]*\\setup\.exe)"' -or $uninstall -match '([A-Za-z]:\\\S*\\setup\.exe)') {
                $setupPaths.Add($Matches[1]) | Out-Null
            }
        }
        foreach ($root in @(
                if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application' }
                if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Microsoft\Edge\Application' }
            )) {
            if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root -PathType Container)) { continue }
            Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                ForEach-Object {
                    $candidate = Join-Path $_.FullName 'Installer\setup.exe'
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                        $setupPaths.Add($candidate) | Out-Null
                    }
                }
        }
        $setupPaths | Select-Object -Unique
    }

    function Invoke-ScEdgeNormalUninstall {
        foreach ($setup in @(Get-ScEdgeSetupUninstallers)) {
            try {
                Write-ScLog "Attempting supported Edge browser uninstall: $setup"
                $p = Start-Process -FilePath $setup -ArgumentList @('--uninstall', '--system-level', '--verbose-logging', '--force-uninstall') -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
                $result.normalUninstallAttempts += [ordered]@{ path = $setup; exitCode = [int]$p.ExitCode }
                $result.uninstallers += "$setup --uninstall --system-level --verbose-logging --force-uninstall"
                $result.exitCodes += [int]$p.ExitCode
                if ([int]$p.ExitCode -eq 0) { return $true }
            }
            catch {
                $result.normalUninstallAttempts += [ordered]@{ path = $setup; error = [string]$_.Exception.Message }
                $result.failed += [ordered]@{ target = $setup; error = [string]$_.Exception.Message }
            }
        }
        return $false
    }

    $result.before = Get-ScEdgeBrowserProbe
    $normalUninstallOk = Invoke-ScEdgeNormalUninstall
    $result.after = Get-ScEdgeBrowserProbe
    $edgePresentAfterNormal = [bool](@($result.after.edgeApplicationPaths | Where-Object { $_.exists }).Count)
    if ($normalUninstallOk -and -not $edgePresentAfterNormal) {
        $result.action = 'edge browser removed through the supported app uninstaller; WebView2 preserved.'
        Write-ScLog $result.action
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $logDir 'SetupComplete_Edge.json') -Encoding UTF8
        return
    }

    $result.action = if ($edgePresentAfterNormal) {
        'edge browser left installed: the supported app uninstaller did not remove it. Edge debloat policies applied; WebView2 preserved.'
    }
    else {
        'edge browser already absent; WebView2 preserved.'
    }
    Write-ScLog $result.action
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $logDir 'SetupComplete_Edge.json') -Encoding UTF8
}
