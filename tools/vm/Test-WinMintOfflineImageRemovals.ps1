#Requires -Version 7.6
<#
.SYNOPSIS
    Verify serviced install.wim offline removal expectations before VM boot.

.DESCRIPTION
    Mounts the built ISO's install.wim, checks provisioned AppX prefixes and
    removed capabilities against the build profile. Mirrors live guest drift semantics.
#>
[CmdletBinding()]
param(
    [string]$IsoPath,
    [string]$ProfilePath,
    [string]$BuildDir,
    [string]$OutputPath,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\runtime\image\WinMint.ps1')

function Invoke-WinMintOfflineDism {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [int[]]$SuccessCodes = @(0)
    )
    $oldPref = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $lines = [System.Collections.Generic.List[string]]::new()
        & dism.exe @Arguments 2>&1 | ForEach-Object { $lines.Add([string]$_) }
        $code = $LASTEXITCODE
        if ($SuccessCodes -notcontains $code) {
            throw "dism.exe failed (exit $code).`n  dism.exe $($Arguments -join ' ')`n$($lines -join "`n")"
        }
        return [pscustomobject]@{ ExitCode = $code; Output = $lines.ToArray() }
    }
    finally {
        $PSNativeCommandUseErrorActionPreference = $oldPref
    }
}

function Test-WinMintOfflineNameMatchesPrefix {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Prefix
    )
    return ($Name -like "*$Prefix*")
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if ($BuildDir) {
    $buildDirResolved = if ([IO.Path]::IsPathRooted($BuildDir)) { $BuildDir } else { Join-Path $repoRoot $BuildDir }
    if (-not $IsoPath) {
        $isoCandidate = Get-ChildItem -LiteralPath $buildDirResolved -Filter 'WinMint-*.iso' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($isoCandidate) { $IsoPath = $isoCandidate.FullName }
    }
    if (-not $ProfilePath) {
        foreach ($name in @('WinMint-BuildProfile.json', 'BuildProfile.json')) {
            $candidate = Join-Path $buildDirResolved $name
            if (Test-Path -LiteralPath $candidate) { $ProfilePath = $candidate; break }
        }
    }
}

if (-not $IsoPath -or -not (Test-Path -LiteralPath $IsoPath)) {
    throw 'Specify -IsoPath or -BuildDir containing a WinMint-*.iso.'
}
if (-not $ProfilePath -or -not (Test-Path -LiteralPath $ProfilePath)) {
    throw 'Specify -ProfilePath or -BuildDir containing WinMint-BuildProfile.json.'
}

$profile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
$keepBlock = Get-WinMintProfileKeepBlock -BuildProfile $profile
$expectedPrefixes = @(Get-WinMintProfileAppxRemovalPrefixFromKeep -Keep $keepBlock | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
$expectedRemovedCapabilities = @('Media.WindowsMediaPlayer', 'Microsoft.Wallpapers.Extended')

$mountDir = Join-Path $env:TEMP ("winmint-offline-wim-" + [Guid]::NewGuid().ToString('n'))
$wimMountDir = $mountDir
$isoMount = $null
$wimMounted = $false

try {
    $isoMount = Mount-DiskImage -ImagePath $IsoPath -Access ReadOnly -PassThru -ErrorAction Stop
    $volume = $isoMount | Get-Volume -ErrorAction Stop | Select-Object -First 1
    if (-not $volume -or -not $volume.DriveLetter) { throw "Could not mount ISO: $IsoPath" }
    $installWim = Join-Path "$($volume.DriveLetter):" 'sources\install.wim'
    if (-not (Test-Path -LiteralPath $installWim)) {
        $installWim = Join-Path "$($volume.DriveLetter):" 'sources\install.esd'
    }
    if (-not (Test-Path -LiteralPath $installWim)) {
        throw "No install.wim or install.esd found on ISO: $IsoPath"
    }

    $edition = [string]$profile.target.edition
    $image = Get-WindowsImage -ImagePath $installWim -ErrorAction Stop |
        Where-Object { [string]$_.ImageName -eq $edition } |
        Select-Object -First 1
    if (-not $image) {
        $image = Get-WindowsImage -ImagePath $installWim -ErrorAction Stop | Select-Object -First 1
    }
    if (-not $image) { throw "No WIM index found in $installWim" }

    $null = New-Item -ItemType Directory -Path $wimMountDir -Force
    # ponytail: ISO-backed WIM is read-only; /ReadOnly is enough for provisioned/capability queries.
    Invoke-WinMintOfflineDism -Arguments @(
        '/English', '/Mount-Image', "/ImageFile:$installWim", "/Index:$($image.ImageIndex)", "/MountDir:$wimMountDir", '/ReadOnly'
    ) | Out-Null
    $wimMounted = $true

    $driftProvisioned = [System.Collections.Generic.List[object]]::new()
    $capabilityDrift = [System.Collections.Generic.List[object]]::new()

    $list = Invoke-WinMintOfflineDism -Arguments @('/English', "/Image:$wimMountDir", '/Get-ProvisionedAppxPackages')
    $packages = @($list.Output | ForEach-Object { if ("$_" -match 'PackageName : (.*)') { $matches[1].Trim() } })

    foreach ($prefix in $expectedPrefixes) {
        foreach ($pkg in @($packages | Where-Object { Test-WinMintOfflineNameMatchesPrefix -Name $_ -Prefix $prefix })) {
            $driftProvisioned.Add([ordered]@{
                    prefix = [string]$prefix
                    packageName = [string]$pkg
                }) | Out-Null
        }
    }

    $capList = Invoke-WinMintOfflineDism -Arguments @('/English', "/Image:$wimMountDir", '/Get-Capabilities')
    $capabilityDrift.Clear()
    $block = @()
    foreach ($line in @($capList.Output)) {
        if ($line -match 'Capability Identity : (.+)') {
            if ($block.Count -gt 0) {
                $identity = ($block | Where-Object { $_ -match 'Capability Identity : (.+)' } | ForEach-Object { $matches[1].Trim() } | Select-Object -First 1)
                $state = ($block | Where-Object { $_ -match 'State : (.+)' } | ForEach-Object { $matches[1].Trim() } | Select-Object -First 1)
                foreach ($capToken in $expectedRemovedCapabilities) {
                    if ($identity -like "*$capToken*" -and $state -eq 'Installed') {
                        $capabilityDrift.Add([ordered]@{ token = $capToken; name = $identity; state = $state }) | Out-Null
                    }
                }
            }
            $block = @($line)
        }
        elseif ($block.Count -gt 0) {
            $block += $line
        }
    }
    if ($block.Count -gt 0) {
        $identity = ($block | Where-Object { $_ -match 'Capability Identity : (.+)' } | ForEach-Object { $matches[1].Trim() } | Select-Object -First 1)
        $state = ($block | Where-Object { $_ -match 'State : (.+)' } | ForEach-Object { $matches[1].Trim() } | Select-Object -First 1)
        foreach ($capToken in $expectedRemovedCapabilities) {
            if ($identity -like "*$capToken*" -and $state -eq 'Installed') {
                $capabilityDrift.Add([ordered]@{ token = $capToken; name = $identity; state = $state }) | Out-Null
            }
        }
    }

    $ok = ($driftProvisioned.Count -eq 0) -and ($capabilityDrift.Count -eq 0)
    $result = [ordered]@{
        ok = [bool]$ok
        isoPath = $IsoPath
        profilePath = $ProfilePath
        imageIndex = [int]$image.ImageIndex
        imageName = [string]$image.ImageName
        driftProvisioned = @($driftProvisioned.ToArray())
        capabilityDrift = @($capabilityDrift.ToArray())
    }

    if ($OutputPath) {
        $outDir = Split-Path -Parent $OutputPath
        if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
            $null = New-Item -ItemType Directory -Path $outDir -Force
        }
        ($result | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    }

    if ($AsJson) {
        $result | ConvertTo-Json -Depth 6
    }
    elseif (-not $ok) {
        Write-Host "Offline removal drift detected (provisioned=$($driftProvisioned.Count), capabilities=$($capabilityDrift.Count))." -ForegroundColor Red
    }
    else {
        Write-Host 'Offline WIM removal verification passed.'
    }

    if (-not $ok) { exit 1 }
}
finally {
    if ($wimMounted) {
        try { Invoke-WinMintOfflineDism -Arguments @('/English', '/Unmount-Image', "/MountDir:$wimMountDir", '/Discard') | Out-Null }
        catch { Write-Warning "WIM unmount failed: $($_.Exception.Message)" }
    }
    if ($isoMount) {
        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
    }
    if (Test-Path -LiteralPath $wimMountDir) { Remove-Item -LiteralPath $wimMountDir -Recurse -Force -ErrorAction SilentlyContinue }
}
