# Shared loader for WinMint backend script modules.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-WinMintModuleRepositoryRoot {
    $current = Split-Path -Parent $PSScriptRoot
    while ($current) {
        $hasSourceRootMarker = (Test-Path -LiteralPath (Join-Path $current 'AGENTS.md')) -or
            (Test-Path -LiteralPath (Join-Path $current '.git'))
        $hasReleaseRootMarker = (Test-Path -LiteralPath (Join-Path $current 'WinMint-CLI.ps1') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $current 'src\runtime\modules') -PathType Container)
        if ($hasSourceRootMarker -or $hasReleaseRootMarker) {
            return (Resolve-Path -LiteralPath $current).Path
        }
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }

    throw 'Unable to determine WinMint repository root from module loader.'
}

function Get-WinMintRuntimeModuleFileList {
    # Only the Profile area is composed through this loader. WinMint.Engine
    # dot-sources src/runtime/image/WinMint.ps1 directly (the single canonical
    # runtime load order) and WinMint.Bootstrap has no image-file dependencies,
    # so per-area wrappers for them were removed. Add an area back only when a
    # module actually consumes it.
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Profile')]
        [string]$Area
    )

    switch ($Area) {
        'Profile' {
            return @(
                'src/runtime/image/Core.ps1',
                'src/runtime/image/Private/WslSelection.ps1',
                'src/runtime/image/Private/Config/OptionCatalog.ps1',
                'src/runtime/image/Private/Config/Profile.ps1',
                'src/runtime/image/Private/Config/ProfileAuthoring.ps1',
                'src/runtime/image/Private/Headless.ps1'
            )
        }
    }
}
