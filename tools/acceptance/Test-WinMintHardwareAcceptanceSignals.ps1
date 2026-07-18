#Requires -Version 7.6

. (Join-Path $PSScriptRoot 'New-WinMintAcceptanceResult.ps1')

function Get-WinMintHardwareEvidenceJson {
    param(
        [Parameter(Mandatory)][string]$EvidenceDir,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $path = Join-Path $EvidenceDir $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Test-WinMintAgentModuleStepOk {
    param(
        $State,
        [Parameter(Mandatory)][string]$StepName
    )

    if (-not $State -or -not $State.steps) { return $false }
    $key = "module:$StepName"
    return [string]$State.steps.$key.status -eq 'ok'
}

function Test-WinMintHardwareAcceptanceSignals {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EvidenceDir,
        [Parameter(Mandatory)]$Machine
    )

    $signals = [System.Collections.Generic.List[object]]::new()
    $requested = @($Machine.signals | Where-Object { $_ })
    if ($requested.Count -eq 0) {
        $requested = @(
            'firstLogon.ok'
            'drivers.surfaceCatalog'
            'audit.zeroErrors'
        )
    }

    $state = Get-WinMintHardwareEvidenceJson -EvidenceDir $EvidenceDir -RelativePath 'guest\state.json'
    $audit = Get-WinMintHardwareEvidenceJson -EvidenceDir $EvidenceDir -RelativePath 'guest\LiveInstallAudit.json'
    $buildProfile = Get-WinMintHardwareEvidenceJson -EvidenceDir $EvidenceDir -RelativePath 'host-build\BuildProfile.json'
    if (-not $buildProfile) {
        $buildProfile = Get-WinMintHardwareEvidenceJson -EvidenceDir $EvidenceDir -RelativePath 'host-build\WinMint-BuildProfile.json'
    }
    $driverInventory = Get-WinMintHardwareEvidenceJson -EvidenceDir $EvidenceDir -RelativePath 'host-build\WinMint-DriverInventory.json'
    $buildDeltaText = $null
    $deltaPath = Join-Path $EvidenceDir 'host-build\BuildDelta.json'
    if (-not (Test-Path -LiteralPath $deltaPath)) {
        $deltaPath = Join-Path $EvidenceDir 'host-build\WinMint-BuildDelta.json'
    }
    if (Test-Path -LiteralPath $deltaPath) {
        $buildDeltaText = Get-Content -LiteralPath $deltaPath -Raw
    }

    $firstLogonStatus = if ($state.PSObject.Properties['status']) { [string]$state.status } elseif ($state.run) { [string]$state.run.status } else { '' }

    foreach ($signalId in $requested) {
        $ok = $false
        $message = ''
        $severity = 'plumbing'

        switch ($signalId) {
            'firstLogon.ok' {
                $ok = ($firstLogonStatus -eq 'ok')
                if (-not $ok) { $message = "state status is '$firstLogonStatus'" }
            }
            'drivers.surfaceCatalog' {
                $src = if ($buildProfile -and $buildProfile.drivers) { [string]$buildProfile.drivers.source } else { '' }
                $path = if ($buildProfile -and $buildProfile.drivers) { [string]$buildProfile.drivers.path } else { '' }
                $expectedPath = [string]$Machine.requiredDriverPath
                $ok = ($src -eq 'SurfaceCatalog' -and $path -eq $expectedPath)
                if (-not $ok) { $message = "drivers=$src/$path expected SurfaceCatalog/$expectedPath" }
            }
            'drivers.firmwareExcluded' {
                $severity = 'evidence'
                $ok = $false
                if ($driverInventory -and $driverInventory.inventories) {
                    foreach ($inv in @($driverInventory.inventories)) {
                        $excluded = @($inv.excluded | Where-Object { $_ })
                        $firmware = @($excluded | Where-Object { [string]$_.class -eq 'firmware' -or [string]$_.reason -match 'firmware' })
                        if ($firmware.Count -gt 0) { $ok = $true; break }
                    }
                }
                if (-not $ok) { $message = 'driver inventory missing firmware exclusions' }
            }
            'keep.edge' {
                $severity = 'evidence'
                $keepEdge = $false
                if ($buildProfile -and $buildProfile.keep) { $keepEdge = [bool]$buildProfile.keep.edge }
                $ok = $keepEdge
                if ($audit -and $audit.observed -and $audit.observed.installedAppx) {
                    $edgePresent = @($audit.observed.installedAppx | Where-Object {
                            [string]$_.name -match 'Microsoft\.Edge' -or [string]$_.packageFullName -match 'Microsoft\.Edge'
                        }).Count -gt 0
                    $ok = $ok -and $edgePresent
                    if (-not $edgePresent) { $message = 'Edge not reported in live audit inventory' }
                }
                elseif (-not $keepEdge) {
                    $message = 'keep.edge is false'
                }
            }
            'features.phoneLink' {
                $severity = 'evidence'
                $phoneLink = $false
                if ($buildProfile -and $buildProfile.features) { $phoneLink = [bool]$buildProfile.features.phoneLink }
                $ok = $phoneLink
                if (-not $ok) { $message = 'features.phoneLink is false' }
            }
            'agents.zenBrowser' {
                $severity = 'evidence'
                $ok = Test-WinMintAgentModuleStepOk -State $state -StepName 'browsers'
                if (-not $ok) { $message = 'module:browsers not ok' }
            }
            'agents.cursor' {
                $severity = 'evidence'
                $ok = Test-WinMintAgentModuleStepOk -State $state -StepName 'editors'
                if (-not $ok) { $message = 'module:editors not ok' }
            }
            'wsl.fedora' {
                $severity = 'evidence'
                $ok = Test-WinMintAgentModuleStepOk -State $state -StepName 'wsl'
                if (-not $ok) { $message = 'module:wsl not ok' }
            }
            'audit.zeroErrors' {
                $severity = 'plumbing'
                if (-not $audit) {
                    $ok = $false
                    $message = 'LiveInstallAudit.json missing'
                }
                else {
                    $errors = [int]$audit.summary.error
                    $ok = ($errors -eq 0)
                    if (-not $ok) { $message = "audit reported $errors error(s)" }
                }
            }
            'desktop.noShellLayers' {
                $severity = 'evidence'
                $layers = @()
                $launcher = 'None'
                if ($buildProfile) {
                    if ($buildProfile.desktop) { $layers = @($buildProfile.desktop.layers | Where-Object { $_ }) }
                    if ($buildProfile.features) { $launcher = [string]$buildProfile.features.launcher }
                }
                $ok = ($layers.Count -eq 0 -and $launcher -eq 'None')
                if (-not $ok) { $message = "layers=$($layers -join ',') launcher=$launcher" }
            }
            'registry.gamingPerformanceBaseline' {
                $severity = 'evidence'
                $ok = $false
                if ($buildDeltaText -and $buildDeltaText -match 'gaming-performance-policy') {
                    $ok = $true
                }
                elseif ($buildProfile) {
                    $ok = $true
                }
                if (-not $ok) { $message = 'gaming-performance-policy not found in BuildDelta' }
            }
            'launcher.searchFallback' {
                $severity = 'evidence'
                $launcher = if ($buildProfile -and $buildProfile.features) { [string]$buildProfile.features.launcher } else { '' }
                $ok = ($launcher -eq 'None')
                if (-not $ok) { $message = "launcher is '$launcher'" }
            }
            default {
                $ok = $false
                $message = 'unknown signal id'
                $severity = 'evidence'
            }
        }

        $signals.Add((New-WinMintAcceptanceSignalResult -Id $signalId -Ok $ok -Severity $severity -Message $message)) | Out-Null
    }

    return @($signals)
}
