#requires -Version 7.6
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools/host/WinMintHostConsole.ps1')

$script:WinMintHostConsoleSpawnCapture = @{
    FileName     = ''
    ArgumentList = [string[]]@()
    SpawnCount   = 0
}

function Reset-WinMintHostConsoleSpawnCapture {
    $script:WinMintHostConsoleSpawnCapture.FileName = ''
    $script:WinMintHostConsoleSpawnCapture.ArgumentList = [string[]]@()
    $script:WinMintHostConsoleSpawnCapture.SpawnCount = 0
}

function Invoke-WinMintHostConsoleSpawnRecorder {
    param([System.Diagnostics.ProcessStartInfo] $StartInfo)
    $script:WinMintHostConsoleSpawnCapture.FileName = [string]$StartInfo.FileName
    $script:WinMintHostConsoleSpawnCapture.ArgumentList = @(
        foreach ($a in $StartInfo.ArgumentList) { [string]$a })
    $script:WinMintHostConsoleSpawnCapture.SpawnCount++
    return [pscustomobject]@{ Id = $PID }
}

function Assert-WinMintHostConsoleArgvContains {
    param(
        [Parameter(Mandatory)] [string[]] $ArgumentList,
        [Parameter(Mandatory)] [string[]] $Tokens
    )
    foreach ($t in $Tokens) {
        if ($ArgumentList -notcontains $t) {
            throw "spawn argv missing token '$t' (have: $($ArgumentList -join ' | '))"
        }
    }
}

$fakeWt = Join-Path ([IO.Path]::GetTempPath()) ('winmint-fake-wt-' + [guid]::NewGuid().ToString('N') + '.exe')
Set-Content -LiteralPath $fakeWt -Value 'stub' -Encoding ascii -Force
$script:WinMintFakeWtPath = $fakeWt
function Resolve-WinMintWindowsTerminal { return $script:WinMintFakeWtPath }

$pwshExe = (Get-Command pwsh.exe -ErrorAction Stop).Source
$workRoot = Join-Path ([IO.Path]::GetTempPath()) ('winmint-host-console-spawn-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$markerPath = Join-Path $workRoot 'watch-smoke.pid'
Set-Content -LiteralPath $markerPath -Value $PID -Encoding utf8 -NoNewline

try {
    Reset-WinMintHostConsoleSpawnCapture
    $watch = Start-WinMintHostConsole -RepoRoot $repo -Work $workRoot -Kind smoke `
        -PriorRunId '' -MarkerPath $markerPath -PwshExe $pwshExe `
        -ProcessStarter ${function:Invoke-WinMintHostConsoleSpawnRecorder}
    if ($watch.outcome -cne 'ok') { throw "watch spawn outcome $($watch.outcome): $($watch.detail)" }
    Assert-WinMintHostConsoleArgvContains -ArgumentList $script:WinMintHostConsoleSpawnCapture.ArgumentList `
        -Tokens @('-w', '0', '-PriorRunId:')
    if ($script:WinMintHostConsoleSpawnCapture.ArgumentList -contains '-NonInteractive') {
        throw 'watch spawn argv must not include -NonInteractive'
    }
    if ($script:WinMintHostConsoleSpawnCapture.FileName -cne $fakeWt) {
        throw "watch spawn expected fake wt, got $($script:WinMintHostConsoleSpawnCapture.FileName)"
    }

    $elevWork = Join-Path $workRoot 'elev-work'
    New-Item -ItemType Directory -Force -Path $elevWork | Out-Null
    $elevTranscript = Join-Path $elevWork 'elevated-smoke.log'
    $elevFile = Join-Path $repo 'tools\vm\Start-SmokeElevated.ps1'
    Reset-WinMintHostConsoleSpawnCapture
    $savedWtSession = $env:WT_SESSION
    Remove-Item Env:WT_SESSION -ErrorAction SilentlyContinue
    try {
        $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
        $elev = Start-WinMintHostConsole -Elevate -RepoRoot $repo -Work $elevWork `
            -File $elevFile -ArgumentList @('-ElevatedWorker', '-Work', $elevWork) `
            -PwshExe $pwshExe -TranscriptPath $elevTranscript `
            -ProcessStarter ${function:Invoke-WinMintHostConsoleSpawnRecorder}
        if ($elev.disposition -eq 'RunHere') {
            throw 'elevate matrix returned RunHere — clear WT_SESSION and avoid locked default transcript for spawn contract'
        }
        if ($elev.outcome -cne 'ok') { throw "elevate spawn outcome $($elev.outcome): $($elev.detail)" }
        $argv = $script:WinMintHostConsoleSpawnCapture.ArgumentList
        Assert-WinMintHostConsoleArgvContains -ArgumentList $argv -Tokens @('-w', '0')
        if ($admin) {
            if ($script:WinMintHostConsoleSpawnCapture.FileName -cne $fakeWt) {
                throw 'admin elevate must spawn via wt when stub resolves'
            }
        }
        else {
            if ($script:WinMintHostConsoleSpawnCapture.FileName -cne 'sudo') {
                throw 'non-admin elevate must spawn via sudo when wt resolves'
            }
            Assert-WinMintHostConsoleArgvContains -ArgumentList $argv -Tokens @('-E')
        }
    }
    finally {
        if ($null -ne $savedWtSession) { $env:WT_SESSION = $savedWtSession }
    }

    $sidecar = Join-Path $elevWork 'host-console-spawn.json'
    @{
        utc            = [DateTimeOffset]::UtcNow.ToString('o')
        spawnMode      = 'wtNewWindow'
        wtResolvedPath = $fakeWt
        childPid       = $PID
        outcome        = 'ok'
        disposition    = 'Spawned'
        detail         = ''
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath $sidecar -Encoding utf8
    try {
        Start-WinMintHostConsole -Elevate -RepoRoot $repo -Work $elevWork `
            -File $elevFile -ArgumentList @('-ElevatedWorker') -PwshExe $pwshExe `
            -TranscriptPath $elevTranscript `
            -ProcessStarter { throw 'overlap must short-circuit before ProcessStarter' }
        throw 'expected overlapAlive throw'
    }
    catch {
        if ($_.Exception.Message -notmatch '^overlapAlive:') {
            throw "expected overlapAlive, got: $($_.Exception.Message)"
        }
    }

    $startSrc = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Start-SmokeElevated.ps1') -Raw -Encoding utf8
    if ($startSrc -notmatch 'childExitedEarly') {
        throw 'Start-SmokeElevated must throw childExitedEarly when outer starter dies quickly'
    }
}
finally {
    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fakeWt -Force -ErrorAction SilentlyContinue
}

Write-Output 'Test-WinMintHostConsoleSpawn ok'
