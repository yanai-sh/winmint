#requires -Version 7.6
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$smoke = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Invoke-Smoke.ps1') -Raw -Encoding utf8
if ($smoke -notmatch 'WinMintSmokeApplyJob\.ps1') {
    throw 'Invoke-Smoke must dot-source WinMintSmokeApplyJob.ps1'
}
if ($smoke -notmatch 'Invoke-WinMintSmokeApplyMaintainer') {
    throw 'Invoke-Smoke must Apply via Invoke-WinMintSmokeApplyMaintainer (job-wrapped just apply-smoke-maintainer)'
}
if ($smoke -match '&\s+just\s+apply-smoke-maintainer') {
    throw 'Invoke-Smoke must not call just apply-smoke-maintainer directly (use job wrapper)'
}
if ($smoke -notmatch 'discard-stale-mount') {
    throw 'Invoke-Smoke Apply spawn must document discard-stale-mount for hard-kill mid-DISM'
}

foreach ($path in @(
        (Join-Path $repo 'tools/host/WinMintHostConsole.ps1'),
        (Join-Path $repo 'tools/host/Write-WinMintHostProgress.ps1')
    )) {
    $text = Get-Content -LiteralPath $path -Raw -Encoding utf8
    if ($text -match 'AssignProcessToJobObject|WinMintSmokeApplyJob') {
        throw "Watch/host console must not join Smoke Apply job: $path"
    }
}

. (Join-Path $repo 'tools/vm/WinMintSmokeApplyJob.ps1')

$hJob = [WinMintSmokeApplyJobNative]::CreateKillOnCloseJob()
$proc = $null
try {
    $proc = Start-Process -FilePath (Get-Command pwsh.exe -ErrorAction Stop).Source -PassThru -WindowStyle Hidden `
        -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 600')
    [WinMintSmokeApplyJobNative]::AssignProcess($hJob, $proc.Id)
    [WinMintSmokeApplyJobNative]::CloseJob($hJob)
    $hJob = [IntPtr]::Zero

    $deadline = [Environment]::TickCount64 + 15000
    while ([Environment]::TickCount64 -lt $deadline) {
        if ($null -eq (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 200
    }
    if ($null -ne (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        throw 'KILL_ON_JOB_CLOSE did not terminate assigned child after job handle close'
    }
}
finally {
    if ($null -ne $hJob -and $hJob -ne [IntPtr]::Zero) {
        [WinMintSmokeApplyJobNative]::CloseJob($hJob)
    }
    if ($null -ne $proc -and (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}

Write-Output 'Smoke Apply job contract passed.'
