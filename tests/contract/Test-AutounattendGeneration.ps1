#Requires -Version 7.6
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:root = $root
. (Join-Path $root 'tests\contract\TestFixtures.ps1')
. (Join-Path $root 'src\runtime\image\WinMint.ps1')
Initialize-WinMintEngine -RepositoryRoot $root -DryRun

# Dry-run autounattend prints a Spectre table; contracts do not require the gallery module.
function Write-SpectreKeyValueTable {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [string]$TableColor = 'Grey'
    )
    [void]$Title
    [void]$Rows
    [void]$TableColor
}

$failures = [System.Collections.Generic.List[string]]::new()

function Add-AutounattendFailure {
    param([string]$Message)
    $script:failures.Add($Message) | Out-Null
}

function Get-WinMintUnattendRunPaths {
    param([Parameter(Mandatory)][string]$AutounattendXml)

    $xml = [xml]$AutounattendXml
    $ns = [System.Xml.XmlNamespaceManager]::new($xml.NameTable)
    $ns.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
    @($xml.SelectNodes('//u:RunSynchronousCommand/u:Path', $ns) | ForEach-Object { [string]$_.InnerText })
}

function New-WinMintAutounattendCommonArgs {
    $template = Get-Content -LiteralPath (Join-Path $root 'config\autounattend.xml') -Raw
    @{
        MountDir             = 'C:\WinMint-Mount'
        IsoContents          = 'C:\WinMint-Iso'
        AutounattendTemplate = $template
        ImageArch            = 'amd64'
        TimeZone             = 'UTC'
        TargetPCName         = 'WinMint'
        TargetUser           = 'dev'
        TargetPass           = ''
        EditionName          = 'Windows 11 Home'
        EditionMode          = 'TargetLicense'
        AutoLogon            = $false
        InputLocale          = 'en-US'
        SystemLocale         = 'en-US'
        UILanguage           = 'en-US'
        UILanguageFallback   = 'en-US'
        UserLocale           = 'en-US'
        ScriptRoot           = $root
        AgentProfile         = $null
        SetupProfile         = $null
        DryRun               = $true
        HardwareBypass       = $false
    }
}

function New-WinMintTestDiskLayout {
    param([Parameter(Mandatory)][string]$Mode)

    [ordered]@{
        mode                 = $Mode
        preset               = $(if ($Mode -eq 'DualBootReserved') { 'Balanced' } else { '' })
        roundingGb           = 64
        windowsMinimumGb     = 256
        windowsRecommendedGb = 384
        linuxMinimumGb       = 128
        linuxRecommendedGb   = 256
        efiMb                = 1024
        msrMb                = 16
        recoveryMb           = 1024
    }
}

function Assert-RunSynchronousPathBudget {
    param([Parameter(Mandatory)][string]$AutounattendXml)

    foreach ($pathText in @(Get-WinMintUnattendRunPaths -AutounattendXml $AutounattendXml)) {
        if ($pathText.Length -gt 259) {
            Add-AutounattendFailure "RunSynchronousCommand <Path> is $($pathText.Length) chars (> 259 limit): $($pathText.Substring(0, [Math]::Min(80, $pathText.Length)))..."
        }
    }
}

$common = New-WinMintAutounattendCommonArgs

# --- AutoWipeDisk0 + DevDrive Off: keep native DiskConfiguration (no DevDrive diskpart) ---
$native = Install-Autounattend @common `
    -AutoWipeDisk:$true `
    -DiskLayout (New-WinMintTestDiskLayout -Mode 'AutoWipeDisk0') `
    -DevDrive ([ordered]@{ mode = 'Off'; sizeGb = 128 })
Assert-RunSynchronousPathBudget -AutounattendXml $native.AutounattendXml
if ($native.AutounattendXml -notmatch 'DiskConfiguration') {
    Add-AutounattendFailure 'AutoWipeDisk0 without Partition Dev Drive should keep native DiskConfiguration.'
}
if ([string]$native.DiskpartPeScript) {
    Add-AutounattendFailure 'AutoWipeDisk0 without Partition Dev Drive must not stage WinMintDiskpart.ps1.'
}
if ($native.AutounattendXml -match 'WinMintDiskpart\.ps1') {
    Add-AutounattendFailure 'AutoWipeDisk0 without Partition Dev Drive must not launch WinMintDiskpart.ps1.'
}

# --- AutoWipeDisk0 + Partition: force diskpart + ReFS DevDrive carve ---
$partition = Install-Autounattend @common `
    -AutoWipeDisk:$true `
    -DiskLayout (New-WinMintTestDiskLayout -Mode 'AutoWipeDisk0') `
    -DevDrive ([ordered]@{ mode = 'Partition'; sizeGb = 128 })
Assert-RunSynchronousPathBudget -AutounattendXml $partition.AutounattendXml
if ($partition.AutounattendXml -match '<DiskConfiguration') {
    Add-AutounattendFailure 'Partition Dev Drive must remove native DiskConfiguration and use diskpart.'
}
if ($partition.AutounattendXml -notmatch 'WinMintDiskpart\.ps1') {
    Add-AutounattendFailure 'Partition Dev Drive must launch WinMintDiskpart.ps1 from ISO root.'
}
if ([string]$partition.DiskpartPeScript -notmatch 'format quick fs=refs label=DevDrive') {
    Add-AutounattendFailure 'Partition Dev Drive PE script must format fs=refs label=DevDrive.'
}
if ([string]$partition.DiskpartPeScript -notmatch 'size=131072') {
    Add-AutounattendFailure 'Partition Dev Drive PE script should carve 128 GB (131072 MB).'
}

# --- DualBootReserved + Partition: Dev Drive from Windows share ---
$dual = Install-Autounattend @common `
    -AutoWipeDisk:$true `
    -DiskLayout (New-WinMintTestDiskLayout -Mode 'DualBootReserved') `
    -DevDrive ([ordered]@{ mode = 'Partition'; sizeGb = 64 })
Assert-RunSynchronousPathBudget -AutounattendXml $dual.AutounattendXml
if ($dual.AutounattendXml -notmatch 'WinMintDiskpart\.ps1') {
    Add-AutounattendFailure 'DualBoot Partition Dev Drive must launch WinMintDiskpart.ps1.'
}
if ([string]$dual.DiskpartPeScript -notmatch 'windowsOnlyGb') {
    Add-AutounattendFailure 'DualBoot Partition Dev Drive script should carve Dev Drive from the Windows share (windowsOnlyGb).'
}
if ([string]$dual.DiskpartPeScript -notmatch 'size=65536') {
    Add-AutounattendFailure 'DualBoot Partition Dev Drive PE script should carve 64 GB (65536 MB).'
}

# --- VhdDynamic must not force Setup diskpart DevDrive ---
$vhd = Install-Autounattend @common `
    -AutoWipeDisk:$true `
    -DiskLayout (New-WinMintTestDiskLayout -Mode 'AutoWipeDisk0') `
    -DevDrive ([ordered]@{ mode = 'VhdDynamic'; sizeGb = 64 })
if ([string]$vhd.DiskpartPeScript -or $vhd.AutounattendXml -match 'WinMintDiskpart\.ps1') {
    Add-AutounattendFailure 'VhdDynamic Dev Drive must not inject Setup diskpart launcher.'
}
if ($vhd.AutounattendXml -notmatch 'DiskConfiguration') {
    Add-AutounattendFailure 'VhdDynamic with AutoWipeDisk0 should keep native DiskConfiguration.'
}

# --- Profile validation: Partition + Manual fails; VhdDynamic + Manual ok ---
try {
    $manualPartition = New-WinMintBuildProfile -Settings @{
        Profile        = 'WinMint'
        ISOPath        = (Get-WinMintTestOfficialIsoFixturePath)
        Architecture   = 'arm64'
        ComputerName   = 'WinMint'
        AccountName    = 'dev'
        DriverSource   = 'None'
        DiskMode       = 'Manual'
        DevDriveMode   = 'Partition'
        DevDriveSizeGb = 128
    }
    $manualResult = Test-WinMintBuildProfile -BuildProfile $manualPartition
    if ($manualResult.Passed) {
        Add-AutounattendFailure 'Partition Dev Drive + Manual disk mode must fail profile validation.'
    }
    elseif (-not (@($manualResult.Failures) -match 'Partition requires AutoWipeDisk0 or DualBootReserved')) {
        Add-AutounattendFailure "Partition+Manual validation missed expected failure text; got: $($manualResult.Failures -join ' | ')"
    }
}
catch {
    Add-AutounattendFailure "Partition+Manual validation threw unexpectedly: $($_.Exception.Message)"
}

try {
    $manualVhd = New-WinMintBuildProfile -Settings @{
        Profile        = 'WinMint'
        ISOPath        = (Get-WinMintTestOfficialIsoFixturePath)
        Architecture   = 'arm64'
        ComputerName   = 'WinMint'
        AccountName    = 'dev'
        DriverSource   = 'None'
        DiskMode       = 'Manual'
        DevDriveMode   = 'VhdDynamic'
        DevDriveSizeGb = 64
    }
    Assert-WinMintBuildProfile -BuildProfile $manualVhd
    if ([string]$manualVhd.target.devDrive.mode -ne 'VhdDynamic' -or [int]$manualVhd.target.devDrive.sizeGb -ne 64) {
        Add-AutounattendFailure 'VhdDynamic + Manual must author target.devDrive mode/sizeGb.'
    }
}
catch {
    Add-AutounattendFailure "VhdDynamic+Manual should validate: $($_.Exception.Message)"
}

try {
    $off = New-WinMintBuildProfile -Settings @{
        Profile      = 'WinMint'
        ISOPath      = (Get-WinMintTestOfficialIsoFixturePath)
        Architecture = 'arm64'
        ComputerName = 'WinMint'
        AccountName  = 'dev'
        DriverSource = 'None'
    }
    if ([string]$off.target.devDrive.mode -ne 'Off') {
        Add-AutounattendFailure 'Default profile target.devDrive.mode must be Off.'
    }
}
catch {
    Add-AutounattendFailure "Default Dev Drive Off profile failed: $($_.Exception.Message)"
}

$pathLen = (Get-WinMintDiskpartRunSynchronousPath).Length
if ($pathLen -gt 259) {
    Add-AutounattendFailure "Get-WinMintDiskpartRunSynchronousPath is $pathLen chars (> 259)."
}

if ($failures.Count -gt 0) {
    throw "Autounattend generation contract failed:`n$($failures -join "`n")"
}

Write-Host 'Autounattend generation contract smoke passed.'
