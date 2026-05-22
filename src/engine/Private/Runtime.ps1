#Requires -Version 7.3

function Get-Win11IsoProcessTempPath {
    <# <summary>Per-process temp directory from [IO.Path]::GetTempPath() (trimmed); callers use this instead of the TEMP shell variable.</summary> #>
    $p = [System.IO.Path]::GetTempPath()
    if ([string]::IsNullOrWhiteSpace($p)) {
        throw 'GetTempPath() returned an empty path; cannot determine a writable temp directory.'
    }
    return $p.TrimEnd([char]'\', [char]'/')
}

function Initialize-ConsoleUtf8ForSpectre {
    <# <summary>Align Windows console and PowerShell with UTF-8 before Spectre loads.</summary> #>
    # Use $IsWindows (PS 6+); $PSVersionTable.PSPlatform is missing on Windows PowerShell 5.1 and throws under StrictMode.
    if (-not $IsWindows) { return }
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding = $utf8
    [Console]::InputEncoding = $utf8
    # Preference variable is not updated by a plain $OutputEncoding assignment inside a function scope.
    $global:OutputEncoding = $utf8
    try {
        $chcpExe = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)) 'System32\chcp.com'
        $null = & $chcpExe 65001 2>$null
    }
    catch {
        Write-Verbose "chcp 65001: $($_.Exception.Message)"
    }
}

function Get-Win11IsoDependencyCacheRoot {
    <# <summary>Stable under %TEMP% so GitHub downloads and Save-Module output survive between script runs.</summary> #>
    $root = Join-Path (Get-Win11IsoProcessTempPath) 'Win11ISO_dependency_cache'
    if (-not (Test-Path -LiteralPath $root)) {
        $null = New-Item -ItemType Directory -Path $root -Force
    }
    return $root
}

function Invoke-WebRequestCachedFile {
    <# <summary>Download to %TEMP%\Win11ISO_dependency_cache\downloads if missing or empty; returns the local file path.</summary> #>
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$CacheFileName,
        [hashtable]$Headers = @{}
    )
    $dir = Join-Path (Get-Win11IsoDependencyCacheRoot) 'downloads'
    $null = New-Item -ItemType Directory -Path $dir -Force
    $safe = ($CacheFileName -replace '[<>:"|?*\\/]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = ('download_' + [Guid]::NewGuid().ToString('n')) }
    $dest = Join-Path $dir $safe
    if ((Test-Path -LiteralPath $dest) -and ((Get-Item -LiteralPath $dest).Length -gt 0)) {
        LogVerbose "Using cached file: $safe"
        return $dest
    }
    $part = "$dest.part"
    $ih = @{ 'User-Agent' = 'WinMint/1.0' }
    foreach ($k in $Headers.Keys) { $ih[$k] = $Headers[$k] }
    try {
        Invoke-WebRequest -Verbose:$false -Uri $Uri -OutFile $part -Headers $ih
        Move-Item -LiteralPath $part -Destination $dest -Force
    }
    catch {
        Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
        throw
    }
    return $dest
}

function Get-WinMintCachedDownloadFile {
    param(
        [Parameter(Mandatory)][string[]]$Patterns,
        [string]$DownloadDir = (Join-Path (Get-Win11IsoDependencyCacheRoot) 'downloads')
    )

    if ([string]::IsNullOrWhiteSpace($DownloadDir) -or -not (Test-Path -LiteralPath $DownloadDir)) {
        return $null
    }

    foreach ($pattern in $Patterns) {
        $match = Get-ChildItem -LiteralPath $DownloadDir -Filter $pattern -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -gt 0 } |
            Sort-Object LastWriteTimeUtc, Name -Descending |
            Select-Object -First 1
        if ($null -ne $match) { return $match.FullName }
    }

    return $null
}

function Test-WinMintGitHubApiReachable {
    param([int]$TimeoutSec = 5)

    try {
        $null = Invoke-WebRequest -Uri 'https://api.github.com' -Method Head -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Test-IsPathUnderWin11IsoDependencyCache {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $root = [IO.Path]::GetFullPath((Get-Win11IsoDependencyCacheRoot))
    try {
        $p = [IO.Path]::GetFullPath($Path)
        return $p.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}
