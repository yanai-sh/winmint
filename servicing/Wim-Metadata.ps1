#requires -Version 7.6
<#
.SYNOPSIS
  Parse / assert DISM Get-WimInfo text for ImageServicing WIM metadata discipline (IMAGESERVICING §10).
.NOTES
  Dot-source from Mount-InstallWim / Export-Wim / Build-Iso. Self-check: pwsh -File Wim-Metadata.ps1 -SelfCheck
#>
param(
    [switch] $SelfCheck
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
    $blocks = [regex]::Split($Text, '(?m)(?=^Index : \d+\s*$)') |
        Where-Object { $_ -match '(?m)^Index : \d+\s*$' }

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

function Get-WimMetadataSnapshot {
    param(
        [Parameter(Mandatory)]
        [string] $WimFile,
        [int] $Index = 1
    )

    if (-not (Test-Path -LiteralPath $WimFile)) {
        throw "WIM missing: $WimFile"
    }

    # Full list (no /Index) so IndexCount reflects every image; then select one block.
    $text = & dism.exe /English /Get-WimInfo /WimFile:$WimFile 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Get-WimInfo failed: $LASTEXITCODE`n$text"
    }

    return ConvertFrom-WimInfoText -Text $text -Index $Index
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

    foreach ($key in @('Name', 'Architecture', 'Edition', 'Installation', 'ProductType', 'ProductSuite', 'Languages', 'Build')) {
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
}

function Resolve-WimEditionId {
    param($Snapshot)

    $edition = [string]$Snapshot['Edition']
    if (-not (Test-WimMetadataUndefined $edition)) {
        return $edition
    }

    $name = [string]$Snapshot['Name']
    if (Test-WimMetadataUndefined $name) { return $null }

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

    ($digests | ConvertTo-Json) | Set-Content -LiteralPath $digestPath -Encoding utf8
}

if ($SelfCheck) {
    $sample = @'
Deployment Image Servicing and Management tool
Version: 10.0.26100.1

Details for image : C:\media\sources\install.wim

Index : 3
Name : Windows 11 Pro
Description : Windows 11 Pro
Size : 15,000,000,000 bytes
Architecture : ARM64
Hal : acpiapic
Version : 10.0.26100.1
ServicePack Build : 26100
ServicePack Level : 0
Edition : Professional
Installation : Client
ProductType : WinNT
ProductSuite : Terminal Server
Languages : en-US
System Root : WINDOWS
Directories : 30000
Files : 100000
Created : 1/1/2025 - 12:00:00 AM
Modified : 1/2/2025 - 12:00:00 AM

The operation completed successfully.
'@

    $parsed = ConvertFrom-WimInfoText -Text $sample -Index 3
    if ($parsed.IndexCount -ne 1) { throw "SelfCheck: expected IndexCount 1, got $($parsed.IndexCount)" }
    if ($parsed.Installation -ne 'Client') { throw 'SelfCheck: Installation' }
    if ($parsed.ProductType -ne 'WinNT') { throw 'SelfCheck: ProductType' }
    if ((Resolve-WimEditionId -Snapshot $parsed) -ne 'Professional') { throw 'SelfCheck: EditionId from Edition' }

    $multi = @'
Index : 1
Name : Windows 11 Home
Architecture : ARM64
Edition : Core
ServicePack Build : 26100

Index : 3
Name : Windows 11 Pro
Architecture : ARM64
Edition : Professional
Installation : Client
ProductType : WinNT
ProductSuite : Terminal Server
ServicePack Build : 26100
'@
    $homeSnap = ConvertFrom-WimInfoText -Text $multi -Index 1
    $proSnap = ConvertFrom-WimInfoText -Text $multi -Index 3
    if ($homeSnap.IndexCount -ne 2) { throw "SelfCheck: expected IndexCount 2" }
    if ($homeSnap.Name -ne 'Windows 11 Home') { throw "SelfCheck: Home name" }
    if ($proSnap.Name -ne 'Windows 11 Pro') { throw "SelfCheck: Pro name" }
    if ($proSnap.Architecture -ne 'ARM64') { throw "SelfCheck: arch" }
    if ($proSnap.Edition -ne 'Professional') { throw "SelfCheck: edition" }
    if ($proSnap.Build -ne '26100') { throw "SelfCheck: build" }

    Assert-WimMetadataStable -Before $proSnap -After $proSnap -Context 'SelfCheck identity'

    $badName = [ordered]@{ Name = '<undefined>'; Architecture = 'ARM64'; Edition = 'Professional'; Installation = 'Client'; ProductType = 'WinNT'; Build = '26100' }
    $threw = $false
    try { Assert-WimMetadataStable -Before $proSnap -After $badName -Context 'SelfCheck bad name' } catch { $threw = $true }
    if (-not $threw) { throw 'SelfCheck: expected assert throw on <undefined> Name' }

    $badEdition = [ordered]@{
        Name = 'Windows 11 Pro'; Architecture = 'ARM64'; Edition = '<undefined>'
        Installation = 'Client'; ProductType = 'WinNT'; Build = '26100'
    }
    $threw = $false
    try { Assert-WimMetadataPresent -Snapshot $badEdition -Context 'SelfCheck bad edition' } catch { $threw = $true }
    if (-not $threw) { throw 'SelfCheck: expected assert throw on <undefined> Edition' }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('winmint-ei-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'sources') | Out-Null
    Set-Content -LiteralPath (Join-Path $tmp 'sources\PID.txt') -Value 'stale' -Encoding utf8
    Write-WinMintEditionConfig -MediaDir $tmp -Snapshot $proSnap
    if (Test-Path -LiteralPath (Join-Path $tmp 'sources\PID.txt')) { throw 'SelfCheck: PID.txt should be removed' }
    $ei = Get-Content -LiteralPath (Join-Path $tmp 'sources\ei.cfg') -Raw
    if ($ei -notmatch '\[EditionID\]\r?\nProfessional') { throw "SelfCheck: ei.cfg EditionID`n$ei" }
    Remove-Item -LiteralPath $tmp -Recurse -Force

    $fromName = Resolve-WimEditionId -Snapshot ([ordered]@{ Name = 'Windows 11 Pro'; Edition = $null })
    if ($fromName -ne 'Professional') { throw 'SelfCheck: EditionId from Name' }

    Write-Output 'Wim-Metadata SelfCheck ok'
    exit 0
}
