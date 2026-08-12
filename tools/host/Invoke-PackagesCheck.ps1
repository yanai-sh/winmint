#requires -Version 7.6
<#
.SYNOPSIS
  Execute a C#-authored package proof request and write a transient outcome.
.NOTES
  This script does not read the catalog, choose entries, calculate hashes, or write the proof.
#>
param(
    [Parameter(Mandatory)]
    [string] $RequestPath,

    [Parameter(Mandatory)]
    [string] $OutcomePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$DownloadTimeoutSeconds = 600

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string] $FileName,
        [Parameter(Mandatory)][string[]] $ArgumentList,
        [Parameter(Mandatory)][string] $Label
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FileName
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $ArgumentList) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "$Label failed to start"
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timeout = [System.Threading.CancellationTokenSource]::new(
            [TimeSpan]::FromSeconds($DownloadTimeoutSeconds))
        try {
            $null = $process.WaitForExitAsync($timeout.Token).GetAwaiter().GetResult()
        }
        catch [System.OperationCanceledException] {
            if (-not $process.HasExited) {
                try {
                    $process.Kill($true)
                }
                catch [System.InvalidOperationException] {
                    # Process exited between HasExited and Kill.
                }
            }
            throw "$Label timed out after $DownloadTimeoutSeconds seconds"
        }
        finally {
            $timeout.Dispose()
        }

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $output = (@($stdout, $stderr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) `
            -join [Environment]::NewLine
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output   = $output.Trim()
        }
    }
    finally {
        $process.Dispose()
    }
}

function Get-JsonProperty {
    param(
        [Parameter(Mandatory)][psobject] $Object,
        [Parameter(Mandatory)][string] $Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-FirstUrl {
    param($Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Array]) {
        if ($Value.Count -eq 0) { return $null }
        return [string]$Value[0]
    }
    return [string]$Value
}

function Invoke-WingetTarget {
    param(
        [Parameter(Mandatory)][System.Management.Automation.CommandInfo] $Winget,
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][string] $Architecture
    )

    $downloadDirectory = Join-Path ([System.IO.Path]::GetTempPath()) (
        'winmint-winget-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $downloadDirectory | Out-Null
    try {
        [string[]] $arguments = @(
            'download', '--id', $Id, '--exact',
            '--download-directory', $downloadDirectory,
            '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements',
            '--architecture', $Architecture
        )
        $completed = Invoke-BoundedProcess `
            -FileName $Winget.Source `
            -ArgumentList $arguments `
            -Label "winget download for '$Id'"
        $output = $completed.Output
        $exitCode = $completed.ExitCode

        # Some architecture-neutral installers have no explicit ARM64 manifest row.
        if ($exitCode -ne 0 -and $output -match 'No applicable installer') {
            Get-ChildItem -LiteralPath $downloadDirectory -File -Recurse -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
            [string[]] $arguments = @(
                'download', '--id', $Id, '--exact',
                '--download-directory', $downloadDirectory,
                '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements'
            )
            $completed = Invoke-BoundedProcess `
                -FileName $Winget.Source `
                -ArgumentList $arguments `
                -Label "winget fallback download for '$Id'"
            $output = $completed.Output
            $exitCode = $completed.ExitCode
        }

        if ($exitCode -ne 0) {
            if ($output.Length -gt 600) { $output = $output.Substring(0, 600) + '…' }
            throw "winget download exited ${exitCode}: $output"
        }

        $files = @(Get-ChildItem -LiteralPath $downloadDirectory -File -Recurse)
        if ($files.Count -eq 0 -or ($files | Measure-Object -Property Length -Sum).Sum -le 0) {
            throw 'winget download produced no files'
        }
    }
    finally {
        Remove-Item -LiteralPath $downloadDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-ScoopTarget {
    param(
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][string] $Bucket
    )

    $bucketRoot = switch ($Bucket) {
        'main' { 'https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket' }
        'extras' { 'https://raw.githubusercontent.com/ScoopInstaller/Extras/master/bucket' }
        default { throw "unsupported scoop bucket '$Bucket'" }
    }
    $manifestUri = "$bucketRoot/$Id.json"
    try {
        $manifest = Invoke-RestMethod `
            -Uri $manifestUri `
            -Method Get `
            -TimeoutSec $DownloadTimeoutSeconds
    }
    catch {
        throw "scoop manifest request failed (600-second timeout): $($_.Exception.Message)"
    }
    $architecture = Get-JsonProperty -Object $manifest -Name 'architecture'
    $url = $null
    if ($null -ne $architecture) {
        foreach ($name in @('arm64', 'aarch64')) {
            $node = Get-JsonProperty -Object $architecture -Name $name
            if ($null -ne $node) {
                $url = Get-FirstUrl (Get-JsonProperty -Object $node -Name 'url')
                if (-not [string]::IsNullOrWhiteSpace($url)) { break }
            }
        }
    }
    else {
        $url = Get-FirstUrl (Get-JsonProperty -Object $manifest -Name 'url')
    }

    if ([string]::IsNullOrWhiteSpace($url)) {
        throw "scoop manifest has no ARM64/aarch64 or universal URL: $manifestUri"
    }

    $downloadDirectory = Join-Path ([System.IO.Path]::GetTempPath()) (
        'winmint-scoop-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $downloadDirectory | Out-Null
    try {
        $destination = Join-Path $downloadDirectory 'payload.bin'
        try {
            Invoke-WebRequest `
                -Uri $url `
                -OutFile $destination `
                -MaximumRedirection 5 `
                -TimeoutSec $DownloadTimeoutSeconds
        }
        catch {
            throw "scoop archive request failed (600-second timeout): $($_.Exception.Message)"
        }
        if (-not (Test-Path -LiteralPath $destination) -or
            (Get-Item -LiteralPath $destination).Length -le 0) {
            throw 'scoop archive download was empty'
        }
    }
    finally {
        Remove-Item -LiteralPath $downloadDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Write-Outcome {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Outcome
    )

    $directory = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($directory)) {
        throw "OutcomePath must have a parent directory: $Path"
    }
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporaryPath = Join-Path $directory (
        ".$([System.IO.Path]::GetFileName($Path)).$([guid]::NewGuid().ToString('N')).tmp")
    try {
        $json = ($Outcome | ConvertTo-Json -Depth 8) + "`n"
        [System.IO.File]::WriteAllText($temporaryPath, $json)
        [System.IO.File]::Move($temporaryPath, $Path, $true)
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

$osArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
$processArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
$hostDiagnostics = [ordered]@{
    osArchitecture                 = $osArchitecture
    processArchitecture            = $processArchitecture
    processorArchitecture          = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE')
    processorArchitectureW6432     = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITEW6432')
    wingetVersion                  = $null
}
$architecture = $null
$catalogSha256 = $null
$entries = @()
$results = [System.Collections.Generic.List[object]]::new()
$fatalError = $null
$targetFailed = $false

try {
    if (-not (Test-Path -LiteralPath $RequestPath -PathType Leaf)) {
        throw "request missing: $RequestPath"
    }
    $request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
    if ([string](Get-JsonProperty -Object $request -Name 'schemaVersion') -ne
        'winmint.packages.check.request/v1') {
        throw 'unsupported request schemaVersion'
    }

    $architecture = [string](Get-JsonProperty -Object $request -Name 'architecture')
    $catalogSha256 = [string](Get-JsonProperty -Object $request -Name 'catalogSha256')
    $requestEntries = Get-JsonProperty -Object $request -Name 'entries'
    if ($architecture -ne 'arm64') { throw "request architecture must be arm64 (got '$architecture')" }
    if ($catalogSha256 -notmatch '^[0-9a-f]{64}$') { throw 'request catalogSha256 is malformed' }
    if ($null -eq $requestEntries) { throw 'request entries must be an array' }
    $entries = @($requestEntries)

    foreach ($entry in $entries) {
        $source = [string](Get-JsonProperty -Object $entry -Name 'source')
        $id = [string](Get-JsonProperty -Object $entry -Name 'id')
        $bucketValue = Get-JsonProperty -Object $entry -Name 'bucket'
        $bucket = if ($null -eq $bucketValue) { $null } else { [string]$bucketValue }
        if ($source -notin @('winget', 'scoop')) { throw "request source is invalid: '$source'" }
        if ([string]::IsNullOrWhiteSpace($id)) { throw 'request entry id is empty' }
        if ($source -eq 'winget' -and $null -ne $bucket) {
            throw "winget request entry '$id' must not have a bucket"
        }
        if ($source -eq 'scoop' -and [string]::IsNullOrWhiteSpace($bucket)) {
            throw "scoop request entry '$id' must have a bucket"
        }

        $results.Add([pscustomobject][ordered]@{
            source    = $source
            id        = $id
            bucket    = $bucket
            succeeded = $false
            method    = if ($source -eq 'winget') {
                'winget-download'
            }
            else {
                'scoop-manifest-download'
            }
            error     = 'not executed'
        })
    }

    if ($osArchitecture -ne 'Arm64' -or $processArchitecture -ne 'Arm64') {
        throw (
            'packages-check requires native ARM64 ' +
            "(OSArchitecture=$osArchitecture, ProcessArchitecture=$processArchitecture, " +
            "PROCESSOR_ARCHITECTURE=$($hostDiagnostics.processorArchitecture), " +
            "PROCESSOR_ARCHITEW6432=$($hostDiagnostics.processorArchitectureW6432))")
    }

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        throw 'winget not on PATH (install App Installer on the native ARM64 host)'
    }
    $hostDiagnostics.wingetVersion = (& $winget.Source --version 2>$null | Out-String).Trim()
    $sourceUpdate = Invoke-BoundedProcess `
        -FileName $winget.Source `
        -ArgumentList @('source', 'update', '--disable-interactivity') `
        -Label 'winget source update'
    if ($sourceUpdate.ExitCode -ne 0) {
        throw "winget source update exited $($sourceUpdate.ExitCode): $($sourceUpdate.Output)"
    }

    for ($i = 0; $i -lt $entries.Count; $i++) {
        $result = $results[$i]
        try {
            if ($result.source -eq 'winget') {
                Invoke-WingetTarget -Winget $winget -Id $result.id -Architecture $architecture
            }
            else {
                Invoke-ScoopTarget -Id $result.id -Bucket $result.bucket
            }
            $result.succeeded = $true
            $result.error = $null
            Write-Output "ok $($result.source):$($result.id)"
        }
        catch {
            $result.error = $_.Exception.Message
            $targetFailed = $true
            Write-Output "FAIL $($result.source):$($result.id): $($result.error)"
        }
    }
}
catch {
    $fatalError = $_.Exception.Message
    foreach ($result in $results) {
        if ($result.error -eq 'not executed') {
            $result.error = $fatalError
        }
    }
}
finally {
    $outcome = [ordered]@{
        schemaVersion = 'winmint.packages.check.outcome/v1'
        architecture  = $architecture
        catalogSha256 = $catalogSha256
        host           = $hostDiagnostics
        completedAtUtc = [datetimeoffset]::UtcNow.ToString('o')
        fatalError     = $fatalError
        results        = @($results)
    }
    Write-Outcome -Path $OutcomePath -Outcome $outcome
}

if ($null -ne $fatalError -or $targetFailed) { exit 1 }
exit 0
