#Requires -Version 7.3
<#
.SYNOPSIS
  Elevated deep audit: boot layout, WIMs, autounattend, manifest/profile, optional machine-profile gates.
.DESCRIPTION
  Defaults to newest output\*.iso. Use -MachineProfilePath with JSON under scripts\audit\MachineProfiles\ to assert
  arch, Home edition index, manifest driver mode, and EFI layout for YOUR install target. -EmitMachineProfileTemplate
  prints a starter JSON from this PC's WMI (no admin). -AssertHostMatchesMachineProfile requires SMBIOS model match.
.EXAMPLE
  pwsh -NoProfile -File .\scripts\audit\Audit-OutputIso.ps1 -MachineProfilePath .\scripts\audit\MachineProfiles\surface-laptop-7-home.json -VerifyInstallImageDrivers -SaveReport .\output\iso-audit.txt
.EXAMPLE
  pwsh -NoProfile -File .\scripts\audit\Audit-OutputIso.ps1 -EmitMachineProfileTemplate
#>
param(
    [string]$RepositoryRoot = '',
    [string]$IsoPath = '',
    [string]$ManifestPath = '',
    [string]$ProfilePath = '',
    [switch]$SkipContracts,
    [int]$InstallWimImageIndex = 1,
    [switch]$SkipHash,
    [switch]$VerifyInstallImageDrivers,
    [string]$SaveReport = '',
    [switch]$Json,
    [string]$MachineProfilePath = '',
    [switch]$AssertHostMatchesMachineProfile,
    [switch]$ForceScriptInstallWimIndex,
    [switch]$EmitMachineProfileTemplate
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($EmitMachineProfileTemplate) {
    $sys = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $model = if ($sys) { [string]$sys.Model.Trim() } else { '' }
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } elseif ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { 'amd64' } else { 'unknown' }
    $efiRel = if ($arch -eq 'arm64') { 'efi\boot\bootaa64.efi' } else { 'efi\boot\bootx64.efi' }
    $needle = if ($model.Length -gt 64) { $model.Substring(0, 64).Trim() } else { $model }
    $tpl = [ordered]@{
        schemaVersion                           = 2
        friendlyName                            = "$(if ($model) { $model } else { 'This PC' }) — edit me"
        optionalSystemModelContains             = $needle
        processorArchitecture                   = $arch
        firmware                                = 'UEFI'
        installWimImageIndex                    = 1
        expectedInstallImageName                = 'Windows 11 Home'
        expectedInstallImageNameMustNotContain  = @('Single Language')
        requireManifestDriverSource             = 'Custom'
        minimumManifestInjectedInfs             = 1
        requireEfiLoaderPath                    = $efiRel
        notes                                   = 'Save as JSON and pass -MachineProfilePath. Use -AssertHostMatchesMachineProfile when running on the install target.'
    }
    Write-Output ([pscustomobject]$tpl | ConvertTo-Json -Depth 6)
    exit 0
}

$script:AuditFindings = [System.Collections.Generic.List[object]]::new()
$script:AuditLines = [System.Collections.Generic.List[string]]::new()
$script:AuditJsonOutput = [bool]$Json
$supportPath = Join-Path $PSScriptRoot 'Private\Audit-OutputIsoSupport.ps1'
if (-not (Test-Path -LiteralPath $supportPath)) {
    throw "Missing dependency script: $supportPath"
}
. $supportPath
$machineProfileScript = Join-Path $PSScriptRoot 'Private\Audit-MachineProfile.ps1'
if (-not (Test-Path -LiteralPath $machineProfileScript)) {
    throw "Missing dependency script: $machineProfileScript"
}
. $machineProfileScript

if (-not (Test-WinWSElevation)) {
    Write-Error 'Run from an elevated PowerShell (Administrator). DISM queries and optional WIM mounts require elevation.'
    exit 2
}

$repo = Resolve-WinWSRepositoryRoot -Candidate $RepositoryRoot
$outDir = Join-Path $repo 'output'

if ([string]::IsNullOrWhiteSpace($IsoPath)) {
    $isoItem = Get-WinWSNewestOutputIso -OutDir $outDir
    if (-not $isoItem) {
        Write-Error "No .iso under '$outDir'. Use -IsoPath."
        exit 3
    }
    $IsoPath = $isoItem.FullName
}
else {
    if (-not (Test-Path -LiteralPath $IsoPath)) {
        Write-Error "ISO not found: $IsoPath"
        exit 3
    }
    $IsoPath = (Resolve-Path -LiteralPath $IsoPath).Path
}

if ($SkipContracts) {
    $ManifestPath = ''
    $ProfilePath = ''
}

if (-not $SkipContracts -and [string]::IsNullOrWhiteSpace($ManifestPath)) {
    $defaultManifest = Join-Path $outDir 'WinWS-BuildManifest.json'
    $isoUnderOutput = $false
    try {
        $isoFull = [IO.Path]::GetFullPath($IsoPath)
        $outFull = [IO.Path]::GetFullPath($outDir)
        $trimOut = $outFull.TrimEnd([IO.Path]::DirectorySeparatorChar)
        $isoUnderOutput = $isoFull.StartsWith($trimOut + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
            $isoFull.Equals($outFull, [StringComparison]::OrdinalIgnoreCase)
    }
    catch { }
    if ($isoUnderOutput -and (Test-Path -LiteralPath $defaultManifest)) {
        $ManifestPath = $defaultManifest
    }
}
elseif (-not $SkipContracts -and -not (Test-Path -LiteralPath $ManifestPath)) {
    Write-Error "Manifest not found: $ManifestPath"
    exit 4
}
else {
    $ManifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path
}

if (-not $SkipContracts -and [string]::IsNullOrWhiteSpace($ProfilePath)) {
    $cand = Join-Path $outDir 'WinWS-BuildProfile.json'
    if ((Test-Path -LiteralPath $cand)) {
        $ProfilePath = $cand
    }
}
elseif (-not $SkipContracts -and -not (Test-Path -LiteralPath $ProfilePath)) {
    Write-Error "Profile not found: $ProfilePath"
    exit 4
}
else {
    $ProfilePath = (Resolve-Path -LiteralPath $ProfilePath).Path
}

Import-Module Dism -ErrorAction Stop
Import-Module Storage -ErrorAction Stop

$machineProfile = $null
if (-not [string]::IsNullOrWhiteSpace($MachineProfilePath)) {
    if (-not (Test-Path -LiteralPath $MachineProfilePath)) {
        Write-Error "Machine profile not found: $MachineProfilePath"
        exit 4
    }
    $MachineProfilePath = (Resolve-Path -LiteralPath $MachineProfilePath).Path
    $machineProfile = Get-Content -LiteralPath $MachineProfilePath -Raw | ConvertFrom-Json
}

$wimIndexForAudit = [int]$InstallWimImageIndex
if ($machineProfile -and $machineProfile.PSObject.Properties['installWimImageIndex'] -and -not $ForceScriptInstallWimIndex) {
    $wimIndexForAudit = [int]$machineProfile.installWimImageIndex
}

$isoItem = Get-Item -LiteralPath $IsoPath
$manifest = $null
$profile = $null
if ($ManifestPath) {
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
}
if ($ProfilePath) {
    $profile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
}

$sha256 = $null
if (-not $SkipHash) {
    Add-AuditLine 'Computing SHA256 (omit with -SkipHash for a faster pass)…'
    $sha256 = (Get-FileHash -LiteralPath $IsoPath -Algorithm SHA256).Hash
}

$audit = [ordered]@{
    host              = [ordered]@{
        computerName = $env:COMPUTERNAME
        os           = [System.Environment]::OSVersion.VersionString
        psVersion    = $PSVersionTable.PSVersion.ToString()
        elevated     = $true
    }
    isoPath           = $IsoPath
    fileSizeBytes     = [int64]$isoItem.Length
    fileLastWriteUtc  = $isoItem.LastWriteTimeUtc.ToString('o')
    iso9660VolumeId   = [string](Get-Iso9660PrimaryVolumeId -LiteralIsoPath $IsoPath)
    sha256            = [string]$sha256
    manifestPath      = [string]$ManifestPath
    profilePath       = [string]$ProfilePath
    manifestMatch     = [ordered]@{}
    mountedRoot       = ''
    installImagePath  = ''
    installImages     = @()
    installArch       = ''
    bootWimImages      = @()
    autounattend      = [ordered]@{}
    manifestSummary   = [ordered]@{}
    profileSummary    = [ordered]@{}
    surfaceLaptop7    = [ordered]@{}
    offlineDrivers       = $null
    machineProfilePath   = [string]$MachineProfilePath
    targetInstallWimIndex = $wimIndexForAudit
    findings             = @()
}

Add-AuditLine '======== WinWS output ISO — full audit ========'
Add-AuditLine ("Host: {0} | OS: {1} | PS: {2}" -f $audit.host.computerName, $audit.host.os, $audit.host.psVersion)
Add-AuditLine ("ISO: {0}" -f $IsoPath)
Add-AuditLine ("Size: {0:N0} bytes | Modified UTC: {1}" -f $isoItem.Length, $audit.fileLastWriteUtc)
if ($audit.iso9660VolumeId) {
    Add-AuditLine ("ISO 9660 volume id: {0}" -f $audit.iso9660VolumeId)
}
if ($sha256) {
    Add-AuditLine ("SHA256: {0}" -f $sha256)
}

if ($manifest -and $manifest.PSObject.Properties['output']) {
    $mo = $manifest.output
    $audit.manifestMatch.declaredSha256 = [string]$mo.sha256
    $audit.manifestMatch.declaredSizeBytes = [int64]$mo.sizeBytes
    $audit.manifestMatch.sha256Ok = ($sha256 -and ($sha256 -eq $mo.sha256))
    $audit.manifestMatch.sizeOk = ([int64]$isoItem.Length -eq [int64]$mo.sizeBytes)
    Add-AuditLine ('--- Manifest output.* vs file ---')
    Add-AuditFinding -Severity $(if ($audit.manifestMatch.sha256Ok) { 'Info' } else { 'Warning' }) -Section 'Manifest' `
        -Message ("SHA256 match: {0}" -f $audit.manifestMatch.sha256Ok)
    Add-AuditFinding -Severity $(if ($audit.manifestMatch.sizeOk) { 'Info' } else { 'Warning' }) -Section 'Manifest' `
        -Message ("Size match: {0}" -f $audit.manifestMatch.sizeOk)
}

$mount = $null
try {
    $mount = Mount-DiskImage -ImagePath $IsoPath -Access ReadOnly -NoDriveLetter -PassThru -ErrorAction Stop
    $volume = $mount | Get-Volume -ErrorAction Stop | Select-Object -First 1
    if (-not $volume) { throw 'No volume after ISO mount.' }
    $root = if ($volume.DriveLetter) { "$($volume.DriveLetter):\" } elseif ($volume.Path) { [string]$volume.Path } else { throw 'No drive letter or volume path.' }
    $audit.mountedRoot = $root

    Add-AuditLine ''
    Add-AuditLine '--- Boot & layout (WinWS / oscdimg expectations) ---'
    $sectionLayout = 'Layout'
    Test-AuditPath -Root $root -RelativePath 'setup.exe' -Section $sectionLayout | Out-Null
    Test-AuditPath -Root $root -RelativePath 'autounattend.xml' -Section $sectionLayout | Out-Null
    Test-AuditPath -Root $root -RelativePath 'bootmgr.efi' -Section $sectionLayout | Out-Null
    Test-AuditPath -Root $root -RelativePath 'boot\boot.sdi' -Section $sectionLayout | Out-Null

    $wim = Join-Path $root 'sources\install.wim'
    $esd = Join-Path $root 'sources\install.esd'
    if (Test-Path -LiteralPath $wim) {
        $audit.installImagePath = $wim
    }
    elseif (Test-Path -LiteralPath $esd) {
        $audit.installImagePath = $esd
    }
    else {
        Add-AuditFinding -Severity Error -Section $sectionLayout -Message 'Missing sources\install.wim and install.esd'
    }

    $efiLoaderRel = $null
    if ($manifest -and $manifest.source.architecture) {
        $efiLoaderRel = switch ([string]$manifest.source.architecture) {
            'arm64' { 'efi\boot\bootaa64.efi' }
            'amd64' { 'efi\boot\bootx64.efi' }
            default { $null }
        }
    }
    if (-not $efiLoaderRel) {
        $efiLoaderRel = 'efi\boot\bootaa64.efi'
        Add-AuditFinding -Severity Warning -Section $sectionLayout -Message 'Assuming arm64 EFI loader path for checks (manifest architecture missing).'
    }
    $bootmgfwPath = Join-Path $root 'bootmgfw.efi'
    if (Test-Path -LiteralPath $bootmgfwPath) {
        Add-AuditFinding -Severity Info -Section $sectionLayout -Message 'OK: bootmgfw.efi'
    }
    elseif ($manifest -and [string]$manifest.source.architecture -eq 'arm64') {
        Add-AuditFinding -Severity Info -Section $sectionLayout -Message 'bootmgfw.efi absent; ARM64 media is validated by efi\boot\bootaa64.efi and efisys.bin.'
    }
    else {
        Add-AuditFinding -Severity Error -Section $sectionLayout -Message 'Missing: bootmgfw.efi (bootmgfw.efi)'
    }
    Test-AuditPath -Root $root -RelativePath $efiLoaderRel -Section $sectionLayout -Label "EFI loader ($efiLoaderRel)" | Out-Null
    Test-AuditPath -Root $root -RelativePath 'efi\microsoft\boot\efisys.bin' -Section $sectionLayout | Out-Null

    $bootWimPath = Join-Path $root 'sources\boot.wim'
    if (Test-Path -LiteralPath $bootWimPath) {
        $bimgs = @(Get-WindowsImage -ImagePath $bootWimPath -ErrorAction Stop | Sort-Object ImageIndex)
        foreach ($b in $bimgs) {
            $audit.bootWimImages += [ordered]@{
                ImageIndex = [int]$b.ImageIndex
                ImageName  = [string]$b.ImageName
            }
        }
        Add-AuditFinding -Severity Info -Section 'boot.wim' -Message ("Image count: {0}" -f $bimgs.Count)
        Add-AuditLine (($bimgs | ForEach-Object { '  boot.wim [{0}] {1}' -f $_.ImageIndex, $_.ImageName }) -join "`n")
    }
    else {
        Add-AuditFinding -Severity Warning -Section 'boot.wim' -Message 'sources\boot.wim missing'
    }

    if ($audit.installImagePath) {
        Add-AuditLine ''
        Add-AuditLine '--- install.wim / install.esd (DISM) ---'
        $imgs = @(Get-WindowsImage -ImagePath $audit.installImagePath -ErrorAction Stop | Sort-Object ImageIndex)
        foreach ($img in $imgs) {
            $det = Get-WindowsImage -ImagePath $audit.installImagePath -Index ([int]$img.ImageIndex) -ErrorAction Stop
            $archStr = switch ([int]$det.Architecture) {
                9 { 'amd64' }
                12 { 'arm64' }
                0 { 'x86' }
                default { "arch$([int]$det.Architecture)" }
            }
            $row = [ordered]@{
                ImageIndex       = [int]$img.ImageIndex
                ImageName        = [string]$img.ImageName
                ImageDescription = [string]$img.ImageDescription
                Architecture     = $archStr
                ImageSize        = if ($img.ImageSize) { [int64]$img.ImageSize } else { 0 }
            }
            $audit.installImages += $row
            Add-AuditLine ("  [{0}] {1} | arch={2} | size={3:N0}" -f $row.ImageIndex, $row.ImageName, $archStr, $row.ImageSize)
        }
        if ($imgs.Count -gt 0) {
            $first = Get-WindowsImage -ImagePath $audit.installImagePath -Index ([int]$imgs[0].ImageIndex) -ErrorAction Stop
            $audit.installArch = switch ([int]$first.Architecture) {
                9 { 'amd64' }
                12 { 'arm64' }
                0 { 'x86' }
                default { "arch$([int]$first.Architecture)" }
            }
        }
    }

    if ($machineProfile) {
        Invoke-WinWSMachineProfileAudit -MachineProfile $machineProfile -Manifest $manifest -IsoRoot $root `
            -InstallImageRows @($audit.installImages) -InstallArchFromWim $audit.installArch -WimIndex $wimIndexForAudit `
            -AssertHostMatches:$AssertHostMatchesMachineProfile
    }

    $srcDir = Join-Path $root 'sources'
    if (Test-Path -LiteralPath $srcDir) {
        Add-AuditLine ''
        Add-AuditLine '--- sources\ (depth 1) ---'
        Get-ChildItem -LiteralPath $srcDir -File -ErrorAction SilentlyContinue |
            Sort-Object Length -Descending |
            Select-Object -First 25 Name, @{ n = 'SizeMB'; e = { [math]::Round($_.Length / 1MB, 1) } } |
            Format-Table -AutoSize |
            Out-String |
            ForEach-Object { $_.TrimEnd() } |
            ForEach-Object { Add-AuditLine $_ }
    }

    $autoPath = Join-Path $root 'autounattend.xml'
    if (Test-Path -LiteralPath $autoPath) {
        Add-AuditLine ''
        Add-AuditLine '--- autounattend.xml (structure) ---'
        try {
            $raw = Get-Content -LiteralPath $autoPath -Raw -ErrorAction Stop
            $xd = [xml]::new()
            $xd.LoadXml($raw)
            $passes = Get-UnattendPassSummary -Doc $xd
            $audit.autounattend.passes = @($passes)
            $audit.autounattend.componentCount = $xd.SelectNodes("//*[local-name()='component']").Count
            Add-AuditFinding -Severity Info -Section 'Unattend' -Message ("Passes: {0}" -f ($passes -join ', '))
            Add-AuditFinding -Severity Info -Section 'Unattend' -Message ("Component nodes: {0}" -f $audit.autounattend.componentCount)
            $diskWipe = $xd.SelectNodes("//*[local-name()='WillWipeDisk']")
            foreach ($w in $diskWipe) {
                $t = $w.InnerText.Trim()
                if ($t -eq 'true') {
                    Add-AuditFinding -Severity Warning -Section 'Unattend' -Message 'Disk configuration includes WillWipeDisk=true (expected for clean install).'
                    break
                }
            }
        }
        catch {
            Add-AuditFinding -Severity Error -Section 'Unattend' -Message "XML parse failed: $($_.Exception.Message)"
        }
    }

    if ($manifest) {
        Add-AuditLine ''
        Add-AuditLine '--- WinWS-BuildManifest.json (summary) ---'
        $audit.manifestSummary.buildResult = [string]$manifest.buildResult
        $audit.manifestSummary.builtAt = [string]$manifest.builtAt
        $audit.manifestSummary.buildDurationSeconds = $manifest.buildDurationSeconds
        $audit.manifestSummary.sourceArchitecture = [string]$manifest.source.architecture
        $audit.manifestSummary.sourceIsoPath = [string]$manifest.source.isoPath
        $audit.manifestSummary.driverSource = [string]$manifest.drivers.source
        $audit.manifestSummary.driverInjectedCount = [int]$manifest.drivers.injectedCount
        $audit.manifestSummary.driverInfNameCount = @($manifest.drivers.infNames).Count
        Add-AuditLine ("buildResult={0} | builtAt={1}" -f $audit.manifestSummary.buildResult, $audit.manifestSummary.builtAt)
        Add-AuditLine ("source.architecture={0}" -f $audit.manifestSummary.sourceArchitecture)
        Add-AuditLine ("drivers: source={0} injectedCount={1} distinctInfNames={2}" -f `
                $audit.manifestSummary.driverSource, $audit.manifestSummary.driverInjectedCount, $audit.manifestSummary.driverInfNameCount)

        $wimNames = @($audit.installImages | ForEach-Object { [string]$_.ImageName })
        $manEd = @($manifest.source.editions)
        $setWim = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($x in $wimNames) { [void]$setWim.Add($x) }
        $setMan = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($x in $manEd) { [void]$setMan.Add([string]$x) }
        $same = $setWim.SetEquals($setMan)
        Add-AuditFinding -Severity $(if ($same) { 'Info' } else { 'Warning' }) -Section 'Manifest' `
            -Message ("Edition name set matches manifest.source.editions: {0}" -f $same)
        if (-not $same) {
            Add-AuditLine ('WIM only: ' + ($setWim -join ' | '))
            Add-AuditLine ('Manifest only: ' + ($setMan -join ' | '))
        }

        if ($audit.installArch -and $manifest.source.architecture) {
            $aok = $audit.installArch -eq [string]$manifest.source.architecture
            Add-AuditFinding -Severity $(if ($aok) { 'Info' } else { 'Error' }) -Section 'Manifest' `
                -Message ("WIM arch ({0}) vs manifest.source.architecture ({1}): match={2}" -f $audit.installArch, $manifest.source.architecture, $aok)
        }
    }

    if ($profile) {
        Add-AuditLine ''
        Add-AuditLine '--- WinWS-BuildProfile.json (summary) ---'
        if ($machineProfile) {
            Add-AuditLine '(Last UI save under output\ — may not match this ISO; manifest + machine profile are authoritative.)'
        }
        try {
            $audit.profileSummary.targetDevice = [string]$profile.target.device
            $audit.profileSummary.computerName = [string]$profile.identity.computerName
            $audit.profileSummary.driverSource = [string]$profile.drivers.source
            $audit.profileSummary.driverPath = [string]$profile.drivers.path
            $audit.profileSummary.sourceArchitecture = [string]$profile.source.architecture
            Add-AuditLine ("target.device={0} | identity.computerName={1}" -f $audit.profileSummary.targetDevice, $audit.profileSummary.computerName)
            Add-AuditLine ("source.architecture={0} | drivers.source={1}" -f $audit.profileSummary.sourceArchitecture, $audit.profileSummary.driverSource)
            if ($audit.profileSummary.driverPath) {
                Add-AuditLine ("drivers.path={0}" -f $audit.profileSummary.driverPath)
            }
            if ($audit.installArch -and $audit.profileSummary.sourceArchitecture) {
                $pok = $audit.installArch -eq $audit.profileSummary.sourceArchitecture
                if ($pok) {
                    Add-AuditFinding -Severity Info -Section 'Profile' `
                        -Message 'WIM arch vs profile.source.architecture match: True'
                }
                elseif ($machineProfile -and -not [string]::IsNullOrWhiteSpace([string]$machineProfile.processorArchitecture) -and
                    ($audit.installArch -eq [string]$machineProfile.processorArchitecture)) {
                    Add-AuditFinding -Severity Info -Section 'Profile' `
                        -Message ("BuildProfile source.architecture ({0}) ≠ WIM ({1}); machine profile matched WIM — BuildProfile is a stale UI snapshot, not the build contract (see WinWS-BuildManifest.json)." -f $audit.profileSummary.sourceArchitecture, $audit.installArch)
                }
                else {
                    Add-AuditFinding -Severity Warning -Section 'Profile' `
                        -Message ("WIM arch ({0}) vs profile.source.architecture ({1}): mismatch." -f $audit.installArch, $audit.profileSummary.sourceArchitecture)
                }
            }
        }
        catch {
            Add-AuditFinding -Severity Warning -Section 'Profile' -Message "Profile parse summary skipped: $($_.Exception.Message)"
        }
    }

    if (-not $machineProfile) {
        Add-AuditLine ''
        Add-AuditLine '--- Generic arm64 install media checklist ---'
        $audit.surfaceLaptop7.expectArm64 = $true
        $audit.surfaceLaptop7.wimIsArm64 = ($audit.installArch -eq 'arm64')
        Add-AuditFinding -Severity $(if ($audit.surfaceLaptop7.wimIsArm64) { 'Info' } else { 'Error' }) -Section 'Surface' `
            -Message ("install.wim architecture is arm64: {0}" -f $audit.surfaceLaptop7.wimIsArm64)
        if ($manifest -and $manifest.drivers.source -eq 'Custom' -and $manifest.drivers.injectedCount -gt 0) {
            Add-AuditFinding -Severity Info -Section 'Surface' `
                -Message ("Custom driver INFs in manifest: {0}" -f $manifest.drivers.injectedCount)
        }
    }
    if ($VerifyInstallImageDrivers -and $audit.installImagePath) {
        Add-AuditLine ''
        Add-AuditLine ("--- Offline install image driver catalog (mount index {0}; slow) ---" -f $wimIndexForAudit)
        $wimMount = Join-Path ([IO.Path]::GetTempPath()) ('WinWS_audit_wim_' + [Guid]::NewGuid().ToString('n'))
        $null = New-Item -ItemType Directory -Path $wimMount -Force
        try {
            try {
                Mount-WindowsImage -ImagePath $audit.installImagePath -Index $wimIndexForAudit -Path $wimMount -ReadOnly -ErrorAction Stop
            }
            catch {
                Mount-WindowsImage -ImagePath $audit.installImagePath -Index $wimIndexForAudit -Path $wimMount -ErrorAction Stop
            }
            $drv = @(Get-WindowsDriver -Path $wimMount -ErrorAction Stop)
            $audit.offlineDrivers = [ordered]@{
                installWimIndex = $wimIndexForAudit
                driverPackages  = $drv.Count
                sampleDrivers   = @($drv | Select-Object -First 12 -ExpandProperty Driver)
            }
            Add-AuditFinding -Severity Info -Section 'OfflineImage' `
                -Message ("Get-WindowsDriver package count: {0}" -f $drv.Count)
            Add-AuditLine ('Sample Driver paths: ' + (($drv | Select-Object -First 6 -ExpandProperty Driver) -join '; '))
            if ($manifest) {
                Add-AuditFinding -Severity Info -Section 'OfflineImage' `
                    -Message 'Manifest drivers.injectedCount counts .inf files passed to DISM; Get-WindowsDriver counts driver packages in the offline store — expect same order of magnitude, not an exact match.'
            }
        }
        catch {
            Add-AuditFinding -Severity Error -Section 'OfflineImage' -Message $_.Exception.Message
        }
        finally {
            if (Test-Path -LiteralPath $wimMount) {
                try {
                    Dismount-WindowsImage -Path $wimMount -Discard -ErrorAction SilentlyContinue | Out-Null
                }
                catch { }
                Remove-Item -LiteralPath $wimMount -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    elseif ($VerifyInstallImageDrivers) {
        Add-AuditFinding -Severity Warning -Section 'OfflineImage' -Message 'Skipped driver catalog mount (no install.wim path).'
    }
}
finally {
    if ($mount) {
        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
    }
}

$audit.findings = @($script:AuditFindings | ForEach-Object {
        [ordered]@{ Severity = $_.Severity; Section = $_.Section; Message = $_.Message }
    })

$errCount = @($script:AuditFindings | Where-Object { $_.Severity -eq 'Error' }).Count
$wrnCount = @($script:AuditFindings | Where-Object { $_.Severity -eq 'Warning' }).Count

Add-AuditLine ''
Add-AuditLine ("======== Summary: {0} error(s), {1} warning(s) ========" -f $errCount, $wrnCount)

if ($SaveReport) {
    $reportPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SaveReport)
    $dir = [System.IO.Path]::GetDirectoryName($reportPath.TrimEnd([char]'/', [char]'\'))
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    Set-Content -LiteralPath $reportPath -Value ($script:AuditLines -join [Environment]::NewLine) -Encoding utf8
    if (-not $Json) {
        Write-Host "Report saved: $reportPath"
    }
}

if ($Json) {
    $audit.summary = [ordered]@{ errors = $errCount; warnings = $wrnCount }
    [pscustomobject]$audit | ConvertTo-Json -Depth 12
}

if ($errCount -gt 0) {
    exit 1
}
exit 0
