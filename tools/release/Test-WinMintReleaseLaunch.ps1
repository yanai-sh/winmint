#Requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$BundlePath,

    [string]$ChecksumPath = '',
    [string]$InstallRoot = '',
    [string]$Version = '',
    [switch]$SkipGuiLaunch,
    [switch]$LaunchGui,
    [switch]$KeepInstallRoot,
    [switch]$SkipBootstrapDownload
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:WinMintRepositoryRoot = $root
. (Join-Path $root 'src\runtime\image\Core.ps1')

function Write-ReleaseSmokeLog {
    param([string]$Message)

    $stamp = Get-Date -Format 'HH:mm:ss.fff'
    Write-Host "[$stamp] $Message"
}

function Get-ReleaseSmokeFileSha256 {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = $sha.ComputeHash($stream)
            return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '').ToUpperInvariant()
        }
        finally {
            $sha.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Assert-ReleaseSmokePath {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$RelativePath,
        [ValidateSet('Leaf','Container')]
        [string]$PathType = 'Leaf'
    )

    $path = Join-Path $RootPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType $PathType)) {
        throw "Release smoke check failed: missing $PathType '$RelativePath'."
    }
}

function Assert-ReleaseSmokePathAbsent {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $path = Join-Path $RootPath $RelativePath
    if (Test-Path -LiteralPath $path) {
        throw "Release smoke check failed: forbidden release path exists: '$RelativePath'."
    }
}

function Assert-ReleaseSmokeNoChildPathLike {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$Pattern
    )

    if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
        return
    }

    $match = Get-ChildItem -LiteralPath $RootPath -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like $Pattern } |
        Select-Object -First 1
    if ($match) {
        throw "Release smoke check failed: unexpected path remains: '$($match.FullName)'."
    }
}

function Test-ReleaseSmokeChecksum {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$HashPath
    )

    if (-not (Test-Path -LiteralPath $HashPath -PathType Leaf)) {
        throw "Checksum file not found: $HashPath"
    }

    $text = Get-Content -LiteralPath $HashPath -Raw -Encoding ASCII
    $match = [regex]::Match($text, '(?i)\b[a-f0-9]{64}\b')
    if (-not $match.Success) {
        throw "Checksum file does not contain a SHA256 hash: $HashPath"
    }

    $expected = $match.Value.ToUpperInvariant()
    $actual = Get-ReleaseSmokeFileSha256 -Path $ArchivePath
    if ($actual -ne $expected) {
        throw "Release bundle SHA256 mismatch. Expected $expected, got $actual."
    }

    Write-ReleaseSmokeLog "OK release bundle SHA256 $actual"
}

function Get-ReleaseSmokeVersion {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [string]$RequestedVersion
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedVersion)) {
        return $RequestedVersion
    }

    $name = [IO.Path]::GetFileNameWithoutExtension($ArchivePath)
    $match = [regex]::Match($name, '^WinMint-(?<version>.+)$')
    if (-not $match.Success) {
        throw "Could not infer release version from bundle name '$name'. Pass -Version."
    }

    return $match.Groups['version'].Value
}

function Test-ReleaseSmokeInstalledTree {
    param([Parameter(Mandatory)][string]$ReleaseRoot)

    foreach ($leaf in @(
            'WinMint-CLI.ps1',
            'WinMint-GUI.ps1',
            'assets\runtime\setup\setup-shell\wizard.html',
            'assets\runtime\setup\setup-shell\wizard.js',
            'tools\ui-bridge\New-UiBuildProfile.ps1',
            'config\release-manifest.json',
            'config\packages.json',
            'schemas\winmint.buildprofile.schema.json',
            'src\runtime\image\WinMint.ps1',
            'src\runtime\firstlogon\Start-WinMintAgent.ps1',
            'src\runtime\modules\WinMint.Bootstrap\WinMint.Bootstrap.psd1',
            'src\runtime\modules\WinMint.Engine\WinMint.Engine.psd1'
        )) {
        Assert-ReleaseSmokePath -RootPath $ReleaseRoot -RelativePath $leaf -PathType Leaf
    }

    foreach ($container in @(
            'assets',
            'config',
            'docs',
            'schemas',
            'src\runtime\modules',
            'src\runtime\setup',
            'src\runtime\firstlogon'
        )) {
        Assert-ReleaseSmokePath -RootPath $ReleaseRoot -RelativePath $container -PathType Container
    }

    foreach ($forbidden in @(
            'tools\vm',
            'tools\dev',
            'tools\release',
            'tools\validation',
            'tools\audit',
            'tools\media',
            'tools\assets',
            'tools\drivers',
            'tools\firstlogon',
            'tests',
            'output',
            'dist',
            'temp',
            'node_modules',
            'docs\codebase',
            'docs\superpowers'
        )) {
        Assert-ReleaseSmokePathAbsent -RootPath $ReleaseRoot -RelativePath $forbidden
    }

    $forbiddenArtifacts = @(Get-ChildItem -LiteralPath $ReleaseRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '^\.(iso|wim|esd|swm|vhd|vhdx|log)$' })
    if ($forbiddenArtifacts.Count -gt 0) {
        $first = $forbiddenArtifacts[0].FullName.Substring($ReleaseRoot.Length).TrimStart('\', '/')
        throw "Release smoke check failed: forbidden artifact was packaged: $first"
    }

    Write-ReleaseSmokeLog 'OK release tree required/forbidden path checks'
}

function Invoke-ReleaseSmokePackagedCli {
    param([Parameter(Mandatory)][string]$ReleaseRoot)

    $pwsh = (Get-Command 'pwsh.exe' -ErrorAction Stop).Source
    $cli = Join-Path $ReleaseRoot 'WinMint-CLI.ps1'
    Write-ReleaseSmokeLog 'Running packaged CLI help smoke check.'
    & $pwsh -NoProfile -ExecutionPolicy Bypass -File $cli help | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Packaged CLI help failed with exit code $LASTEXITCODE."
    }
    Write-ReleaseSmokeLog 'OK packaged CLI help'
}

function Invoke-ReleaseSmokeGuiLaunch {
    param([Parameter(Mandatory)][string]$ReleaseRoot)

    $archFolder = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    $wizard = Join-Path $ReleaseRoot "assets\runtime\setup\setup-shell\bin\$archFolder\WinMintSetupShell.exe"
    $shellRoot = Join-Path $ReleaseRoot 'assets\runtime\setup\setup-shell'
    Write-ReleaseSmokeLog "Starting packaged wizard host for manual launch smoke: $wizard"
    $process = Start-Process -FilePath $wizard -ArgumentList @('--wizard', '--shell-root', $shellRoot, '--repo-root', $ReleaseRoot, '--preview') -PassThru
    Write-ReleaseSmokeLog "Packaged wizard host started with PID $($process.Id)."
}

function Get-ReleaseSmokeFreePort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return [int]$listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
}

function Start-ReleaseSmokeServer {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$HashPath,
        [Parameter(Mandatory)][string]$Tag
    )

    $port = Get-ReleaseSmokeFreePort
    $baseUrl = "http://127.0.0.1:$port"
    $archiveName = [IO.Path]::GetFileName($ArchivePath)
    $checksumName = [IO.Path]::GetFileName($HashPath)
    $release = [pscustomobject][ordered]@{
        tag_name = $Tag
        assets = @(
            [pscustomobject][ordered]@{
                name = $archiveName
                browser_download_url = "$baseUrl/assets/$archiveName"
            },
            [pscustomobject][ordered]@{
                name = $checksumName
                browser_download_url = "$baseUrl/assets/$checksumName"
            }
        )
    }
    $releaseJson = $release | ConvertTo-Json -Depth 8

    $job = Start-Job -ScriptBlock {
        param(
            [int]$Port,
            [string]$ReleaseJson,
            [string]$ArchivePath,
            [string]$HashPath
        )

        function Write-SmokeHttpResponse {
            param(
                [Parameter(Mandatory)][System.IO.Stream]$Stream,
                [int]$StatusCode,
                [string]$StatusText,
                [string]$ContentType,
                [byte[]]$Body
            )

            $header = "HTTP/1.1 $StatusCode $StatusText`r`nContent-Type: $ContentType`r`nContent-Length: $($Body.Length)`r`nConnection: close`r`n`r`n"
            $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
            $Stream.Write($headerBytes, 0, $headerBytes.Length)
            if ($Body.Length -gt 0) {
                $Stream.Write($Body, 0, $Body.Length)
            }
        }

        function Get-SmokeHttpRequestPath {
            param([string]$RequestLine)

            $parts = $RequestLine.Split(' ')
            if ($parts.Count -lt 2) { return '/' }
            $rawPath = [string]$parts[1]
            $queryIndex = $rawPath.IndexOf('?')
            if ($queryIndex -ge 0) {
                $rawPath = $rawPath.Substring(0, $queryIndex)
            }
            return [uri]::UnescapeDataString($rawPath)
        }

        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        try {
            $stop = $false
            while (-not $stop) {
                $client = $listener.AcceptTcpClient()
                try {
                    $stream = $client.GetStream()
                    $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
                    $requestLine = $reader.ReadLine()
                    if ([string]::IsNullOrWhiteSpace($requestLine)) {
                        continue
                    }
                    while ($true) {
                        $line = $reader.ReadLine()
                        if ([string]::IsNullOrEmpty($line)) { break }
                    }

                    $path = Get-SmokeHttpRequestPath -RequestLine $requestLine
                    if ($path -eq '/health') {
                        $body = [System.Text.Encoding]::UTF8.GetBytes('ok')
                        Write-SmokeHttpResponse -Stream $stream -StatusCode 200 -StatusText 'OK' -ContentType 'text/plain' -Body $body
                        continue
                    }
                    if ($path -eq '/shutdown') {
                        $body = [System.Text.Encoding]::UTF8.GetBytes('bye')
                        Write-SmokeHttpResponse -Stream $stream -StatusCode 200 -StatusText 'OK' -ContentType 'text/plain' -Body $body
                        $stop = $true
                        continue
                    }
                    if ($path -match '^/repos/local/winmint/releases/(latest|tags/.+)$') {
                        $body = [System.Text.Encoding]::UTF8.GetBytes($ReleaseJson)
                        Write-SmokeHttpResponse -Stream $stream -StatusCode 200 -StatusText 'OK' -ContentType 'application/json' -Body $body
                        continue
                    }
                    if ($path -like '/assets/*.zip') {
                        $body = [System.IO.File]::ReadAllBytes($ArchivePath)
                        Write-SmokeHttpResponse -Stream $stream -StatusCode 200 -StatusText 'OK' -ContentType 'application/zip' -Body $body
                        continue
                    }
                    if ($path -like '/assets/*.sha256') {
                        $body = [System.IO.File]::ReadAllBytes($HashPath)
                        Write-SmokeHttpResponse -Stream $stream -StatusCode 200 -StatusText 'OK' -ContentType 'text/plain' -Body $body
                        continue
                    }

                    $notFound = [System.Text.Encoding]::UTF8.GetBytes('not found')
                    Write-SmokeHttpResponse -Stream $stream -StatusCode 404 -StatusText 'Not Found' -ContentType 'text/plain' -Body $notFound
                }
                finally {
                    $client.Close()
                }
            }
        }
        finally {
            $listener.Stop()
        }
    } -ArgumentList $port, $releaseJson, $ArchivePath, $HashPath

    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            Invoke-WebRequest -Uri "$baseUrl/health" -UseBasicParsing -TimeoutSec 1 | Out-Null
            return [pscustomobject]@{
                BaseUrl = $baseUrl
                Job = $job
            }
        }
        catch {
            Start-Sleep -Milliseconds 200
        }
    }

    Stop-Job -Job $job -ErrorAction SilentlyContinue
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    throw 'Timed out waiting for local release smoke server.'
}

function Stop-ReleaseSmokeServer {
    param([Parameter(Mandatory)]$Server)

    try {
        Invoke-WebRequest -Uri "$($Server.BaseUrl)/shutdown" -UseBasicParsing -TimeoutSec 2 | Out-Null
    }
    catch { }

    Wait-Job -Job $Server.Job -Timeout 5 | Out-Null
    Stop-Job -Job $Server.Job -ErrorAction SilentlyContinue
    Remove-Job -Job $Server.Job -Force -ErrorAction SilentlyContinue
}

function Invoke-ReleaseSmokeBootstrapDownload {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$HashPath,
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$BootstrapRoot
    )

    $server = $null
    $previousTemp = $env:TEMP
    $previousTmp = $env:TMP
    $previousLocalAppData = $env:LOCALAPPDATA
    try {
        $tempRoot = Join-Path $BootstrapRoot 'temp'
        $localAppDataRoot = Join-Path $BootstrapRoot 'localappdata'
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $localAppDataRoot -Force | Out-Null
        $env:TEMP = $tempRoot
        $env:TMP = $tempRoot
        $env:LOCALAPPDATA = $localAppDataRoot

        $server = Start-ReleaseSmokeServer -ArchivePath $ArchivePath -HashPath $HashPath -Tag $Tag
        $bootstrap = Join-Path $root 'winmint.ps1'
        Write-ReleaseSmokeLog 'Running bootstrap -NoLaunch against local release endpoint.'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bootstrap `
            -Repository 'local/winmint' `
            -ReleaseApiRoot $server.BaseUrl `
            -Version $Tag `
            -NoLaunch `
            -Force
        if ($LASTEXITCODE -ne 0) {
            throw "Bootstrap -NoLaunch smoke failed with exit code $LASTEXITCODE."
        }

        Assert-ReleaseSmokeNoChildPathLike -RootPath $tempRoot -Pattern 'WinMintBootstrap-*'
        $forbiddenVersionRoot = Join-Path $localAppDataRoot 'WinMint\versions'
        if (Test-Path -LiteralPath $forbiddenVersionRoot) {
            throw "Default bootstrap created a durable version cache: $forbiddenVersionRoot"
        }
        Write-ReleaseSmokeLog 'OK bootstrap temp execution cleanup'
    }
    finally {
        $env:TEMP = $previousTemp
        $env:TMP = $previousTmp
        $env:LOCALAPPDATA = $previousLocalAppData
        if ($server) {
            Stop-ReleaseSmokeServer -Server $server
        }
    }
}

function Invoke-ReleaseSmokeBootstrapIntegrityFailure {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$BootstrapRoot
    )

    $server = $null
    $previousTemp = $env:TEMP
    $previousTmp = $env:TMP
    $previousLocalAppData = $env:LOCALAPPDATA
    try {
        $tempRoot = Join-Path $BootstrapRoot 'temp-integrity'
        $localAppDataRoot = Join-Path $BootstrapRoot 'localappdata-integrity'
        $hashRoot = Join-Path $BootstrapRoot 'bad-hash'
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $localAppDataRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $hashRoot -Force | Out-Null

        $archiveName = [IO.Path]::GetFileName($ArchivePath)
        $badHashPath = Join-Path $hashRoot "$archiveName.sha256"
        Set-Content -LiteralPath $badHashPath -Value "0000000000000000000000000000000000000000000000000000000000000000  $archiveName" -Encoding ASCII

        $env:TEMP = $tempRoot
        $env:TMP = $tempRoot
        $env:LOCALAPPDATA = $localAppDataRoot

        $server = Start-ReleaseSmokeServer -ArchivePath $ArchivePath -HashPath $badHashPath -Tag $Tag
        $bootstrap = Join-Path $root 'winmint.ps1'
        Write-ReleaseSmokeLog 'Running bootstrap bad-checksum failure smoke against local release endpoint.'
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bootstrap `
            -Repository 'local/winmint' `
            -ReleaseApiRoot $server.BaseUrl `
            -Version $Tag `
            -NoLaunch `
            -Force 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) {
            throw 'Bootstrap bad-checksum smoke unexpectedly succeeded.'
        }

        $text = (@($output) | ForEach-Object { [string]$_ }) -join "`n"
        foreach ($expected in @(
                'Failure kind: Integrity',
                'Recovery: Do not run this release asset.',
                'Safe to retry: no',
                'Removed temporary session'
            )) {
            if ($text -notmatch [regex]::Escape($expected)) {
                throw "Bootstrap bad-checksum smoke did not include expected text: $expected"
            }
        }

        Assert-ReleaseSmokeNoChildPathLike -RootPath $tempRoot -Pattern 'WinMintBootstrap-*'
        $global:LASTEXITCODE = 0
        Write-ReleaseSmokeLog 'OK bootstrap integrity failure messaging and cleanup'
    }
    finally {
        $env:TEMP = $previousTemp
        $env:TMP = $previousTmp
        $env:LOCALAPPDATA = $previousLocalAppData
        if ($server) {
            Stop-ReleaseSmokeServer -Server $server
        }
    }
}

$resolvedBundle = (Resolve-Path -LiteralPath $BundlePath).Path
if ([string]::IsNullOrWhiteSpace($ChecksumPath)) {
    $ChecksumPath = "$resolvedBundle.sha256"
}
$resolvedChecksum = (Resolve-Path -LiteralPath $ChecksumPath).Path
$releaseVersion = Get-ReleaseSmokeVersion -ArchivePath $resolvedBundle -RequestedVersion $Version

if ($LaunchGui -and $SkipGuiLaunch) {
    throw 'Use either -LaunchGui or -SkipGuiLaunch, not both.'
}

$createdRoot = $false
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Join-Path ([IO.Path]::GetTempPath()) "WinMintReleaseSmoke-$([guid]::NewGuid().ToString('N'))"
    $createdRoot = $true
}
$resolvedInstallRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallRoot)
$extractRoot = Join-Path $resolvedInstallRoot 'extracted'
$bootstrapRoot = Join-Path $resolvedInstallRoot 'bootstrap'

try {
    New-Item -ItemType Directory -Path $resolvedInstallRoot -Force | Out-Null
    if (Test-Path -LiteralPath $extractRoot) {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $bootstrapRoot) {
        Remove-Item -LiteralPath $bootstrapRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null

    Test-ReleaseSmokeChecksum -ArchivePath $resolvedBundle -HashPath $resolvedChecksum

    Write-ReleaseSmokeLog "Extracting release bundle to '$extractRoot'."
    Expand-Archive -LiteralPath $resolvedBundle -DestinationPath $extractRoot -Force
    Test-ReleaseSmokeInstalledTree -ReleaseRoot $extractRoot
    Invoke-ReleaseSmokePackagedCli -ReleaseRoot $extractRoot

    if (-not $SkipBootstrapDownload) {
        Invoke-ReleaseSmokeBootstrapDownload `
            -ArchivePath $resolvedBundle `
            -HashPath $resolvedChecksum `
            -Tag $releaseVersion `
            -BootstrapRoot $bootstrapRoot
        Invoke-ReleaseSmokeBootstrapIntegrityFailure `
            -ArchivePath $resolvedBundle `
            -Tag $releaseVersion `
            -BootstrapRoot $bootstrapRoot
    }
    else {
        Write-ReleaseSmokeLog 'Skipping bootstrap download smoke.'
    }

    if ($LaunchGui) {
        Invoke-ReleaseSmokeGuiLaunch -ReleaseRoot $extractRoot
    }
    else {
        Write-ReleaseSmokeLog 'Skipping packaged GUI launch. Use -LaunchGui for manual GUI smoke.'
    }

    Write-ReleaseSmokeLog 'Release launch smoke passed.'
}
finally {
    if ((-not $KeepInstallRoot) -and $createdRoot -and (Test-Path -LiteralPath $resolvedInstallRoot)) {
        Remove-Item -LiteralPath $resolvedInstallRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
