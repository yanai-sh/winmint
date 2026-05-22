#Requires -Version 7.3

function Write-AgentLog {
    param([string]$Message)
    "$(Get-Date -Format o) $Message" | Out-File (Join-Path $logDir 'WinMintAgent.log') -Append -Encoding utf8
}

function Write-AgentEvent {
    param(
        [Parameter(Mandatory)][string]$Type,
        [string]$Status,
        [string]$Step,
        [string]$Message,
        [hashtable]$Data = @{}
    )

    try {
        $agentEvent = [ordered]@{
            time = Get-Date -Format o
            type = $Type
        }
        if (-not [string]::IsNullOrWhiteSpace($Status)) { $agentEvent.status = $Status }
        if (-not [string]::IsNullOrWhiteSpace($Step)) { $agentEvent.step = $Step }
        if (-not [string]::IsNullOrWhiteSpace($Message)) { $agentEvent.message = $Message }
        foreach ($key in $Data.Keys) {
            if (-not $agentEvent.Contains($key)) { $agentEvent[$key] = $Data[$key] }
        }
        $json = $agentEvent | ConvertTo-Json -Depth 10 -Compress
        $json | Out-File -LiteralPath $eventLogPath -Append -Encoding utf8
        if ($EmitProgressJson) { [Console]::Out.WriteLine($json) }
    }
    catch {
        Write-AgentLog "Progress event write failed: $($_.Exception.Message)"
    }
}

function Initialize-AgentConsole {
    if (-not $InteractiveFirstLogon) { return }
    try {
        if (-not (Get-Command Write-SpectreHost -ErrorAction SilentlyContinue)) {
            $galleryCache = Join-Path $stateDir 'PSGallery'
            $null = New-Item -ItemType Directory -Path $galleryCache -Force -ErrorAction SilentlyContinue
            $manifest = @(Get-ChildItem -LiteralPath $galleryCache -Recurse -Filter 'PwshSpectreConsole.psd1' -File -ErrorAction SilentlyContinue |
                    Sort-Object FullName -Descending |
                    Select-Object -First 1)
            if (-not $manifest -and (Get-Command Save-Module -ErrorAction SilentlyContinue)) {
                $savedProgress = $ProgressPreference
                try {
                    $ProgressPreference = 'SilentlyContinue'
                    Save-Module -Name PwshSpectreConsole -Path $galleryCache -Repository PSGallery -Force -ErrorAction Stop
                }
                finally {
                    $ProgressPreference = $savedProgress
                }
                $manifest = @(Get-ChildItem -LiteralPath $galleryCache -Recurse -Filter 'PwshSpectreConsole.psd1' -File -ErrorAction SilentlyContinue |
                        Sort-Object FullName -Descending |
                        Select-Object -First 1)
            }
            if ($manifest) {
                Import-Module -Name $manifest.FullName -Force -Global -ErrorAction Stop
            }
        }
        $script:AgentConsoleReady = [bool](Get-Command Write-SpectreHost -ErrorAction SilentlyContinue)
        if ($script:AgentConsoleReady) {
            try {
                $w = [Math]::Clamp([int]$Host.UI.RawUI.WindowSize.Width, 60, 220)
                $h = [Math]::Clamp([int]$Host.UI.RawUI.WindowSize.Height, 20, 120)
                [Spectre.Console.AnsiConsole]::Console.Profile.Width = $w
                [Spectre.Console.AnsiConsole]::Console.Profile.Height = $h
            }
            catch { }
        }
    }
    catch {
        $script:AgentConsoleReady = $false
        Write-AgentLog "PwshSpectreConsole unavailable: $($_.Exception.Message)"
    }
}

function Get-AgentEscapedText {
    param([string]$Text)
    if ($script:AgentConsoleReady) { return [Spectre.Console.Markup]::Escape([string]$Text) }
    return [string]$Text
}

function Write-AgentConsoleLine {
    param(
        [ValidateSet('Info','OK','Warn','Error','Section')][string]$Level,
        [string]$Message
    )
    if (-not $InteractiveFirstLogon) { return }
    $safe = Get-AgentEscapedText -Text $Message
    if ($script:AgentConsoleReady) {
        $prefix = switch ($Level) {
            'OK' { '[green]+[/]' }
            'Warn' { '[yellow]![/]' }
            'Error' { '[red]x[/]' }
            'Section' { '[dodgerblue1]>[/]' }
            default { '[grey]>[/]' }
        }
        $null = Write-SpectreHost "$prefix [white]$safe[/]"
        return
    }
    $color = switch ($Level) {
        'OK' { 'Green' }
        'Warn' { 'Yellow' }
        'Error' { 'Red' }
        'Section' { 'Cyan' }
        default { 'Gray' }
    }
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Show-AgentConsoleHeader {
    if (-not $InteractiveFirstLogon) { return }
    if ($script:AgentConsoleReady) {
        $body = @(
            '[white]WinMint is applying the selected first-logon preset.[/]'
            '[grey]This window can be left alone. Detailed logs are written under[/] [silver]%LOCALAPPDATA%\WinMint\Logs[/][grey].[/]'
        ) -join "`n"
        $null = Format-SpectrePanel -Data $body -Header '[bold dodgerblue1]WinMint FirstLogon[/]' -Border Rounded -Color DodgerBlue1 -Expand |
            Out-SpectreHost | Out-Host
        return
    }
    Write-Host ''
    Write-Host 'WinMint FirstLogon' -ForegroundColor Cyan
    Write-Host 'Applying the selected first-logon preset. Logs are under %LOCALAPPDATA%\\WinMint\\Logs.' -ForegroundColor Gray
    Write-Host ''
}

function Show-AgentPlan {
    if (-not $InteractiveFirstLogon) { return }
    $rows = @(
        [pscustomobject]@{ Step = 'Package managers'; Selection = if (Test-AgentModuleEnabled -Name 'packageManagers') { 'Selected' } else { 'Not needed' } }
        [pscustomobject]@{ Step = 'WSL'; Selection = if (Test-AgentModuleEnabled -Name 'wsl') { 'Selected' } else { 'Not selected' } }
        [pscustomobject]@{ Step = 'Desktop layers'; Selection = if (Test-AgentModuleEnabled -Name 'shell') { 'Selected' } else { 'Standard' } }
        [pscustomobject]@{ Step = 'Windhawk'; Selection = if (Test-AgentModuleEnabled -Name 'windhawk') { 'Selected' } else { 'Not selected' } }
        [pscustomobject]@{ Step = 'Editors'; Selection = if (@($agentProfile.editors).Count) { @($agentProfile.editors) -join ', ' } else { 'None' } }
    )
    if ($script:AgentConsoleReady) {
        $null = Format-SpectreTable -Data $rows -Property Step, Selection -Border Rounded -Color Grey -Title '[bold white]Selected automation[/]' |
            Out-SpectreHost | Out-Host
        return
    }
    $rows | Format-Table -AutoSize
}

function Show-AgentFinalSummary {
    param([hashtable]$State)
    if (-not $InteractiveFirstLogon) { return }
    $rows = @(
        $State.steps.GetEnumerator() |
            Sort-Object Name |
            ForEach-Object {
                [pscustomobject]@{
                    Step = $_.Key
                    Status = [string]$_.Value.status
                }
            }
    )
    if ($script:AgentConsoleReady) {
        $null = Format-SpectreTable -Data $rows -Property Step, Status -Border Rounded -Color Grey -Title '[bold white]FirstLogon result[/]' |
            Out-SpectreHost | Out-Host
        return
    }
    $rows | Format-Table -AutoSize
}

function Wait-AgentConsoleBeforeClose {
    param([bool]$Failed)
    if (-not $InteractiveFirstLogon) { return }
    if ($Failed) {
        Write-AgentConsoleLine -Level Error -Message "One or more selected steps failed. Review $logDir before closing this window."
        Read-Host 'Press Enter to close'
        return
    }
    Write-AgentConsoleLine -Level OK -Message 'First-logon automation finished. This window will close shortly.'
    Start-Sleep -Seconds 8
}
