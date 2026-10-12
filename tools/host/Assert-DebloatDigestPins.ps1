#requires -Version 7.6
Set-StrictMode -Version Latest

<#
.SYNOPSIS
  Offline debloat digest pins from stages.json (S5 Host Apply + S4 Smoke).

.NOTES
  Online AppX remove phases stay S4-only (guest FirstLogon) — not asserted here.
#>

function Get-WinMintDebloatPinIdsFromStage {
    param(
        [Parameter(Mandatory)] $StagesDoc,
        [Parameter(Mandatory)] [string] $Opcode,
        [Parameter(Mandatory)] [string] $PathParam
    )
    $stage = @($StagesDoc.stages) |
        Where-Object { [string]$_.opcode -eq $Opcode } |
        Select-Object -First 1
    if ($null -eq $stage) { return @() }
    $path = [string]$stage.parameters.$PathParam
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return @()
    }
    return @(Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json)
}

function Get-WinMintDebloatPinsFromStages {
    param(
        [Parameter(Mandatory)]
        [string] $StagesPath
    )
    if (-not (Test-Path -LiteralPath $StagesPath -PathType Leaf)) {
        throw "stages.json missing: $StagesPath (Apply materialize required for keep-flag pins)"
    }
    try {
        $stagesDoc = Get-Content -LiteralPath $StagesPath -Raw -Encoding utf8 | ConvertFrom-Json
    }
    catch {
        throw "stages.json unreadable: $StagesPath ($($_.Exception.Message))"
    }

    [pscustomobject]@{
        PinnedRemoveAppx              = @(Get-WinMintDebloatPinIdsFromStage -StagesDoc $stagesDoc -Opcode 'RemoveProvisionedAppx' -PathParam 'packageFamilyNamesPath')
        PinnedRemoveCapabilities      = @(Get-WinMintDebloatPinIdsFromStage -StagesDoc $stagesDoc -Opcode 'RemoveCapabilities' -PathParam 'namesPath')
        PinnedDisableOptionalFeatures = @(Get-WinMintDebloatPinIdsFromStage -StagesDoc $stagesDoc -Opcode 'DisableOptionalFeatures' -PathParam 'namesPath')
    }
}

function Assert-WinMintPinnedRemoveDigests {
    param(
        [Parameter(Mandatory)]
        [hashtable] $DigestMap,

        [string[]] $PinnedRemoveAppx = @(),
        [string[]] $PinnedRemoveCapabilities = @(),
        [string[]] $PinnedDisableOptionalFeatures = @()
    )

    foreach ($row in @(
            @{ Prefix = 'removed.appx.'; Value = 'absent'; Ids = $PinnedRemoveAppx; Label = 'appx' }
            @{ Prefix = 'removed.capability.'; Value = 'Absent'; Ids = $PinnedRemoveCapabilities; Label = 'capability' }
            @{ Prefix = 'disabled.feature.'; Value = 'Disabled'; Ids = $PinnedDisableOptionalFeatures; Label = 'feature' }
        )) {
        if ($null -eq $row.Ids -or @($row.Ids).Count -eq 0) { continue }
        foreach ($id in @($row.Ids)) {
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            $key = "$($row.Prefix)$id"
            if (-not $DigestMap.ContainsKey($key) -or $DigestMap[$key] -ne $row.Value) {
                throw "keep-flag digest missing: expected $key=$($row.Value) in digests ($($row.Label))"
            }
        }
    }
}
