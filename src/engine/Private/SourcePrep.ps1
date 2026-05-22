#Requires -Version 7.3

function Get-WinMintUupPrepRoot {
    Join-Path (Get-WinMintOutputDirectory) '.uup'
}

function Get-WinMintUupZipFingerprint {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    [pscustomobject]@{
        Hash = $hash
        Key = $hash.Substring(0, 24)
        Path = $item.FullName
        Length = $item.Length
    }
}

function Test-WinMintUupDumpZip {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if ([IO.Path]::GetExtension($Path) -ine '.zip') { return $false }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $names = @($zip.Entries | ForEach-Object { $_.FullName -replace '/', '\' })
        return ($names -contains 'uup_download_windows.cmd' -and
                $names -contains 'ConvertConfig.ini' -and
                $names -contains 'files\get_aria2.ps1')
    }
    finally {
        $zip.Dispose()
    }
}

function Set-WinMintUupConvertConfigPolicy {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { throw "UUP ConvertConfig.ini not found: $Path" }
    $raw = Get-Content -LiteralPath $Path -Raw
    $policy = [ordered]@{
        AutoStart = '1'
        AddUpdates = '1'
        Cleanup = '1'
        ResetBase = '0'
        NetFx3 = '0'
        wim2esd = '0'
        wim2swm = '0'
        SkipISO = '0'
        AutoExit = '1'
    }
    foreach ($key in $policy.Keys) {
        $value = $policy[$key]
        if ($raw -match "(?m)^$([regex]::Escape($key))\s*=") {
            $raw = [regex]::Replace($raw, "(?m)^$([regex]::Escape($key))\s*=.*$", "$key=$value")
        }
        else {
            $raw += [Environment]::NewLine + "$key=$value"
        }
    }
    [System.IO.File]::WriteAllText($Path, $raw, [System.Text.UTF8Encoding]::new($false))
}

function Get-WinMintPreparedUupIso {
    param([Parameter(Mandatory)][string]$WorkDir)

    $iso = Get-ChildItem -LiteralPath $WorkDir -Filter '*.iso' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($iso) { return $iso.FullName }
    return ''
}

function Format-WinMintUupByteSize {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Get-WinMintUupDirectoryByteCount {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return [pscustomobject]@{ Count = 0; Bytes = 0L } }
    $measure = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum
    [pscustomobject]@{
        Count = [int]$measure.Count
        Bytes = [long]$measure.Sum
    }
}

function Get-WinMintUupNewestFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $null }
    Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
}

function Get-WinMintUupToolProcessNames {
    $names = @(
        'aria2c', 'wimlib-imagex', 'Dism', 'oscdimg',
        'cmd', 'powershell', 'pwsh'
    )
    @(
        Get-Process -Name $names -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty ProcessName -Unique |
            Sort-Object
    )
}

function Get-WinMintUupSourcePrepSnapshot {
    param(
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][datetime]$StartedAt
    )

    $uupsDir = Join-Path $WorkDir 'UUPs'
    $isoFolder = Join-Path $WorkDir 'ISOFOLDER'
    $installWim = Join-Path $isoFolder 'sources\install.wim'
    $aria2Log = Join-Path $WorkDir 'aria2_download.log'
    $aria2Script = @(Get-ChildItem -LiteralPath (Join-Path $WorkDir 'files') -Filter 'aria2_script*.txt' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1)
    $iso = Get-WinMintPreparedUupIso -WorkDir $WorkDir
    $uupBytes = Get-WinMintUupDirectoryByteCount -Path $uupsDir
    $newest = Get-WinMintUupNewestFile -Path $WorkDir
    $processes = @(Get-WinMintUupToolProcessNames)

    $phase = 'Preparing workspace'
    if (-not [string]::IsNullOrWhiteSpace($iso)) {
        $phase = 'ISO ready'
    }
    elseif ($processes -contains 'oscdimg') {
        $phase = 'Creating ISO'
    }
    elseif ($processes -contains 'Dism') {
        $phase = 'Servicing image'
    }
    elseif ($processes -contains 'wimlib-imagex') {
        $phase = 'Building install.wim'
    }
    elseif (Test-Path -LiteralPath $installWim -PathType Leaf) {
        $phase = 'Integrating apps and packages'
    }
    elseif ((Test-Path -LiteralPath $aria2Log -PathType Leaf) -or $uupBytes.Count -gt 0) {
        $phase = 'Downloading and verifying payloads'
    }
    elseif ($aria2Script.Count -gt 0) {
        $phase = 'Resolving download list'
    }

    $wimBytes = 0L
    if (Test-Path -LiteralPath $installWim -PathType Leaf) {
        $wimBytes = [long](Get-Item -LiteralPath $installWim).Length
    }

    [pscustomobject]@{
        Time = [DateTimeOffset]::Now.ToString('o')
        Phase = $phase
        ElapsedSeconds = [int]([DateTime]::Now - $StartedAt).TotalSeconds
        UupFileCount = $uupBytes.Count
        UupBytes = $uupBytes.Bytes
        InstallWimBytes = $wimBytes
        IsoPath = $iso
        ActiveProcesses = @($processes)
        NewestFile = if ($newest) { $newest.FullName } else { '' }
        NewestFileTime = if ($newest) { $newest.LastWriteTime.ToString('o') } else { '' }
    }
}

function Write-WinMintUupProgressSnapshot {
    param(
        [Parameter(Mandatory)][object]$Snapshot,
        [Parameter(Mandatory)][string]$ProgressLogPath
    )

    $parent = Split-Path -Parent $ProgressLogPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    $json = $Snapshot | ConvertTo-Json -Depth 8 -Compress
    Add-Content -LiteralPath $ProgressLogPath -Value $json -Encoding UTF8
}

function Format-WinMintUupProgressMessage {
    param([Parameter(Mandatory)][object]$Snapshot)

    $elapsed = [TimeSpan]::FromSeconds([int]$Snapshot.ElapsedSeconds).ToString('hh\:mm\:ss')
    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add("UUP source prep: $($Snapshot.Phase)") | Out-Null
    $parts.Add("elapsed $elapsed") | Out-Null
    if ([long]$Snapshot.UupBytes -gt 0) {
        $parts.Add("payloads $(Format-WinMintUupByteSize -Bytes ([long]$Snapshot.UupBytes)) in $($Snapshot.UupFileCount) file(s)") | Out-Null
    }
    if ([long]$Snapshot.InstallWimBytes -gt 0) {
        $parts.Add("install.wim $(Format-WinMintUupByteSize -Bytes ([long]$Snapshot.InstallWimBytes))") | Out-Null
    }
    if (@($Snapshot.ActiveProcesses).Count -gt 0) {
        $parts.Add("tools: $(@($Snapshot.ActiveProcesses) -join ', ')") | Out-Null
    }
    $parts -join '; '
}

function Wait-WinMintUupDumpProcess {
    param(
        [Parameter(Mandatory)]$Process,
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string]$ProgressLogPath
    )

    $started = Get-Date
    $lastPhase = ''
    $lastMessageAt = [datetime]::MinValue
    $lastNewestFile = ''
    $lastNewestAt = ''
    Log 'UUP source prep started. This can take 45-90+ minutes on ARM64 when updates and cleanup are enabled.'
    Log 'Progress is estimated from UUP payload files, generated WIM/ISO artifacts, and active tools (aria2c, wimlib, DISM, oscdimg).'

    while (-not $Process.HasExited) {
        $snapshot = Get-WinMintUupSourcePrepSnapshot -WorkDir $WorkDir -StartedAt $started
        Write-WinMintUupProgressSnapshot -Snapshot $snapshot -ProgressLogPath $ProgressLogPath

        $phaseChanged = $snapshot.Phase -ne $lastPhase
        $fileChanged = ($snapshot.NewestFile -ne $lastNewestFile) -or ($snapshot.NewestFileTime -ne $lastNewestAt)
        $timeForHeartbeat = ((Get-Date) - $lastMessageAt).TotalSeconds -ge 60
        if ($phaseChanged -or ($fileChanged -and $timeForHeartbeat) -or $timeForHeartbeat) {
            $message = Format-WinMintUupProgressMessage -Snapshot $snapshot
            if ($phaseChanged) { LogOK $message } else { Log $message }
            $lastPhase = [string]$snapshot.Phase
            $lastMessageAt = Get-Date
            $lastNewestFile = [string]$snapshot.NewestFile
            $lastNewestAt = [string]$snapshot.NewestFileTime
        }

        Start-Sleep -Seconds 10
        try { $Process.Refresh() } catch { break }
    }

    try { $Process.WaitForExit() } catch { }
    $final = Get-WinMintUupSourcePrepSnapshot -WorkDir $WorkDir -StartedAt $started
    Write-WinMintUupProgressSnapshot -Snapshot $final -ProgressLogPath $ProgressLogPath
    if (-not [string]::IsNullOrWhiteSpace([string]$final.IsoPath)) {
        LogOK "$(Format-WinMintUupProgressMessage -Snapshot $final); ISO $([IO.Path]::GetFileName([string]$final.IsoPath))"
    }
}

function Invoke-WinMintUupDumpSourcePrep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$UupDumpZip,
        [switch]$Yes,
        [switch]$ValidateOnly,
        [string]$MockPreparedIso = ''
    )

    if (-not (Test-WinMintUupDumpZip -Path $UupDumpZip)) {
        throw "UUP Dump input must be a conversion zip containing uup_download_windows.cmd, ConvertConfig.ini, and files\get_aria2.ps1: $UupDumpZip"
    }

    $fp = Get-WinMintUupZipFingerprint -Path $UupDumpZip
    $workDir = Join-Path (Get-WinMintUupPrepRoot) $fp.Key
    $extractDir = Join-Path $workDir 'source'
    $logDir = Join-Path $workDir 'logs'
    if (-not [string]::IsNullOrWhiteSpace($MockPreparedIso)) {
        if (-not (Test-Path -LiteralPath $MockPreparedIso -PathType Leaf)) {
            throw "Mock UUP prepared ISO not found: $MockPreparedIso"
        }
        return [pscustomobject]@{
            SourceKind = 'UupDumpZip'
            UupDumpZip = $fp.Path
            UupDumpHash = $fp.Hash
            WorkDir = $workDir
            GeneratedIso = (Get-Item -LiteralPath $MockPreparedIso).FullName
            Reused = $true
            RanConversion = $false
            Mocked = $true
            Logs = $logDir
        }
    }
    $existingIso = Get-WinMintPreparedUupIso -WorkDir $extractDir
    if (-not [string]::IsNullOrWhiteSpace($existingIso)) {
        return [pscustomobject]@{
            SourceKind = 'UupDumpZip'
            UupDumpZip = $fp.Path
            UupDumpHash = $fp.Hash
            WorkDir = $workDir
            GeneratedIso = $existingIso
            Reused = $true
            RanConversion = $false
            Logs = $logDir
        }
    }

    if ($ValidateOnly) {
        return [pscustomobject]@{
            SourceKind = 'UupDumpZip'
            UupDumpZip = $fp.Path
            UupDumpHash = $fp.Hash
            WorkDir = $workDir
            GeneratedIso = ''
            Reused = $false
            RanConversion = $false
            Logs = $logDir
        }
    }

    if (-not $Yes) {
        throw 'UUP Dump source prep needs to download and convert Windows payloads. Re-run with -Yes to allow this source preparation step.'
    }

    $null = New-Item -ItemType Directory -Path $extractDir, $logDir -Force
    if (-not (Test-Path -LiteralPath (Join-Path $extractDir 'uup_download_windows.cmd'))) {
        Expand-Archive -LiteralPath $fp.Path -DestinationPath $extractDir -Force
    }
    Set-WinMintUupConvertConfigPolicy -Path (Join-Path $extractDir 'ConvertConfig.ini')

    $cmdPath = Join-Path $extractDir 'uup_download_windows.cmd'
    $stdout = Join-Path $logDir 'uup_download_stdout.log'
    $stderr = Join-Path $logDir 'uup_download_stderr.log'
    $progressLog = Join-Path $logDir 'uup_progress.jsonl'
    Set-WinMintHeadlessJournalPhase -Phase 'PrepareSource'
    $proc = Start-Process -FilePath $env:ComSpec -ArgumentList @('/c', "`"$cmdPath`"") -WorkingDirectory $extractDir -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    Wait-WinMintUupDumpProcess -Process $proc -WorkDir $extractDir -ProgressLogPath $progressLog
    if ($proc.ExitCode -ne 0) {
        throw "UUP Dump conversion failed with exit code $($proc.ExitCode). Logs: $logDir"
    }

    $iso = Get-WinMintPreparedUupIso -WorkDir $extractDir
    if ([string]::IsNullOrWhiteSpace($iso)) {
        throw "UUP Dump conversion completed but no ISO was found under $extractDir."
    }

    [pscustomobject]@{
        SourceKind = 'UupDumpZip'
        UupDumpZip = $fp.Path
        UupDumpHash = $fp.Hash
        WorkDir = $workDir
        GeneratedIso = $iso
        Reused = $false
        RanConversion = $true
        Logs = $logDir
        ProgressLog = $progressLog
    }
}
