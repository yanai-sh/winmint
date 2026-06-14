#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Version,

    [string]$OutputDirectory = '',
    [switch]$SkipGuiBuild,
    [string]$RustTarget = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:WinMintRepositoryRoot = $root
. (Join-Path $root 'src\runtime\image\Core.ps1')
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Get-WinMintPath -Name DistRoot
}
$bundleName = "WinMint-$Version"
$zipName = "$bundleName.zip"
$zipPath = Join-Path $OutputDirectory $zipName
$hashPath = "$zipPath.sha256"
$stageRoot = Join-Path ([IO.Path]::GetTempPath()) "WinMintRelease-$([guid]::NewGuid().ToString('N'))"
$stage = Join-Path $stageRoot $bundleName
$manifestPath = Get-WinMintPath -Name ConfigRoot -ChildPath 'release-manifest.json'

function Write-BundleLog {
    param([string]$Message)
    $stamp = Get-Date -Format 'HH:mm:ss.fff'
    Write-Host "[$stamp] $Message"
}

function Get-BundleFileSha256 {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = $sha.ComputeHash($stream)
            return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
        }
        finally {
            $sha.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Copy-BundlePath {
    param([string]$RelativePath)

    $source = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Required bundle path missing: $RelativePath"
    }

    $target = Join-Path $stage $RelativePath
    $targetParent = Split-Path -Parent $target
    if ($targetParent) {
        New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
    }

    Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
}

function ConvertTo-BundleRegex {
    param([Parameter(Mandatory)][string]$Pattern)

    $normalized = ($Pattern -replace '/', '\').Trim('\')
    $escaped = [regex]::Escape($normalized)
    $escaped = $escaped -replace '\\\*\\\*', '.*'
    $escaped = $escaped -replace '\\\*', '[^\\]*'
    return '^(?:' + $escaped + ')(?:\\.*)?$'
}

function Remove-BundleExcludedPath {
    param([Parameter(Mandatory)][string[]]$Patterns)

    $regexes = @($Patterns | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
        ConvertTo-BundleRegex -Pattern $_
    })
    if ($regexes.Count -eq 0) { return }

    Get-ChildItem -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending |
        Where-Object {
            $trim = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
            $relative = $_.FullName.Substring($stage.Length).TrimStart($trim)
            $relative = $relative -replace '/', '\'
            foreach ($regex in $regexes) {
                if ($relative -match $regex) { return $true }
            }
            return $false
        } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

function Import-BundleManifest {
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Release manifest missing: $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.schema -ne 'winmint.releaseManifest.v1') {
        throw "Unsupported release manifest schema: $($manifest.schema)"
    }
    if (-not $manifest.include -or @($manifest.include).Count -eq 0) {
        throw 'Release manifest must include at least one path.'
    }
    return $manifest
}

function Assert-WinMintReleaseInputs {
    $guiBinary = Get-WinMintPath -Name GuiBinary
    if (-not (Test-Path -LiteralPath $guiBinary -PathType Leaf)) {
        throw "Packaged GUI binary missing: $guiBinary"
    }

    $bootstrap = Get-Content -LiteralPath (Get-WinMintPath -Name RepoRoot -ChildPath 'winmint.ps1') -Raw
    if ($bootstrap -match '''Gui''\s*\{\s*Find-WinMintGuiScript\s+-Root\s+\$versionRoot\s*\}') {
        throw 'winmint.ps1 must use the packaged GUI script captured at install time, not re-resolve a fallback.'
    }

    $docHits = @(Get-ChildItem -LiteralPath (Get-WinMintPath -Name DocsRoot) -Recurse -File -Include '*.md' -ErrorAction SilentlyContinue |
        Select-String -Pattern @('WIP GUI', 'not packaged', 'not part of the release bundle') -SimpleMatch)
    if ($docHits.Count -gt 0) {
        throw "Documentation still describes the GUI as experimental or unpackaged: $($docHits[0].Path)"
    }
}

try {
    if (-not $SkipGuiBuild) {
    $buildGui = Get-WinMintPath -Name ReleaseToolsRoot -ChildPath 'Build-WinMintGui.ps1'
        & $buildGui -RustTarget $RustTarget
        if ($LASTEXITCODE -ne 0) {
            throw "GUI build failed with exit code $LASTEXITCODE."
        }
    }
    Assert-WinMintReleaseInputs

    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $stage -Force | Out-Null

    $manifest = Import-BundleManifest
    $include = @($manifest.include)

    foreach ($path in $include) {
        Write-BundleLog "Adding $path"
        Copy-BundlePath -RelativePath $path
    }

    $exclude = @($manifest.exclude)
    if ($exclude.Count -gt 0) {
        Write-BundleLog "Applying $($exclude.Count) release exclusion(s)"
        Remove-BundleExcludedPath -Patterns $exclude
    }

    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    if (Test-Path -LiteralPath $hashPath) {
        Remove-Item -LiteralPath $hashPath -Force
    }

    Write-BundleLog "Writing $zipPath"
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath -Force

    $hash = Get-BundleFileSha256 -Path $zipPath
    Set-Content -LiteralPath $hashPath -Value "$hash  $zipName" -Encoding ASCII

    Write-BundleLog "SHA256 $hash"
    Write-BundleLog "Created $zipPath"
    Write-BundleLog "Created $hashPath"
} finally {
    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
