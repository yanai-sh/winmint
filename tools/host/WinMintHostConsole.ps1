#requires -Version 7.6
# Host console resolve/spawn (wt, pwsh). Not progress formatting.

Set-StrictMode -Version Latest

function Resolve-WinMintWindowsTerminal {
    # Prefer real install over WindowsApps app-execution alias (often 0-byte stub → "cannot be accessed").
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @(
            (Join-Path $env:ProgramFiles 'Windows Terminal\wt.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Windows Terminal\wt.exe')
        )) {
        if (-not [string]::IsNullOrWhiteSpace($p)) { [void]$candidates.Add($p) }
    }
    # Store package: alias is 0 bytes; real binary lives under InstallLocation.
    foreach ($pkg in @(Get-AppxPackage -Name 'Microsoft.WindowsTerminal*' -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace([string]$pkg.InstallLocation)) { continue }
        [void]$candidates.Add((Join-Path $pkg.InstallLocation 'wt.exe'))
    }
    $cmd = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { [void]$candidates.Add([string]$cmd.Source) }
    [void]$candidates.Add((Join-Path $env:LocalAppData 'Microsoft\WindowsApps\wt.exe'))
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        $item = Get-Item -LiteralPath $candidate -ErrorAction SilentlyContinue
        # App execution aliases are 0-byte reparse points until the Store app is present.
        if ($null -eq $item -or $item.Length -lt 1024) { continue }
        return $candidate
    }
    return ''
}

function Get-WinMintHostConsoleWorkRoot {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $Work,
        [string] $TranscriptPath = ''
    )
    if (-not [string]::IsNullOrWhiteSpace($TranscriptPath)) {
        return (Split-Path -Parent $TranscriptPath)
    }
    if ([System.IO.Path]::IsPathRooted($Work)) { return $Work }
    return (Join-Path $RepoRoot ($Work -replace '/', '\'))
}

function Get-WinMintHostConsoleTranscriptPath {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [string] $TranscriptPath = ''
    )
    if (-not [string]::IsNullOrWhiteSpace($TranscriptPath)) { return $TranscriptPath }
    return (Join-Path $RepoRoot '.scratch\smoke\elevated-smoke.log')
}

function Test-WinMintHostConsoleTranscriptLocked {
    param([Parameter(Mandatory)] [string] $TranscriptPath)
    if (-not (Test-Path -LiteralPath $TranscriptPath -PathType Leaf)) { return $false }
    try {
        $fs = [System.IO.File]::Open(
            $TranscriptPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None)
        $fs.Dispose()
        return $false
    }
    catch {
        return $true
    }
}

function Write-WinMintHostConsoleSpawnSidecar {
    param(
        [Parameter(Mandatory)] [string] $SidecarPath,
        [Parameter(Mandatory)] [psobject] $Result
    )
    $dir = Split-Path -Parent $SidecarPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $payload = [ordered]@{
        utc            = [DateTimeOffset]::UtcNow.ToString('o')
        spawnMode      = $Result.spawnMode
        wtResolvedPath = $Result.wtResolvedPath
        childPid       = $Result.childPid
        outcome        = $Result.outcome
        disposition    = $Result.disposition
        detail         = $Result.detail
    }
    ($payload | ConvertTo-Json -Compress) | Set-Content -LiteralPath $SidecarPath -Encoding utf8
}

function Test-WinMintHostConsoleOverlapAlive {
    param([Parameter(Mandatory)] [string] $SidecarPath)
    if (-not (Test-Path -LiteralPath $SidecarPath -PathType Leaf)) { return $false }
    try {
        $raw = Get-Content -LiteralPath $SidecarPath -Raw -Encoding utf8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $false }
        $doc = $raw | ConvertFrom-Json
        $workerPid = [int]$doc.childPid
        if ($workerPid -le 0) { return $false }
        return $null -ne (Get-Process -Id $workerPid -ErrorAction SilentlyContinue)
    }
    catch {
        return $false
    }
}

function Invoke-WinMintHostConsoleProcessStart {
    param(
        [Parameter(Mandatory)] [System.Diagnostics.ProcessStartInfo] $StartInfo,
        [scriptblock] $ProcessStarter
    )
    if ($ProcessStarter) {
        return & $ProcessStarter $StartInfo
    }
    return [System.Diagnostics.Process]::Start($StartInfo)
}

function New-WinMintHostConsolePsi {
    param(
        [Parameter(Mandatory)] [string] $FileName,
        [Parameter(Mandatory)] [string[]] $ArgumentList,
        [Parameter(Mandatory)] [string] $WorkingDirectory
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FileName
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    foreach ($a in $ArgumentList) { [void]$psi.ArgumentList.Add([string]$a) }
    return $psi
}

function Complete-WinMintHostConsoleResult {
    param(
        [Parameter(Mandatory)] [string] $SidecarPath,
        [Parameter(Mandatory)] [pscustomobject] $Result
    )
    Write-WinMintHostConsoleSpawnSidecar -SidecarPath $SidecarPath -Result $Result
    if ($Result.outcome -cne 'ok') {
        throw "$($Result.outcome): $($Result.detail)"
    }
    return $Result
}

function Start-WinMintHostConsole {
    [CmdletBinding(DefaultParameterSetName = 'Watch')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Elevate')]
        [switch] $Elevate,

        [Parameter(Mandatory, ParameterSetName = 'Watch')]
        [Parameter(Mandatory, ParameterSetName = 'Elevate')]
        [string] $RepoRoot,

        [Parameter(Mandatory, ParameterSetName = 'Watch')]
        [Parameter(Mandatory, ParameterSetName = 'Elevate')]
        [string] $Work,

        [Parameter(Mandatory, ParameterSetName = 'Watch')]
        [ValidateSet('smoke', 'check', 'apply')]
        [string] $Kind,

        [Parameter(ParameterSetName = 'Watch')]
        [string] $PriorRunId = '',

        [Parameter(Mandatory, ParameterSetName = 'Watch')]
        [string] $MarkerPath,

        [Parameter(Mandatory, ParameterSetName = 'Watch')]
        [Parameter(Mandatory, ParameterSetName = 'Elevate')]
        [string] $PwshExe,

        [Parameter(Mandatory, ParameterSetName = 'Elevate')]
        [string] $File,

        [Parameter(Mandatory, ParameterSetName = 'Elevate')]
        [string[]] $ArgumentList,

        [Parameter(ParameterSetName = 'Elevate')]
        [string] $TranscriptPath = '',

        [Parameter(ParameterSetName = 'Elevate')]
        [string] $Title = '',

        [Parameter(ParameterSetName = 'Watch')]
        [Parameter(ParameterSetName = 'Elevate')]
        [scriptblock] $ProcessStarter
    )

    if ($PSCmdlet.ParameterSetName -eq 'Elevate') {
        $workRoot = Get-WinMintHostConsoleWorkRoot -RepoRoot $RepoRoot -Work $Work -TranscriptPath $TranscriptPath
        $sidecar = Join-Path $workRoot 'host-console-spawn.json'
        $logPath = Get-WinMintHostConsoleTranscriptPath -RepoRoot $RepoRoot -TranscriptPath $TranscriptPath

        if (Test-WinMintHostConsoleTranscriptLocked -TranscriptPath $logPath) {
            $bad = [pscustomobject]@{
                spawnMode      = 'here'
                wtResolvedPath = ''
                childPid       = $null
                outcome        = 'transcriptLocked'
                disposition    = 'RunHere'
                detail         = $logPath
            }
            return Complete-WinMintHostConsoleResult -SidecarPath $sidecar -Result $bad
        }
        if (Test-WinMintHostConsoleOverlapAlive -SidecarPath $sidecar) {
            $bad = [pscustomobject]@{
                spawnMode      = 'here'
                wtResolvedPath = ''
                childPid       = $null
                outcome        = 'overlapAlive'
                disposition    = 'RunHere'
                detail         = $sidecar
            }
            return Complete-WinMintHostConsoleResult -SidecarPath $sidecar -Result $bad
        }

        $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
        $inWt = -not [string]::IsNullOrWhiteSpace([string]$env:WT_SESSION)
        $wt = Resolve-WinMintWindowsTerminal
        $elevTitle = if ([string]::IsNullOrWhiteSpace($Title)) { "WinMint smoke elevated — $Work" } else { $Title }
        $cwd = $RepoRoot

        if ($admin -and $inWt) {
            $ok = [pscustomobject]@{
                spawnMode      = 'alreadyInWt'
                wtResolvedPath = $wt
                childPid       = $null
                outcome        = 'ok'
                disposition    = 'RunHere'
                detail         = ''
            }
            return Complete-WinMintHostConsoleResult -SidecarPath $sidecar -Result $ok
        }

        if ($admin -and -not $inWt -and -not $wt) {
            $ok = [pscustomobject]@{
                spawnMode      = 'conhostInPlace'
                wtResolvedPath = ''
                childPid       = $null
                outcome        = 'ok'
                disposition    = 'RunHere'
                detail         = ''
            }
            return Complete-WinMintHostConsoleResult -SidecarPath $sidecar -Result $ok
        }

        $pwshArgs = @('-NoProfile', '-File', $File) + $ArgumentList

        if ($admin -and $wt -and -not $inWt) {
            $spawnMode = 'wtNewWindow'
            $fileName = $wt
            $spawnArgs = @(
                '-w', '0', 'new-tab', '--title', $elevTitle, '-d', $cwd, '--',
                $PwshExe
            ) + $pwshArgs
        }
        elseif (-not $admin -and $wt) {
            $spawnMode = 'sudoWt'
            $fileName = 'sudo'
            $spawnArgs = @(
                '-E', $wt,
                '-w', '0', 'new-tab', '--title', $elevTitle, '-d', $cwd, '--',
                $PwshExe
            ) + $pwshArgs
        }
        elseif (-not $admin) {
            $spawnMode = 'sudoPwsh'
            $fileName = 'sudo'
            $spawnArgs = @('-E', $PwshExe) + $pwshArgs
        }
        else {
            throw 'Start-WinMintHostConsole -Elevate: unreachable matrix branch'
        }

        if ([string]::IsNullOrWhiteSpace($fileName)) {
            $bad = [pscustomobject]@{
                spawnMode      = $spawnMode
                wtResolvedPath = $wt
                childPid       = $null
                outcome        = 'resolveEmpty'
                disposition    = 'Spawned'
                detail         = 'spawn executable empty'
            }
            return Complete-WinMintHostConsoleResult -SidecarPath $sidecar -Result $bad
        }

        try {
            $psi = New-WinMintHostConsolePsi -FileName $fileName -ArgumentList $spawnArgs -WorkingDirectory $cwd
            $proc = Invoke-WinMintHostConsoleProcessStart -StartInfo $psi -ProcessStarter $ProcessStarter
            $childPid = if ($null -eq $proc) { 0 } else { [int]$proc.Id }
            if ($childPid -le 0) {
                $bad = [pscustomobject]@{
                    spawnMode      = $spawnMode
                    wtResolvedPath = $wt
                    childPid       = $null
                    outcome        = 'startThrew'
                    disposition    = 'Spawned'
                    detail         = 'Process.Start returned no PID'
                }
                return Complete-WinMintHostConsoleResult -SidecarPath $sidecar -Result $bad
            }
            $ok = [pscustomobject]@{
                spawnMode      = $spawnMode
                wtResolvedPath = $wt
                childPid       = $childPid
                outcome        = 'ok'
                disposition    = 'Spawned'
                detail         = ''
            }
            return Complete-WinMintHostConsoleResult -SidecarPath $sidecar -Result $ok
        }
        catch {
            $bad = [pscustomobject]@{
                spawnMode      = $spawnMode
                wtResolvedPath = $wt
                childPid       = $null
                outcome        = 'startThrew'
                disposition    = 'Spawned'
                detail         = $_.Exception.Message
            }
            return Complete-WinMintHostConsoleResult -SidecarPath $sidecar -Result $bad
        }
    }

    $watchScript = Join-Path $RepoRoot 'tools/host/Watch-Host.ps1'
    $title = "WinMint host watch — $Work"
    # Watch redraws an interactive console — not -NonInteractive.
    $pwshArgs = @(
        '-NoProfile', '-File', $watchScript,
        '-Kind', $Kind, '-Work', $Work, '-MarkerPath', $MarkerPath
    )
    if ($PSBoundParameters.ContainsKey('PriorRunId')) {
        # One argv token so an empty prior id survives wt/-- forwarding (bare "" is dropped).
        $pwshArgs += "-PriorRunId:$PriorRunId"
    }
    $wt = Resolve-WinMintWindowsTerminal
    if ($wt) {
        # -w 0: new window (elevated smoke must not rely on attaching to an existing tab).
        # ProcessStartInfo.ArgumentList: Start-Process joins with spaces and does not quote;
        # wt then treats the second word of --title ("host") as the executable → 0x80070002.
        $wtArgs = @(
            '-w', '0',
            'new-tab',
            '--title', $title,
            '-d', $RepoRoot,
            '--',
            $PwshExe
        ) + $pwshArgs
        try {
            $psi = New-WinMintHostConsolePsi -FileName $wt -ArgumentList $wtArgs -WorkingDirectory $RepoRoot
            $proc = Invoke-WinMintHostConsoleProcessStart -StartInfo $psi -ProcessStarter $ProcessStarter
            $childPid = [int]$proc.Id
            # ponytail: poll up to 5s for Watch self-stamp; Stopwatch (not UtcNow) — host clock can jump.
            $wait = [Diagnostics.Stopwatch]::StartNew()
            while ($wait.Elapsed.TotalSeconds -lt 5) {
                if (Test-Path -LiteralPath $MarkerPath -PathType Leaf) {
                    $markerPid = 0
                    $raw = (Get-Content -LiteralPath $MarkerPath -Raw -ErrorAction SilentlyContinue)
                    if ($raw -and [int]::TryParse($raw.Trim(), [ref]$markerPid) -and $markerPid -gt 0) {
                        if ($null -ne (Get-Process -Id $markerPid -ErrorAction SilentlyContinue)) {
                            return [pscustomobject]@{
                                spawnMode      = 'wtNewWindow'
                                wtResolvedPath = $wt
                                childPid       = $childPid
                                outcome        = 'ok'
                                disposition    = 'Spawned'
                                detail         = ''
                            }
                        }
                    }
                }
                Start-Sleep -Milliseconds 200
            }
            $bad = [pscustomobject]@{
                spawnMode      = 'wtNewWindow'
                wtResolvedPath = $wt
                childPid       = $childPid
                outcome        = 'watchMarkerTimeout'
                disposition    = 'Spawned'
                detail         = $MarkerPath
            }
            throw "$($bad.outcome): $($bad.detail)"
        }
        catch {
            if ($_.Exception.Message -match '^watchMarkerTimeout:') { throw }
            # Broken wt alias / ACL — fall through to pwsh console watch.
            Write-Debug "wt spawn failed: $($_.Exception.Message)"
        }
    }
    try {
        $psi = New-WinMintHostConsolePsi -FileName $PwshExe -ArgumentList $pwshArgs -WorkingDirectory $RepoRoot
        $proc = Invoke-WinMintHostConsoleProcessStart -StartInfo $psi -ProcessStarter $ProcessStarter
        Set-Content -LiteralPath $MarkerPath -Value $proc.Id -Encoding utf8
        return [pscustomobject]@{
            spawnMode      = 'here'
            wtResolvedPath = ''
            childPid       = $proc.Id
            outcome        = 'ok'
            disposition    = 'Spawned'
            detail         = ''
        }
    }
    catch {
        $bad = [pscustomobject]@{
            spawnMode      = 'here'
            wtResolvedPath = ''
            childPid       = $null
            outcome        = 'startThrew'
            disposition    = 'Spawned'
            detail         = $_.Exception.Message
        }
        throw "$($bad.outcome): $($bad.detail)"
    }
}

function Start-WinMintHostWatchProcess {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $Work,
        [Parameter(Mandatory)] [ValidateSet('smoke', 'check', 'apply')] [string] $Kind,
        [string] $PriorRunId = '',
        [Parameter(Mandatory)] [string] $MarkerPath,
        [Parameter(Mandatory)] [string] $PwshExe
    )
    $splat = @{
        RepoRoot   = $RepoRoot
        Work       = $Work
        Kind       = $Kind
        MarkerPath = $MarkerPath
        PwshExe    = $PwshExe
    }
    if ($PSBoundParameters.ContainsKey('PriorRunId')) {
        $splat.PriorRunId = $PriorRunId
    }
    [void](Start-WinMintHostConsole @splat)
}
