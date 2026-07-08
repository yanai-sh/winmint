#Requires -Version 7.6
<#
.SYNOPSIS
    Classify live guest AppX/capability state against WinMint removal expectations.

.DESCRIPTION
    Read-only guest probe for VM acceptance. Fails removable drift; records
    System/NonRemovable catalog matches as expected system remnants.
#>
[CmdletBinding()]
param(
    [Parameter()][AllowEmptyCollection()][string[]]$ExpectedPrefixes,
    [AllowEmptyCollection()][string[]]$RehydratedPrefixes = @('Microsoft.Edge.GameAssist'),
    [AllowEmptyCollection()][string[]]$ExpectedRemovedCapabilities = @(
        'Media.WindowsMediaPlayer'
        'Microsoft.Wallpapers.Extended'
    ),
    [string]$ConfigJson,
    [string]$ConfigPath,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'

if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "ConfigPath not found: $ConfigPath" }
    $ConfigJson = Get-Content -LiteralPath $ConfigPath -Raw
}
if (-not [string]::IsNullOrWhiteSpace($ConfigJson)) {
    $cfg = $ConfigJson | ConvertFrom-Json
    $ExpectedPrefixes = @($cfg.ExpectedPrefixes)
    if ($cfg.PSObject.Properties['RehydratedPrefixes']) { $RehydratedPrefixes = @($cfg.RehydratedPrefixes) }
    if ($cfg.PSObject.Properties['ExpectedRemovedCapabilities']) { $ExpectedRemovedCapabilities = @($cfg.ExpectedRemovedCapabilities) }
    if ($cfg.PSObject.Properties['AsJson'] -and [bool]$cfg.AsJson) { $AsJson = $true }
}
elseif (-not $PSBoundParameters.ContainsKey('ExpectedPrefixes')) {
    throw 'ExpectedPrefixes or ConfigJson is required.'
}

function Test-WinMintNameMatchesPrefix {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Prefix
    )
    return ($Name -like "*$Prefix*")
}

function Test-WinMintPackageIsSystemLocked {
    param([Parameter(Mandatory)]$Package)
    return ([bool]$Package.NonRemovable -or [string]$Package.SignatureKind -eq 'System')
}

$driftInstalled = [System.Collections.Generic.List[object]]::new()
$driftProvisioned = [System.Collections.Generic.List[object]]::new()
$systemRemnants = [System.Collections.Generic.List[object]]::new()
$rehydratedPresent = [System.Collections.Generic.List[object]]::new()
$capabilityDrift = [System.Collections.Generic.List[object]]::new()

$installedAppx = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
$provisionedAppx = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)

foreach ($prefix in @($ExpectedPrefixes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
    $rehydrated = @($RehydratedPrefixes) -contains $prefix
    foreach ($pkg in @($installedAppx | Where-Object {
            (Test-WinMintNameMatchesPrefix -Name ([string]$_.Name) -Prefix $prefix) -or
            (Test-WinMintNameMatchesPrefix -Name ([string]$_.PackageFullName) -Prefix $prefix)
        })) {
        if (Test-WinMintPackageIsSystemLocked -Package $pkg) {
            $systemRemnants.Add([ordered]@{
                    prefix = [string]$prefix
                    name   = [string]$pkg.Name
                    kind   = 'installed'
                    reason = 'SystemNonRemovable'
                }) | Out-Null
            continue
        }
        if ($rehydrated) {
            $rehydratedPresent.Add([ordered]@{
                    prefix = [string]$prefix
                    name   = [string]$pkg.Name
                    kind   = 'installed'
                }) | Out-Null
            continue
        }
        $driftInstalled.Add([ordered]@{
                prefix          = [string]$prefix
                name            = [string]$pkg.Name
                packageFullName = [string]$pkg.PackageFullName
            }) | Out-Null
    }

    foreach ($pkg in @($provisionedAppx | Where-Object {
            (Test-WinMintNameMatchesPrefix -Name ([string]$_.DisplayName) -Prefix $prefix) -or
            (Test-WinMintNameMatchesPrefix -Name ([string]$_.PackageName) -Prefix $prefix)
        })) {
        $driftProvisioned.Add([ordered]@{
                prefix      = [string]$prefix
                displayName = [string]$pkg.DisplayName
                packageName = [string]$pkg.PackageName
            }) | Out-Null
    }
}

foreach ($capToken in @($ExpectedRemovedCapabilities | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
    $cap = Get-WindowsCapability -Online -ErrorAction SilentlyContinue |
        Where-Object { [string]$_.Name -like "*$capToken*" -and [string]$_.State -eq 'Installed' } |
        Select-Object -First 1
    if ($cap) {
        $capabilityDrift.Add([ordered]@{
                token = [string]$capToken
                name  = [string]$cap.Name
                state = [string]$cap.State
            }) | Out-Null
    }
}

$ok = ($driftInstalled.Count -eq 0) -and ($driftProvisioned.Count -eq 0) -and ($capabilityDrift.Count -eq 0)
$result = [ordered]@{
    ok               = [bool]$ok
    driftInstalled   = @($driftInstalled.ToArray())
    driftProvisioned = @($driftProvisioned.ToArray())
    systemRemnants   = @($systemRemnants.ToArray())
    rehydratedPresent = @($rehydratedPresent.ToArray())
    capabilityDrift  = @($capabilityDrift.ToArray())
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 6
}
else {
    $result
}
