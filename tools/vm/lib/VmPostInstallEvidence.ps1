#Requires -Version 7.6

function Get-WinMintVmPulledAgentState {
    param([Parameter(Mandatory)][string]$EvidenceDir)

    foreach ($rel in @(
            'LocalAppData-WinMint\state.json',
            'guest\state.json',
            'state.json'
        )) {
        $path = Join-Path $EvidenceDir $rel
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            try {
                return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            }
            catch {
                return $null
            }
        }
    }
    return $null
}

function Test-WinMintVmFirstLogonRequiredSteps {
    <#
    .SYNOPSIS
    Smoke plumbing: baseline agent module keys must exist and not be failed.
    Allowed statuses: ok, skipped (optional modules / smoke WSL skip).
    #>
    param(
        [Parameter(Mandatory)]$AgentState,
        [string[]]$RequiredStepKeys = @(
            'module:profiles',
            'module:package-managers',
            'module:wsl',
            'module:launcher-key'
        )
    )

    $failures = [System.Collections.Generic.List[string]]::new()
    $meta = [ordered]@{
        checkedKeys = @($RequiredStepKeys)
        observed    = [ordered]@{}
    }

    if (-not $AgentState -or -not $AgentState.steps) {
        $failures.Add('agent state.json steps missing') | Out-Null
        return [pscustomobject]@{
            plumbingOk       = $false
            plumbingFailures = @($failures)
            meta             = $meta
        }
    }

    $steps = $AgentState.steps
    foreach ($key in $RequiredStepKeys) {
        $step = $null
        if ($steps -is [System.Collections.IDictionary]) {
            if ($steps.Contains($key)) { $step = $steps[$key] }
        }
        elseif ($steps.PSObject.Properties[$key]) {
            $step = $steps.$key
        }

        $status = if ($step -and $step.PSObject.Properties['status']) { [string]$step.status } else { '' }
        $meta.observed[$key] = $status
        if ([string]::IsNullOrWhiteSpace($status)) {
            $failures.Add("required step missing: $key") | Out-Null
        }
        elseif ($status -eq 'failed') {
            $failures.Add("required step failed: $key") | Out-Null
        }
        elseif ($status -notin @('ok', 'skipped')) {
            $failures.Add("required step '$key' status '$status' (expected ok|skipped)") | Out-Null
        }
    }

    [pscustomobject]@{
        plumbingOk       = ($failures.Count -eq 0)
        plumbingFailures = @($failures)
        meta             = $meta
    }
}

function Get-WinMintVmDiskLayoutProbeScript {
    @'
$ErrorActionPreference = 'Stop'
$vols = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object {
        $_.DriveType -eq 'Fixed' -and $_.FileSystemLabel
    } | ForEach-Object {
        [ordered]@{
            letter = $(if ($_.DriveLetter -and $_.DriveLetter -ne ([char]0)) { [string]$_.DriveLetter } else { '' })
            label  = [string]$_.FileSystemLabel
            fs     = [string]$_.FileSystemType
            sizeGb = [math]::Round(([double]$_.Size / 1GB), 1)
        }
    })
$win = @($vols | Where-Object { $_.letter -eq 'C' } | Select-Object -First 1)
$winre = @($vols | Where-Object { $_.label -match '^(?i)WinRE$' } | Select-Object -First 1)
$dev = @($vols | Where-Object { $_.label -match '^(?i)DevDrive$' } | Select-Object -First 1)
$vhdPath = Join-Path (Join-Path $env:SystemDrive 'DevDrives') 'WinMint.vhdx'
[ordered]@{
    windowsPresent = ($null -ne $win)
    winrePresent   = ($null -ne $winre)
    devDriveLabel  = ($null -ne $dev)
    devDriveLetter = $(if ($dev) { [string]$dev.letter } else { '' })
    vhdPresent     = (Test-Path -LiteralPath $vhdPath)
    volumes        = $vols
} | ConvertTo-Json -Depth 6 -Compress
'@
}

function Test-WinMintVmDiskLayoutEvidence {
    param(
        [Parameter(Mandatory)]$Probe,
        [Parameter(Mandatory)][string]$DiskMode,
        [string]$DevDriveMode = 'Off'
    )

    $failures = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $meta = [ordered]@{
        diskMode     = $DiskMode
        devDriveMode = $DevDriveMode
        probe        = $Probe
    }

    if (-not $Probe) {
        $warnings.Add('disk layout probe unavailable') | Out-Null
        return [pscustomobject]@{
            plumbingOk       = $true
            plumbingFailures = @()
            softWarnings     = @($warnings)
            meta             = $meta
        }
    }

    if ($DiskMode -eq 'AutoWipeDisk0') {
        if (-not [bool]$Probe.windowsPresent) {
            $failures.Add('AutoWipeDisk0 guest missing Windows volume (C:)') | Out-Null
        }
        # WinRE may be hidden (no letter); treat missing label as warning only.
        if (-not [bool]$Probe.winrePresent) {
            $warnings.Add('WinRE labeled volume not visible (may be hidden)') | Out-Null
        }
    }

    if ($DevDriveMode -eq 'Partition') {
        if (-not [bool]$Probe.devDriveLabel) {
            $failures.Add('Partition Dev Drive label DevDrive not found') | Out-Null
        }
    }
    elseif ($DevDriveMode -eq 'VhdDynamic') {
        if (-not [bool]$Probe.vhdPresent -and -not [bool]$Probe.devDriveLabel) {
            $failures.Add('VhdDynamic Dev Drive VHDX/label not found') | Out-Null
        }
    }
    elseif ($DevDriveMode -eq 'Off' -or [string]::IsNullOrWhiteSpace($DevDriveMode)) {
        if ([bool]$Probe.devDriveLabel -or [bool]$Probe.vhdPresent) {
            $warnings.Add('Dev Drive volume present while profile mode is Off') | Out-Null
        }
    }

    [pscustomobject]@{
        plumbingOk       = ($failures.Count -eq 0)
        plumbingFailures = @($failures)
        softWarnings     = @($warnings)
        meta             = $meta
    }
}
