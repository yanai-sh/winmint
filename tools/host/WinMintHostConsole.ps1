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

function Start-WinMintHostConsole {
    [CmdletBinding(DefaultParameterSetName = 'Watch')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Watch')]
        [Parameter(Mandatory, ParameterSetName = 'Argv')]
        [string] $RepoRoot,

        [Parameter(Mandatory, ParameterSetName = 'Watch')]
        [string] $Work,

        [Parameter(Mandatory, ParameterSetName = 'Watch')]
        [ValidateSet('smoke', 'check', 'apply')]
        [string] $Kind,

        [Parameter(ParameterSetName = 'Watch')]
        [string] $PriorRunId = '',

        [Parameter(Mandatory, ParameterSetName = 'Watch')]
        [string] $MarkerPath,

        [Parameter(Mandatory, ParameterSetName = 'Watch')]
        [string] $PwshExe,

        [Parameter(Mandatory, ParameterSetName = 'Argv')]
        [string] $FileName,

        [Parameter(Mandatory, ParameterSetName = 'Argv')]
        [string[]] $ArgumentList,

        [Parameter(ParameterSetName = 'Argv')]
        [string] $WorkingDirectory = ''
    )

    if ($PSCmdlet.ParameterSetName -eq 'Argv') {
        $cwd = if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) { $RepoRoot } else { $WorkingDirectory }
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $FileName
        $psi.WorkingDirectory = $cwd
        $psi.UseShellExecute = $false
        foreach ($a in $ArgumentList) { [void]$psi.ArgumentList.Add([string]$a) }
        $proc = [System.Diagnostics.Process]::Start($psi)
        return [pscustomobject]@{
            disposition    = 'Spawned'
            childPid       = $proc.Id
            wtResolvedPath = ''
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
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = $wt
            $psi.WorkingDirectory = $RepoRoot
            $psi.UseShellExecute = $false
            foreach ($a in $wtArgs) { [void]$psi.ArgumentList.Add([string]$a) }
            $proc = [System.Diagnostics.Process]::Start($psi)
            # ponytail: poll up to 5s for Watch self-stamp; Stopwatch (not UtcNow) — host clock can jump.
            $wait = [Diagnostics.Stopwatch]::StartNew()
            while ($wait.Elapsed.TotalSeconds -lt 5) {
                if (Test-Path -LiteralPath $MarkerPath -PathType Leaf) {
                    $markerPid = 0
                    $raw = (Get-Content -LiteralPath $MarkerPath -Raw -ErrorAction SilentlyContinue)
                    if ($raw -and [int]::TryParse($raw.Trim(), [ref]$markerPid) -and $markerPid -gt 0) {
                        if ($null -ne (Get-Process -Id $markerPid -ErrorAction SilentlyContinue)) {
                            return [pscustomobject]@{
                                disposition    = 'Spawned'
                                childPid       = $proc.Id
                                wtResolvedPath = $wt
                            }
                        }
                    }
                }
                Start-Sleep -Milliseconds 200
            }
            return [pscustomobject]@{
                disposition    = 'Spawned'
                childPid       = $proc.Id
                wtResolvedPath = $wt
            }
        }
        catch {
            # Broken wt alias / ACL — fall through to pwsh console watch.
            Write-Debug "wt spawn failed: $($_.Exception.Message)"
        }
    }
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $PwshExe
    $psi.WorkingDirectory = $RepoRoot
    $psi.UseShellExecute = $false
    foreach ($a in $pwshArgs) { [void]$psi.ArgumentList.Add([string]$a) }
    $proc = [System.Diagnostics.Process]::Start($psi)
    Set-Content -LiteralPath $MarkerPath -Value $proc.Id -Encoding utf8
    return [pscustomobject]@{
        disposition    = 'Spawned'
        childPid       = $proc.Id
        wtResolvedPath = ''
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
