#Requires -Version 7.6

function Invoke-AgentNative {
    param([string]$FilePath, [string[]]$ArgumentList)
    if ($script:WinMintAgentNativeHandler) {
        return & $script:WinMintAgentNativeHandler @PSBoundParameters
    }
    $ctx = Get-WinMintAgentContext
    $script:AgentCommandCounter++
    $safeName = ([IO.Path]::GetFileNameWithoutExtension($FilePath) -replace '[^A-Za-z0-9_.-]', '_')
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'command' }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $baseName = '{0:000}-{1}-{2}' -f $script:AgentCommandCounter, $stamp, $safeName
    $stdoutPath = Join-Path $ctx.CommandLogDir "$baseName.out.log"
    $stderrPath = Join-Path $ctx.CommandLogDir "$baseName.err.log"
    Write-AgentLog "RUN $FilePath $($ArgumentList -join ' ')"
    Write-AgentLog "RUNLOG stdout=$stdoutPath stderr=$stderrPath"
    $displayArgs = $ArgumentList -join ' '
    if ($displayArgs.Length -gt 120) { $displayArgs = $displayArgs.Substring(0, 117) + '...' }
    Write-AgentEvent -Type 'command' -Status 'running' -Message "Running $([IO.Path]::GetFileName($FilePath))." -Data @{
        filePath = $FilePath
        stdout = $stdoutPath
        stderr = $stderrPath
        displayArgs = $displayArgs
    }
    # WinMint's first-logon host self-elevates before the agent runs, so package
    # installs should execute under that full admin token rather than being
    # bounced through a second limited-user task. That extra hop was brittle and
    # produced "Access is denied" failures on winget-backed installs.
    $p = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -ErrorAction Stop
    $exitCode = [int]$p.ExitCode
    if ($exitCode -ne 0) {
        $stdoutTail = @()
        $stderrTail = @()
        try { if (Test-Path -LiteralPath $stdoutPath) { $stdoutTail = @(Get-Content -LiteralPath $stdoutPath -Tail 20 -ErrorAction SilentlyContinue) } } catch {}
        try { if (Test-Path -LiteralPath $stderrPath) { $stderrTail = @(Get-Content -LiteralPath $stderrPath -Tail 20 -ErrorAction SilentlyContinue) } } catch {}
        $details = [System.Collections.Generic.List[string]]::new()
        if ($stdoutTail.Count -gt 0) {
            $details.Add("stdout:") | Out-Null
            foreach ($line in @($stdoutTail)) { $details.Add([string]$line) | Out-Null }
        }
        if ($stderrTail.Count -gt 0) {
            if ($details.Count -gt 0) { $details.Add('') | Out-Null }
            $details.Add("stderr:") | Out-Null
            foreach ($line in @($stderrTail)) { $details.Add([string]$line) | Out-Null }
        }
        Write-AgentEvent -Type 'command' -Status 'failed' -Message "$([IO.Path]::GetFileName($FilePath)) exited $exitCode." -Data @{
            filePath = $FilePath
            exitCode = $exitCode
            stdout = $stdoutPath
            stderr = $stderrPath
        }
        $message = "$FilePath exited $exitCode. Logs: $stdoutPath $stderrPath"
        if ($details.Count -gt 0) {
            $message += [Environment]::NewLine + ($details -join [Environment]::NewLine)
        }
        throw $message
    }
    Write-AgentEvent -Type 'command' -Status 'ok' -Message "$([IO.Path]::GetFileName($FilePath)) completed." -Data @{
        filePath = $FilePath
        exitCode = $exitCode
        stdout = $stdoutPath
        stderr = $stderrPath
    }
}

function Get-WingetPath {
    if ($script:WinMintWingetPathOverride) { return [string]$script:WinMintWingetPathOverride }

    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }

    foreach ($candidate in @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'),
            (Join-Path $env:USERPROFILE 'AppData\Local\Microsoft\WindowsApps\winget.exe')
        )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }

    if ($script:WinMintAgentFastWaits) { return $null }

    $pkg = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg -and $pkg.InstallLocation) {
        $manifest = Join-Path $pkg.InstallLocation 'AppxManifest.xml'
        if (Test-Path -LiteralPath $manifest -PathType Leaf) {
            try {
                Add-AppxPackage -Register $manifest -DisableDevelopmentMode -ErrorAction Stop
                Start-Sleep -Seconds 2
            }
            catch {
                Write-AgentLog "winget alias registration warning: $($_.Exception.Message)"
            }
        }
    }

    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return $null
}

function Wait-WingetPath {
    $attempts = if ($script:WinMintAgentFastWaits) { 1 } else { 24 }
    for ($i = 0; $i -lt $attempts; $i++) {
        $p = Get-WingetPath
        if ($p) { return $p }
        if (-not $script:WinMintAgentFastWaits) { Start-Sleep -Seconds 5 }
    }
    return $null
}

function Get-ScoopPath {
    if ($script:WinMintScoopPathOverride) { return [string]$script:WinMintScoopPathOverride }

    $cmd = Get-Command scoop -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }

    foreach ($candidate in @(
            (Join-Path $env:USERPROFILE 'scoop\shims\scoop.ps1'),
            (Join-Path $env:USERPROFILE 'scoop\shims\scoop.cmd')
        )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Wait-ScoopPath {
    $attempts = if ($script:WinMintAgentFastWaits) { 1 } else { 12 }
    for ($i = 0; $i -lt $attempts; $i++) {
        Update-AgentProcessPath
        $p = Get-ScoopPath
        if ($p) { return $p }
        if (-not $script:WinMintAgentFastWaits) { Start-Sleep -Seconds 5 }
    }
    return $null
}

function Get-AgentDirectToolCachePath {
    param([Parameter(Mandatory)]$Tool)

    $cacheRoot = Join-Path $env:LOCALAPPDATA 'WinMint\Cache\Packages'
    $null = New-Item -ItemType Directory -Path $cacheRoot -Force -ErrorAction Stop
    $fileName = [IO.Path]::GetFileName(([Uri][string]$Tool.url).AbsolutePath)
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = ([string]$Tool.id -replace '[^A-Za-z0-9_.-]', '_') + '.exe'
    }
    return (Join-Path $cacheRoot $fileName)
}

function Save-AgentDirectToolInstaller {
    param([Parameter(Mandatory)]$Tool)

    $url = [string]$Tool.url
    $expectedHash = ([string]$Tool.sha256).ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($expectedHash)) {
        throw "Direct package '$($Tool.id)' is missing url or sha256 metadata."
    }

    $installerPath = Get-AgentDirectToolCachePath -Tool $Tool
    $needsDownload = $true
    if (Test-Path -LiteralPath $installerPath -PathType Leaf) {
        $existingHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToUpperInvariant()
        if ($existingHash -eq $expectedHash) {
            $needsDownload = $false
        }
        else {
            Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        }
    }

    if ($needsDownload) {
        Write-AgentEvent -Type 'download' -Status 'running' -Message "Downloading $($Tool.id)." -Data @{ toolId = [string]$Tool.id }
    }

    if ($needsDownload) {
        Invoke-WebRequest -Uri $url -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
        Write-AgentEvent -Type 'download' -Status 'ok' -Message "Downloaded $($Tool.id)." -Data @{ toolId = [string]$Tool.id }
    }

    $actualHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualHash -ne $expectedHash) {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        throw "Direct package '$($Tool.id)' SHA256 mismatch. Expected $expectedHash; got $actualHash."
    }

    return [pscustomobject]@{
        Path = $installerPath
        Url = $url
        Version = [string]$Tool.version
        Sha256 = $expectedHash
    }
}

function Invoke-AgentScoop {
    param([Parameter(Mandatory)][string[]]$ArgumentList)

    $scoop = Wait-ScoopPath
    if (-not $scoop) { throw 'scoop command not available after wait.' }
    $extension = [IO.Path]::GetExtension($scoop)
    if ($extension -ieq '.ps1') {
        $ps = Resolve-AgentPowerShellHost
        Invoke-AgentNative -FilePath $ps -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scoop) + $ArgumentList)
        return
    }
    Invoke-AgentNative -FilePath $scoop -ArgumentList $ArgumentList
}

function Install-AgentScoop {
    param([hashtable]$State)

    $key = 'package-manager:scoop'
    if (-not (Get-WinMintAgentContext).Force -and $State.ContainsKey('steps') -and $State.steps.ContainsKey($key) -and [string]$State.steps[$key].status -eq 'ok') {
        Write-AgentEvent -Type 'notice' -Status 'ok' -Message 'Scoop already installed.'
        return
    }

    if (Get-ScoopPath) {
        $State.steps[$key] = @{ status = 'ok'; updatedAt = (Get-Date -Format o); source = 'existing' }
        Save-AgentState -State $State
        return
    }

    $installerPath = Join-Path $env:TEMP 'WinMint-Scoop-Install.ps1'
    Invoke-WebRequest -Uri 'https://get.scoop.sh' -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
    $ps = Resolve-AgentPowerShellHost
    Invoke-AgentNative -FilePath $ps -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $installerPath,
        '-RunAsAdmin'
    )
    Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    Update-AgentProcessPath
    if (-not (Wait-ScoopPath)) { throw 'Scoop installer completed, but scoop was not found on PATH.' }
    $State.steps[$key] = @{ status = 'ok'; updatedAt = (Get-Date -Format o); source = 'https://get.scoop.sh' }
    Save-AgentState -State $State
}

function Install-AgentTool {
    param($Tool, [hashtable]$State)
    $key = "tool:$($Tool.id)"
    $hostArch = Get-AgentProcessorArchitecture
    $targetArch = Get-AgentTargetArchitecture
    $directPayload = $null
    if (-not (Get-WinMintAgentContext).Force -and $State.steps.ContainsKey($key) -and $State.steps[$key].status -eq 'ok') {
        Write-AgentLog "SKIP $key already ok"
        Write-AgentEvent -Type 'notice' -Status 'ok' -Message "$($Tool.id) already installed."
        return
    }
    try {
        Write-AgentEvent -Type 'install' -Status 'running' -Step $key -Message "Installing $($Tool.id) for $targetArch." -Data @{
            toolId = [string]$Tool.id
            architecture = $targetArch
        }
        if ($Tool.PSObject.Properties['architectures']) {
            $supported = @($Tool.architectures | ForEach-Object { ([string]$_).ToLowerInvariant() })
            if ($supported.Count -gt 0 -and $supported -notcontains $targetArch) {
                $State.steps[$key] = @{
                    status = 'skipped'
                    updatedAt = (Get-Date -Format o)
                    architecture = $targetArch
                    reason = "Unsupported architecture: $targetArch"
                }
                Save-AgentState -State $State
                Write-AgentEvent -Type 'step' -Status 'skipped' -Step $key -Message "$($Tool.id) is not available for $targetArch."
                Write-AgentLog "SKIP $key unsupported architecture $targetArch"
                return
            }
        }
        $versionPolicy = if ($Tool.PSObject.Properties['versionPolicy']) { [string]$Tool.versionPolicy } else { 'latest' }
        $requestedVersion = if ($Tool.PSObject.Properties['version']) { [string]$Tool.version } else { '' }
        switch ($Tool.source) {
            'winget' {
                $winget = Wait-WingetPath
                if (-not $winget) { throw 'winget.exe not available after wait.' }
                $installArgs = @(
                    'install', '--exact', '--id', $Tool.id, '--source', 'winget', '--silent',
                    '--accept-source-agreements', '--accept-package-agreements'
                )
                $wingetArchitecture = Get-AgentToolWingetArchitecture -Tool $Tool -HostArchitecture $hostArch -TargetArchitecture $targetArch
                if ($wingetArchitecture) {
                    $installArgs += @('--architecture', $wingetArchitecture)
                }
                if ($versionPolicy -ne 'latest' -and -not [string]::IsNullOrWhiteSpace($requestedVersion)) {
                    $installArgs += @('--version', $requestedVersion)
                }
                Invoke-AgentNative -FilePath $winget -ArgumentList $installArgs
                Update-AgentProcessPath
            }
            'store' {
                $winget = Wait-WingetPath
                if (-not $winget) { throw 'winget.exe not available after wait.' }
                $installArgs = @(
                    'install', '--exact', '--id', $Tool.id, '--source', 'msstore', '--silent',
                    '--accept-source-agreements', '--accept-package-agreements'
                )
                $wingetArchitecture = Get-AgentToolWingetArchitecture -Tool $Tool -HostArchitecture $hostArch -TargetArchitecture $targetArch
                if ($wingetArchitecture) {
                    $installArgs += @('--architecture', $wingetArchitecture)
                }
                if ($versionPolicy -ne 'latest' -and -not [string]::IsNullOrWhiteSpace($requestedVersion)) {
                    $installArgs += @('--version', $requestedVersion)
                }
                Invoke-AgentNative -FilePath $winget -ArgumentList $installArgs
                Update-AgentProcessPath
            }
            'scoop' {
                Install-AgentScoop -State $State
                $installArgs = @('install', $Tool.id)
                if ($versionPolicy -ne 'latest' -and -not [string]::IsNullOrWhiteSpace($requestedVersion)) {
                    $installArgs = @('install', "$($Tool.id)@$requestedVersion")
                }
                if ($targetArch -eq 'arm64') {
                    Write-AgentLog "Scoop install for $($Tool.id): target architecture is arm64; relying on Scoop manifest architecture selection for native ARM64/aarch64 assets where available."
                }
                Invoke-AgentScoop -ArgumentList $installArgs
                Update-AgentProcessPath
            }
            'direct' {
                $directPayload = Save-AgentDirectToolInstaller -Tool $Tool
                $installArgs = @()
                if ($Tool.PSObject.Properties['silentArgs']) {
                    $installArgs = @($Tool.silentArgs | ForEach-Object { [string]$_ })
                }
                Invoke-AgentNative -FilePath ([string]$directPayload.Path) -ArgumentList $installArgs
                Update-AgentProcessPath
            }
            default {
                # WinMint installs tools through explicit package-manager owners:
                # winget/msstore for GUI/system apps, Scoop for developer CLIs,
                # and a narrow hash-pinned direct installer exception.
                throw "Unsupported install source '$($Tool.source)' for tool '$($Tool.id)'. WinMint only supports the 'winget', 'store', 'scoop', and approved 'direct' install sources."
            }
        }
        $record = @{
            status = 'ok'
            updatedAt = (Get-Date -Format o)
            architecture = $targetArch
        }
        if ($null -ne $directPayload) {
            $record.source = 'direct'
            $record.url = [string]$directPayload.Url
            $record.version = [string]$directPayload.Version
            $record.sha256 = [string]$directPayload.Sha256
            $record.path = [string]$directPayload.Path
        }
        $State.steps[$key] = $record
        Save-AgentState -State $State
        Write-AgentEvent -Type 'step' -Status 'ok' -Step $key -Message "$($Tool.id) installed." -Data @{
            architecture = $targetArch
            hostArchitecture = $hostArch
        }
    } catch {
        $State.steps[$key] = @{
            status = 'failed'
            updatedAt = (Get-Date -Format o)
            architecture = $targetArch
            hostArchitecture = $hostArch
            error = $_.Exception.Message
        }
        Save-AgentState -State $State
        Write-AgentEvent -Type 'step' -Status 'failed' -Step $key -Message "$($Tool.id) failed." -Data @{
            architecture = $targetArch
            hostArchitecture = $hostArch
            error = $_.Exception.Message
        }
        Write-AgentLog "FAIL $key :: $($_.Exception.Message)"
    }
}

function Get-AgentManifestTool {
    param(
        [Parameter(Mandatory)][string]$ToolId
    )

    $manifest = (Get-WinMintAgentContext).Manifest
    if (-not $manifest -or -not $manifest.PSObject.Properties['tools']) {
        throw 'packages.json does not contain a tools manifest.'
    }
    $property = $manifest.tools.PSObject.Properties[$ToolId]
    if (-not $property) {
        throw "Tool '$ToolId' is not defined in packages.json."
    }

    return $property.Value
}

function Get-AgentManifestToolStateKey {
    param(
        [Parameter(Mandatory)][string]$ToolId
    )

    $tool = Get-AgentManifestTool -ToolId $ToolId
    return "tool:$([string]$tool.id)"
}

function Install-AgentManifestTool {
    param(
        [Parameter(Mandatory)][string]$ToolId,
        [Parameter(Mandatory)][hashtable]$State
    )

    $tool = Get-AgentManifestTool -ToolId $ToolId
    Install-AgentTool -Tool $tool -State $State
    $key = Get-AgentManifestToolStateKey -ToolId $ToolId
    if (-not $State.steps.ContainsKey($key)) {
        throw "Tool '$ToolId' did not record install state."
    }
    $status = [string]$State.steps[$key].status
    if ($status -ne 'ok') {
        $reason = if ($State.steps[$key].error) {
            [string]$State.steps[$key].error
        }
        elseif ($State.steps[$key].reason) {
            [string]$State.steps[$key].reason
        }
        else {
            $status
        }
        throw "Tool '$ToolId' install did not complete: $reason"
    }
}
