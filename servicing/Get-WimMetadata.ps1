#requires -Version 7.6
<#
.SYNOPSIS
  Parse / assert DISM Get-WimInfo text for ImageServicing WIM metadata discipline (IMAGESERVICING §10).
.NOTES
  Dot-source from Mount-InstallWim / Export-Wim / Build-Iso.
#>
param(
    [string] $ListFromTextPath,
    [string] $ListFromIso
)

function Test-WimMetadataUndefined([string] $Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    $t = $Value.Trim()
    return $t -eq 'undefined' -or $t -eq '<undefined>'
}

function ConvertFrom-WimInfoText {
    param(
        [Parameter(Mandatory)]
        [string] $Text,
        [int] $Index = 0
    )

    $indexCount = ([regex]::Matches($Text, '(?m)^Index : \d+\s*$')).Count
    $blocks = @([regex]::Split($Text, '(?m)(?=^Index : \d+\s*$)') |
        Where-Object { $_ -match '(?m)^Index : \d+\s*$' })

    $selected = $null
    if ($Index -gt 0) {
        foreach ($block in $blocks) {
            if ($block -match "(?m)^Index : $Index\s*$") {
                $selected = $block
                break
            }
        }
        if ($null -eq $selected) {
            throw "Get-WimInfo: index $Index not found (indexCount=$indexCount)"
        }
    }
    elseif ($blocks.Count -eq 1) {
        $selected = $blocks[0]
    }
    elseif ($blocks.Count -gt 1) {
        throw "Get-WimInfo: Index parameter required when indexCount=$indexCount"
    }
    else {
        throw 'Get-WimInfo: no Index blocks parsed'
    }

    function Read-Field([string] $Block, [string] $Name) {
        if ($Block -match "(?m)^$([regex]::Escape($Name))\s*:\s*(.+?)\s*$") {
            return $Matches[1].Trim()
        }
        return $null
    }

    $name = Read-Field $selected 'Name'
    $arch = Read-Field $selected 'Architecture'
    $edition = Read-Field $selected 'Edition'
    $installation = Read-Field $selected 'Installation'
    $productType = Read-Field $selected 'ProductType'
    $productSuite = Read-Field $selected 'ProductSuite'
    $languages = Read-Field $selected 'Languages'
    $version = Read-Field $selected 'Version'
    $build = Read-Field $selected 'ServicePack Build'
    if ([string]::IsNullOrWhiteSpace($build)) {
        $build = $version
    }

    $parsedIndex = 0
    if ($selected -match '(?m)^Index : (\d+)\s*$') {
        $parsedIndex = [int]$Matches[1]
    }

    return [ordered]@{
        IndexCount    = $indexCount
        Index         = $parsedIndex
        Name          = $name
        Architecture  = $arch
        Edition       = $edition
        Installation  = $installation
        ProductType   = $productType
        ProductSuite  = $productSuite
        Languages     = $languages
        Build         = $build
        Version       = $version
    }
}

function ConvertFrom-WimInfoListText {
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    $blocks = @([regex]::Split($Text, '(?m)(?=^Index : \d+\s*$)') |
        Where-Object { $_ -match '(?m)^Index : \d+\s*$' })
    if ($blocks.Count -lt 1) {
        throw 'wim.probe.empty: no Index blocks parsed'
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($block in $blocks) {
        $snap = ConvertFrom-WimInfoText -Text $block -Index 0
        $name = [string]$snap.Name
        if (Test-WimMetadataUndefined $name) {
            throw "wim.probe.incompleteName: Index $($snap.Index) Name is missing or undefined"
        }

        $rows.Add([ordered]@{
                index        = [int]$snap.Index
                name         = $name.Trim()
                architecture = $(if ($snap.Architecture) { [string]$snap.Architecture } else { $null })
                edition      = $(if ($snap.Edition) { [string]$snap.Edition } else { $null })
                version      = $(if ($snap.Version) { [string]$snap.Version } else { $null })
                build        = $(if ($snap.Build) { [string]$snap.Build } else { $null })
            })
    }

    return $rows
}

function Get-WimIndexList {
    param(
        [Parameter(Mandatory)]
        [string] $WimFile
    )

    if (-not (Test-Path -LiteralPath $WimFile)) {
        throw "wim.probe.wimMissing: WIM missing: $WimFile"
    }

    # IndexCount from summary list (no /Index). Per-index detail needs /Index — 25H2 summary omits Architecture.
    $summary = & dism.exe /English /Get-WimInfo /WimFile:$WimFile 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "wim.probe.unreadable: Get-WimInfo failed: $LASTEXITCODE`n$summary"
    }

    $indexCount = ([regex]::Matches($summary, '(?m)^Index : \d+\s*$')).Count
    if ($indexCount -lt 1) {
        throw 'wim.probe.empty: no Index blocks parsed'
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    for ($i = 1; $i -le $indexCount; $i++) {
        $detail = & dism.exe /English /Get-WimInfo /WimFile:$WimFile /Index:$i 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "wim.probe.unreadable: Get-WimInfo /Index:$i failed: $LASTEXITCODE`n$detail"
        }

        $parts.Add($detail)
    }

    return ,(ConvertFrom-WimInfoListText -Text ($parts -join "`n"))
}

function Get-SourceIsoWimIndexList {
    param(
        [Parameter(Mandatory)]
        [string] $IsoPath
    )

    if ([string]::IsNullOrWhiteSpace($IsoPath) -or -not (Test-Path -LiteralPath $IsoPath)) {
        throw "wim.probe.isoMissing: Source ISO not found: $IsoPath"
    }

    $disk = Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop
    try {
        Start-Sleep -Seconds 1
        $letter = ($disk | Get-Volume | Select-Object -First 1).DriveLetter
        if ([string]::IsNullOrWhiteSpace($letter)) {
            throw 'wim.probe.unreadable: ISO mounted but no drive letter'
        }

        $isoRoot = "${letter}:"
        $wimFile = Join-Path $isoRoot 'sources\install.wim'
        if (-not (Test-Path -LiteralPath $wimFile)) {
            $esd = Join-Path $isoRoot 'sources\install.esd'
            if (Test-Path -LiteralPath $esd) {
                throw 'wim.probe.unreadable: install.esd present; convert to WIM before probing (not implemented)'
            }

            throw "wim.probe.wimMissing: install.wim missing under $isoRoot\sources"
        }

        return ,(Get-WimIndexList -WimFile $wimFile)
    }
    finally {
        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
    }
}

function Write-WimIndexListJson {
    param(
        [Parameter(Mandatory)]
        $Rows
    )

    $payload = [ordered]@{ indexes = @($Rows) }
    $payload | ConvertTo-Json -Depth 6 -Compress
}

function Get-WimMetadataSnapshot {
    param(
        [Parameter(Mandatory)]
        [string] $WimFile,
        [int] $Index = 1
    )

    if (-not (Test-Path -LiteralPath $WimFile)) {
        throw "WIM missing: $WimFile"
    }

    # IndexCount from summary list (no /Index). Per-index detail needs /Index — 25H2 summary omits Architecture.
    $summary = & dism.exe /English /Get-WimInfo /WimFile:$WimFile 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Get-WimInfo failed: $LASTEXITCODE`n$summary"
    }

    $indexCount = ([regex]::Matches($summary, '(?m)^Index : \d+\s*$')).Count
    if ($indexCount -lt 1) {
        throw 'Get-WimInfo: no Index blocks parsed'
    }

    $detailIndex = $Index
    if ($detailIndex -le 0) {
        if ($indexCount -eq 1) { $detailIndex = 1 }
        else { throw "Get-WimInfo: Index parameter required when indexCount=$indexCount" }
    }

    $detail = & dism.exe /English /Get-WimInfo /WimFile:$WimFile /Index:$detailIndex 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Get-WimInfo /Index:$detailIndex failed: $LASTEXITCODE`n$detail"
    }

    $snap = ConvertFrom-WimInfoText -Text $detail -Index 0
    $snap['IndexCount'] = $indexCount
    $snap['Index'] = $detailIndex
    return $snap
}

function Clear-WimReadOnly {
    param([Parameter(Mandatory)][string] $WimFile)
    if (-not (Test-Path -LiteralPath $WimFile)) { return }
    $item = Get-Item -LiteralPath $WimFile
    if ($item.IsReadOnly) {
        $item.IsReadOnly = $false
        Write-Output "Cleared read-only on $WimFile"
    }
}

function Assert-WimMetadataPresent {
    param(
        [Parameter(Mandatory)] $Snapshot,
        [string] $Context = 'WIM metadata'
    )

    # Always required (Setup / ImageInstall coherence).
    foreach ($key in @('Name', 'Architecture')) {
        $v = [string]$Snapshot[$key]
        if (Test-WimMetadataUndefined $v) {
            throw "${Context}: $key is missing or undefined"
        }
    }

    # CTT-style Setup edition fields — required when DISM prints them; never allow <undefined>.
    foreach ($key in @('Edition', 'Installation', 'ProductType', 'ProductSuite', 'Languages')) {
        $v = [string]$Snapshot[$key]
        if ($null -eq $Snapshot[$key] -or $v -eq '') { continue }
        if (Test-WimMetadataUndefined $v) {
            throw "${Context}: $key is undefined"
        }
    }
}

function Assert-WimMetadataStable {
    param(
        [Parameter(Mandatory)] $Before,
        [Parameter(Mandatory)] $After,
        [string] $Context = 'WIM metadata'
    )

    Assert-WimMetadataPresent -Snapshot $Before -Context "${Context} (before)"
    Assert-WimMetadataPresent -Snapshot $After -Context "${Context} (after)"

    foreach ($key in @('Name', 'Architecture', 'Edition', 'Installation', 'ProductType', 'ProductSuite', 'Languages')) {
        $b = [string]$Before[$key]
        $a = [string]$After[$key]
        if ([string]::IsNullOrWhiteSpace($b)) { continue }
        if (Test-WimMetadataUndefined $a) {
            throw "${Context}: after.$key is missing or undefined (was '$b')"
        }
        if (-not $b.Equals($a, [StringComparison]::OrdinalIgnoreCase)) {
            throw "${Context}: $key changed from '$b' to '$a'"
        }
    }

    $beforeBuild = [string]$Before['Build']
    $afterBuild = [string]$After['Build']
    if (-not [string]::IsNullOrWhiteSpace($beforeBuild)) {
        if (Test-WimMetadataUndefined $afterBuild) {
            throw "${Context}: after.Build is missing or undefined (was '$beforeBuild')"
        }
        $beforeUbr = 0
        $afterUbr = 0
        if ([int]::TryParse($beforeBuild, [ref]$beforeUbr) -and [int]::TryParse($afterBuild, [ref]$afterUbr)) {
            if ($afterUbr -lt $beforeUbr) {
                throw "${Context}: ServicePack Build decreased from '$beforeBuild' to '$afterBuild'"
            }
        }
        elseif (-not $beforeBuild.Equals($afterBuild, [StringComparison]::OrdinalIgnoreCase)) {
            throw "${Context}: Build changed from '$beforeBuild' to '$afterBuild'"
        }
    }
}

function Resolve-WimEditionId {
    param($Snapshot)

    $edition = [string]$Snapshot['Edition']
    if (-not (Test-WimMetadataUndefined $edition)) {
        return $edition
    }

    $name = [string]$Snapshot['Name']
    if (Test-WimMetadataUndefined $name) { return $null }

    # Order matters: more-specific names before generic Pro/Home/Enterprise/Education.
    switch -Regex ($name.Trim()) {
        'Pro for Workstations N' { return 'ProfessionalWorkstationN' }
        'Pro for Workstations' { return 'ProfessionalWorkstation' }
        'Pro Education N' { return 'ProfessionalEducationN' }
        'Pro Education' { return 'ProfessionalEducation' }
        'Pro N' { return 'ProfessionalN' }
        '(?i)\bPro\b' { return 'Professional' }
        'Home N' { return 'CoreN' }
        'Home Single Language' { return 'CoreSingleLanguage' }
        '(?i)\bHome\b' { return 'Core' }
        '(?i)IoT Enterprise LTSC' { return 'IoTEnterpriseS' }
        '(?i)Enterprise LTSC' { return 'EnterpriseS' }
        'Enterprise N' { return 'EnterpriseN' }
        'Enterprise' { return 'Enterprise' }
        'Education N' { return 'EducationN' }
        'Education' { return 'Education' }
        default { return $null }
    }
}

function Write-WinMintEditionConfig {
    param(
        [Parameter(Mandatory)][string] $MediaDir,
        [Parameter(Mandatory)] $Snapshot
    )

    $sourcesDir = Join-Path $MediaDir 'sources'
    New-Item -ItemType Directory -Force -Path $sourcesDir | Out-Null

    $pidPath = Join-Path $sourcesDir 'PID.txt'
    if (Test-Path -LiteralPath $pidPath) {
        Remove-Item -LiteralPath $pidPath -Force
        Write-Output 'Removed sources\PID.txt (stale product-key data)'
    }

    $editionId = Resolve-WimEditionId -Snapshot $Snapshot
    if ([string]::IsNullOrWhiteSpace($editionId)) {
        Write-Output 'Warning: EditionID unknown — skipping sources\ei.cfg'
        return
    }

    $eiCfgPath = Join-Path $sourcesDir 'ei.cfg'
    $eiCfg = @"
[EditionID]
$editionId
[Channel]
Retail
[VL]
0
"@.Trim() + "`r`n"
    # ASCII matches Windows Setup expectations for ei.cfg.
    [System.IO.File]::WriteAllText($eiCfgPath, $eiCfg, [System.Text.Encoding]::ASCII)
    Write-Output "Written sources\ei.cfg EditionID=$editionId"
}

function Write-WimMetadataEvidence {
    param(
        [Parameter(Mandatory)] [string] $WorkDirectory,
        [Parameter(Mandatory)] $Document
    )

    $logDir = Join-Path $WorkDirectory 'logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $metaPath = Join-Path $logDir 'wim-metadata.json'
    ($Document | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $metaPath -Encoding utf8

    $digestPath = Join-Path $logDir 'digests.json'
    $digests = @{}
    if (Test-Path -LiteralPath $digestPath) {
        $existing = Get-Content -LiteralPath $digestPath -Raw | ConvertFrom-Json
        foreach ($p in $existing.PSObject.Properties) {
            $digests[[string]$p.Name] = [string]$p.Value
        }
    }

    $final = $Document.final
    if ($null -eq $final) { $final = $Document.after }
    if ($null -eq $final) { $final = $Document.afterCommit }
    if ($null -ne $final) {
        if ($final.Name) { $digests['wim.meta.name'] = [string]$final.Name }
        if ($final.Architecture) { $digests['wim.meta.architecture'] = [string]$final.Architecture }
        if ($final.Edition) { $digests['wim.meta.edition'] = [string]$final.Edition }
        if ($final.Installation) { $digests['wim.meta.installation'] = [string]$final.Installation }
        if ($final.ProductType) { $digests['wim.meta.productType'] = [string]$final.ProductType }
        if ($final.Build) { $digests['wim.meta.build'] = [string]$final.Build }
        $editionId = Resolve-WimEditionId -Snapshot $final
        if ($editionId) { $digests['wim.meta.editionId'] = $editionId }
    }

    if (-not (Get-Command -Name Save-WinMintDigestMap -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'Save-WinMintDigestMap.ps1')
    }
    Save-WinMintDigestMap -WorkDirectory $WorkDirectory -Digests $digests
}

if ($ListFromTextPath) {
    if (-not (Test-Path -LiteralPath $ListFromTextPath)) {
        Write-Error "wim.probe.unreadable: text path missing: $ListFromTextPath"
        exit 1
    }

    try {
        $text = Get-Content -LiteralPath $ListFromTextPath -Raw -Encoding utf8
        $rows = ConvertFrom-WimInfoListText -Text $text
        Write-Output (Write-WimIndexListJson -Rows $rows)
        exit 0
    }
    catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}

if ($ListFromIso) {
    try {
        $rows = Get-SourceIsoWimIndexList -IsoPath $ListFromIso
        Write-Output (Write-WimIndexListJson -Rows $rows)
        exit 0
    }
    catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}
