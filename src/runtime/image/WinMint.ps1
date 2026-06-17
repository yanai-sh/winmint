#Requires -Version 7.6

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

. "$PSScriptRoot\Core.ps1"
. "$PSScriptRoot\Private\Manifest.ps1"
. "$PSScriptRoot\Reports.ps1"
. "$PSScriptRoot\Private\WslSelection.ps1"
. "$PSScriptRoot\Private\Config\OptionCatalog.ps1"
. "$PSScriptRoot\Private\Config\Profile.ps1"
. "$PSScriptRoot\Private\Config\ProfileAuthoring.ps1"
. "$PSScriptRoot\Engine.ps1"
. "$PSScriptRoot\Private\Bootstrap.ps1"
. "$PSScriptRoot\Private\Runtime.ps1"
. "$PSScriptRoot\Private\PayloadStore.ps1"
. "$PSScriptRoot\Private\UpdatePayloads.ps1"
. "$PSScriptRoot\Private\Console\Host.ps1"
. "$PSScriptRoot\Private\Console\Display.ps1"
. "$PSScriptRoot\Private\Catalog.ps1"
. "$PSScriptRoot\Private\Audit.ps1"
. "$PSScriptRoot\Private\Image\AiRemoval.ps1"
. "$PSScriptRoot\Private\Image\Staging.ps1"
. "$PSScriptRoot\Private\IsoStageCache.ps1"
. "$PSScriptRoot\Private\IntermediatesCache.ps1"
. "$PSScriptRoot\Private\Image\Drivers.ps1"
. "$PSScriptRoot\Private\Image\Tweaks\TweakRegistry.ps1"
. "$PSScriptRoot\Private\Image\Tweaks.ps1"
. "$PSScriptRoot\Private\Image\SetupPayloadStaging.ps1"
. "$PSScriptRoot\Private\Image\Unattend.ps1"
. "$PSScriptRoot\Private\InstallPlan.ps1"
. "$PSScriptRoot\Private\Image\Assets.ps1"
. "$PSScriptRoot\Private\Image\Packages.ps1"
. "$PSScriptRoot\Private\Media.ps1"
. "$PSScriptRoot\Private\UsbMedia.ps1"
. "$PSScriptRoot\Private\Console\Review.ps1"
. "$PSScriptRoot\Private\Pipeline.Console.ps1"
. "$PSScriptRoot\Private\Headless.ps1"
. "$PSScriptRoot\Private\Pipeline.ps1"
. "$PSScriptRoot\Cli.ps1"

function Initialize-WinMintEngine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [switch]$DryRun,
        [switch]$ExportHostDrivers
    )

    $script:WinMintRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
    $script:DryRun = [bool]$DryRun
    $script:ExportHostDrivers = [bool]$ExportHostDrivers
}

