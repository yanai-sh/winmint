#Requires -Version 5.1

function Write-WinMintFirstLogonError {
    param([string]$Message)
    "$(Get-Date -Format 'o') $Message" | Out-File (Join-Path $logDir 'FirstLogon_errors.log') -Append
}

function Set-WinMintFirstLogonEnvironmentValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )
    Invoke-WinMintFirstLogonReg -Arguments @('add', 'HKCU\Environment', '/v', $Name, '/t', 'REG_EXPAND_SZ', '/d', $Value, '/f') -AllowFailure
}

function Set-WinMintFirstLogonWindowsTerminalDefault {
    $terminalKey = 'HKCU\Console\%%Startup'
    Invoke-WinMintFirstLogonReg -Arguments @('add', $terminalKey, '/v', 'DelegationConsole', '/t', 'REG_SZ', '/d', '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}', '/f') -AllowFailure
    Invoke-WinMintFirstLogonReg -Arguments @('add', $terminalKey, '/v', 'DelegationTerminal', '/t', 'REG_SZ', '/d', '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}', '/f') -AllowFailure
    "$(Get-Date -Format 'o') Windows Terminal set as the live user's default terminal host." |
        Out-File (Join-Path $logDir 'FirstLogon.log') -Append
}

function Save-WinMintFirstLogonState {
    param([hashtable]$State)
    $path = Join-Path $logDir 'FirstLogonState.json'
    $tmp = "$path.tmp"
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tmp -Encoding UTF8
    $null = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

function Read-WinMintFirstLogonState {
    $path = Join-Path $logDir 'FirstLogonState.json'
    try {
        if (Test-Path -LiteralPath $path) {
            return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    }
    catch {
        Write-WinMintFirstLogonError "FirstLogon state read failed: $_"
    }
    return $null
}

function New-WinMintFirstLogonRunState {
    $previous = Read-WinMintFirstLogonState
    $previousAttempts = 0
    try {
        if ($previous -and $previous.PSObject.Properties['attempts']) {
            $previousAttempts = [int]$previous.attempts
        }
    }
    catch { $previousAttempts = 0 }
    @{
        startedAt = Get-Date -Format o
        agentExitCode = $null
        status = 'running'
        attempts = ($previousAttempts + 1)
        maxAttempts = $script:WinMintFirstLogonMaxAttempts
    }
}

function Read-WinMintFirstLogonSetupProfile {
    $setupProfilePath = Join-Path $payloadDir 'WinMintSetupProfile.json'
    try {
        if (Test-Path -LiteralPath $setupProfilePath) {
            return Get-Content -LiteralPath $setupProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    }
    catch {
        Write-WinMintFirstLogonError "Setup profile read failed: $_"
    }
    return $null
}

function Get-WinMintFirstLogonNestedProfileValue {
    param(
        [object]$BuildProfile,
        [string]$Section,
        [string]$Nested,
        [string]$Name,
        $Default = $null
    )

    if (-not $BuildProfile) { return $Default }
    $sectionProp = $BuildProfile.PSObject.Properties[$Section]
    if (-not $sectionProp) { return $Default }
    $nestedProp = $sectionProp.Value.PSObject.Properties[$Nested]
    if (-not $nestedProp) { return $Default }
    $valueProp = $nestedProp.Value.PSObject.Properties[$Name]
    if (-not $valueProp) { return $Default }
    return $valueProp.Value
}

function Resolve-WinMintPowerShellHost {
    $pwsh = "$env:ProgramFiles\PowerShell\7\pwsh.exe"
    if (Test-Path -LiteralPath $pwsh) { return $pwsh }
    $sysnative = Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $sysnative) { return $sysnative }
    $system32 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $system32) { return $system32 }
    return 'powershell.exe'
}

function Test-WinMintTokenElevated {
    if (-not ('WinMint.TokenElevation' -as [type])) {
        Add-Type -Namespace WinMint -Name TokenElevation -MemberDefinition @'
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct TOKEN_ELEVATION {
    public int TokenIsElevated;
}
[System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError = true)]
public static extern bool OpenProcessToken(System.IntPtr ProcessHandle, uint DesiredAccess, out System.IntPtr TokenHandle);
[System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError = true)]
public static extern bool GetTokenInformation(System.IntPtr TokenHandle, int TokenInformationClass, out TOKEN_ELEVATION TokenInformation, int TokenInformationLength, out int ReturnLength);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern bool CloseHandle(System.IntPtr hObject);
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern System.IntPtr GetCurrentProcess();
'@
    }

    $TOKEN_QUERY = 0x0008
    $TokenElevation = 20
    $tokenHandle = [IntPtr]::Zero
    if (-not [WinMint.TokenElevation]::OpenProcessToken([WinMint.TokenElevation]::GetCurrentProcess(), [uint32]$TOKEN_QUERY, [ref]$tokenHandle)) {
        return $false
    }

    try {
        $elevation = New-Object WinMint.TokenElevation+TOKEN_ELEVATION
        $returnLength = 0
        $size = [System.Runtime.InteropServices.Marshal]::SizeOf($elevation)
        if ([WinMint.TokenElevation]::GetTokenInformation($tokenHandle, $TokenElevation, [ref]$elevation, $size, [ref]$returnLength)) {
            return ($elevation.TokenIsElevated -ne 0)
        }
        return $false
    }
        finally {
            if ($tokenHandle -ne [IntPtr]::Zero) {
                [WinMint.TokenElevation]::CloseHandle($tokenHandle) | Out-Null
            }
        }
    }

function Resolve-WinMintFirstLogonAgentMode {
    param(
        [Parameter(Mandatory)][string]$RequestedMode
    )

    $envMode = [string]$env:WINMINT_FIRSTLOGON_MODE
    if (-not [string]::IsNullOrWhiteSpace($envMode)) {
        switch -Regex ($envMode.Trim()) {
            '^(headless|none|no-ui)$' { return 'Headless' }
            '^(console|terminal|ui)$' { return 'Console' }
        }
    }

    if ($RequestedMode -ne 'Auto') {
        if ($RequestedMode -eq 'UI') { return 'Console' }
        return $RequestedMode
    }
    # Default to a visible progress console so the user can see first-logon automation
    # moving while the selected installs and setup work finish. A silent headless run is
    # still available explicitly via -AgentMode Headless / WINMINT_FIRSTLOGON_MODE=headless.
    return 'Console'
}

function Invoke-WinMintFirstLogonReg {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure
    )
    $out = & reg.exe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        Write-WinMintFirstLogonError "reg.exe $($Arguments -join ' ') exited $LASTEXITCODE`n$($out | Out-String)"
    }
}

function Set-WinMintFirstLogonDesktopDefaults {
    $wallpaperPath = 'C:\Windows\Web\Wallpaper\Windows\WinMint-Bloom.jpg'
    $desktopKey = 'HKCU\Control Panel\Desktop'
    $personalizeKey = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $dwmKey = 'HKCU\Software\Microsoft\Windows\DWM'

    Invoke-WinMintFirstLogonReg -Arguments @('add', $personalizeKey, '/v', 'AppsUseLightTheme', '/t', 'REG_DWORD', '/d', '0', '/f') -AllowFailure
    Invoke-WinMintFirstLogonReg -Arguments @('add', $personalizeKey, '/v', 'SystemUsesLightTheme', '/t', 'REG_DWORD', '/d', '0', '/f') -AllowFailure
    Invoke-WinMintFirstLogonReg -Arguments @('add', $dwmKey, '/v', 'ColorPrevalence', '/t', 'REG_DWORD', '/d', '0', '/f') -AllowFailure

    # Aesthetic defaults for the live user (mirror of the Default-hive values, applied to
    # HKCU so they are guaranteed set for this account): hide the taskbar search box and
    # remove the Recycle Bin desktop icon.
    $searchKey = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Search'
    Invoke-WinMintFirstLogonReg -Arguments @('add', $searchKey, '/v', 'SearchboxTaskbarMode', '/t', 'REG_DWORD', '/d', '0', '/f') -AllowFailure
    foreach ($view in 'NewStartPanel', 'ClassicStartMenu') {
        $hideKey = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\$view"
        Invoke-WinMintFirstLogonReg -Arguments @('add', $hideKey, '/v', '{645FF040-5081-101B-9F08-00AA002F954E}', '/t', 'REG_DWORD', '/d', '1', '/f') -AllowFailure
    }

    # Native helper: broadcast the theme change so the ALREADY-RUNNING shell
    # (taskbar / Start / flyouts) re-reads AppsUseLightTheme + SystemUsesLightTheme.
    Add-Type -Namespace WinMint.Native -Name Shell -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern bool SystemParametersInfo(int uiAction, int uiParam, string pvParam, int fWinIni);
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.IntPtr wParam, string lParam, uint flags, uint timeout, out System.IntPtr result);
'@ -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $wallpaperPath) {
        Invoke-WinMintFirstLogonReg -Arguments @('add', $desktopKey, '/v', 'Wallpaper', '/t', 'REG_SZ', '/d', $wallpaperPath, '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $desktopKey, '/v', 'WallpaperStyle', '/t', 'REG_SZ', '/d', '10', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $desktopKey, '/v', 'TileWallpaper', '/t', 'REG_SZ', '/d', '0', '/f') -AllowFailure
        try { [WinMint.Native.Shell]::SystemParametersInfo(20, 0, $wallpaperPath, 3) | Out-Null } catch { }
    }

    # Windows applies the light default theme at first logon, so the live shell keeps a light
    # taskbar even though the dark Personalize values are written. Broadcast the documented
    # theme-change notification (exactly what the Settings app sends when dark mode is toggled)
    # so the shell re-reads the values and applies dark to the taskbar/Start - rather than
    # relying on the registry write alone being picked up.
    try {
        $hwndBroadcast = [IntPtr]0xffff
        $wmSettingChange = 0x001A
        $smtoAbortIfHung = 0x0002
        $res = [IntPtr]::Zero
        foreach ($payload in 'ImmersiveColorSet', 'WindowsThemeElement', 'Policy') {
            [void][WinMint.Native.Shell]::SendMessageTimeout($hwndBroadcast, $wmSettingChange, [IntPtr]::Zero, $payload, $smtoAbortIfHung, 1000, [ref]$res)
        }
        "$(Get-Date -Format 'o') Broadcast theme-change (ImmersiveColorSet) so the shell applies dark mode." | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
    }
    catch { Write-WinMintFirstLogonError "Theme-change broadcast failed: $_" }
}

function Set-WinMintFirstLogonCursorScheme {
    $schemeName = 'Windows 11 Modern'
    $destSeg = 'Windows11Modern'
    $base = "%SystemRoot%\Cursors\$destSeg"
    $cursorDir = Join-Path $env:SystemRoot "Cursors\$destSeg"
    $schemeOrder = @(
        'Arrow.cur', 'Help.cur', 'Work.ani', 'Busy.ani', 'Cross.cur', 'IBeam.cur', 'Handwriting.cur', 'Unavailable.cur',
        'SizeNS.cur', 'SizeWE.cur', 'SizeNWSE.cur', 'SizeNESW.cur', 'Move.cur', 'Alternate.cur', 'Link.cur',
        'Pin.cur', 'Person.cur'
    )
    $cursorPairs = @(
        @{ Name = 'Arrow'; File = 'Arrow.cur' }
        @{ Name = 'Help'; File = 'Help.cur' }
        @{ Name = 'AppStarting'; File = 'Work.ani' }
        @{ Name = 'Wait'; File = 'Busy.ani' }
        @{ Name = 'Crosshair'; File = 'Cross.cur' }
        @{ Name = 'IBeam'; File = 'IBeam.cur' }
        @{ Name = 'NWPen'; File = 'Handwriting.cur' }
        @{ Name = 'No'; File = 'Unavailable.cur' }
        @{ Name = 'SizeNS'; File = 'SizeNS.cur' }
        @{ Name = 'SizeWE'; File = 'SizeWE.cur' }
        @{ Name = 'SizeNWSE'; File = 'SizeNWSE.cur' }
        @{ Name = 'SizeNESW'; File = 'SizeNESW.cur' }
        @{ Name = 'SizeAll'; File = 'Move.cur' }
        @{ Name = 'UpArrow'; File = 'Alternate.cur' }
        @{ Name = 'Hand'; File = 'Link.cur' }
        @{ Name = 'Pin'; File = 'Pin.cur' }
        @{ Name = 'Person'; File = 'Person.cur' }
    )

    foreach ($file in $schemeOrder) {
        if (-not (Test-Path -LiteralPath (Join-Path $cursorDir $file))) {
            Write-WinMintFirstLogonError "Cursor scheme file missing; live cursor apply skipped: $(Join-Path $cursorDir $file)"
            return
        }
    }

    $schemeList = ($schemeOrder | ForEach-Object { "$base\$_" }) -join ','
    $schemesKey = 'HKCU\Control Panel\Cursors\Schemes'
    $cursorsKey = 'HKCU\Control Panel\Cursors'
    Invoke-WinMintFirstLogonReg -Arguments @('add', $schemesKey, '/v', $schemeName, '/t', 'REG_EXPAND_SZ', '/d', $schemeList, '/f') -AllowFailure
    Invoke-WinMintFirstLogonReg -Arguments @('add', $cursorsKey, '/ve', '/t', 'REG_SZ', '/d', $schemeName, '/f') -AllowFailure
    foreach ($pair in $cursorPairs) {
        Invoke-WinMintFirstLogonReg -Arguments @('add', $cursorsKey, '/v', $pair.Name, '/t', 'REG_EXPAND_SZ', '/d', "$base\$($pair.File)", '/f') -AllowFailure
    }

    Add-Type -Namespace WinMint.Native -Name Cursor -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
public static extern bool SystemParametersInfo(int uiAction, int uiParam, System.IntPtr pvParam, int fWinIni);
'@ -ErrorAction SilentlyContinue

    try {
        # SPI_SETCURSORS reloads the active cursor set from HKCU after first-logon writes.
        $spiSetCursors = 0x0057
        $spifUpdateIniFile = 0x01
        $spifSendChange = 0x02
        [void][WinMint.Native.Cursor]::SystemParametersInfo($spiSetCursors, 0, [IntPtr]::Zero, ($spifUpdateIniFile -bor $spifSendChange))
        "$(Get-Date -Format 'o') Live user cursor scheme applied: $schemeName" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
    }
    catch {
        Write-WinMintFirstLogonError "Cursor refresh failed: $_"
    }
}

function Resolve-WinMintFirstLogonAppExecutable {
    param([Parameter(Mandatory)][string]$Id)

    $candidates = switch ($Id) {
        'zen-browser' {
            @(
                (Join-Path $env:ProgramFiles 'Zen Browser\zen.exe'),
                (Join-Path ${env:ProgramFiles(x86)} 'Zen Browser\zen.exe'),
                (Join-Path $env:LOCALAPPDATA 'Programs\Zen Browser\zen.exe')
            )
            break
        }
        'cursor' {
            @(
                (Join-Path $env:LOCALAPPDATA 'Programs\cursor\Cursor.exe'),
                (Join-Path $env:LOCALAPPDATA 'Programs\Cursor\Cursor.exe'),
                (Join-Path $env:ProgramFiles 'Cursor\Cursor.exe')
            )
            break
        }
        'helium' {
            @(
                (Join-Path $env:LOCALAPPDATA 'imput\Helium\Application\chrome.exe'),
                (Join-Path $env:ProgramFiles 'Helium\Application\chrome.exe'),
                (Join-Path ${env:ProgramFiles(x86)} 'Helium\Application\chrome.exe')
            )
            break
        }
        'vscode' {
            @(
                (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'),
                (Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe')
            )
            break
        }
        'zed' {
            @(
                (Join-Path $env:LOCALAPPDATA 'Programs\Zed\Zed.exe'),
                (Join-Path $env:ProgramFiles 'Zed\Zed.exe')
            )
            break
        }
        'antigravity' {
            @(
                (Join-Path $env:LOCALAPPDATA 'Programs\Antigravity\Antigravity.exe'),
                (Join-Path $env:ProgramFiles 'Antigravity\Antigravity.exe')
            )
            break
        }
        default { @() }
    }

    foreach ($candidate in @($candidates)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return $null
}

function Get-WinMintFirstLogonAppDisplayName {
    param(
        [Parameter(Mandatory)][string]$Id,
        [hashtable]$DisplayNames = @{}
    )

    switch ($Id) {
        'zen-browser' { 'Zen Browser' }
        'helium' { 'Helium' }
        'librewolf' { 'LibreWolf' }
        'brave' { 'Brave' }
        'cursor' { 'Cursor' }
        'vscode' { 'Visual Studio Code' }
        'zed' { 'Zed' }
        'antigravity' { 'Antigravity' }
        default {
            if ($DisplayNames.ContainsKey($Id)) { $DisplayNames[$Id] } else { $Id }
        }
    }
}

function Get-WinMintFirstLogonPackageDisplayNames {
    param([Parameter(Mandatory)][string]$AgentProfilePath)

    $names = @{}
    $packagesPath = Join-Path (Split-Path -Parent $AgentProfilePath) 'packages.json'
    if (-not (Test-Path -LiteralPath $packagesPath -PathType Leaf)) { return $names }

    try {
        $packages = Get-Content -LiteralPath $packagesPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($toolProperty in @($packages.tools.PSObject.Properties)) {
            $displayName = [string]$toolProperty.Value.displayName
            if (-not [string]::IsNullOrWhiteSpace($displayName)) {
                $names[[string]$toolProperty.Name] = $displayName
            }
        }
    }
    catch {
        Write-WinMintFirstLogonError "Start pin package display-name lookup failed: $_"
    }
    return $names
}

function Resolve-WinMintFirstLogonStartShortcut {
    param([Parameter(Mandatory)][string]$DisplayName)

    $roots = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')
    )
    $escaped = [regex]::Escape($DisplayName)
    foreach ($rootPath in $roots) {
        if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) { continue }
        $shortcut = Get-ChildItem -LiteralPath $rootPath -Recurse -Filter '*.lnk' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -match "^$escaped(?:\s|$)" -and $_.BaseName -notmatch '^(?i)uninstall\s' } |
            Sort-Object @{ Expression = { if ($_.BaseName -eq $DisplayName) { 0 } else { 1 } } }, FullName |
            Select-Object -First 1
        if ($shortcut) { return $shortcut.FullName }
    }
    return $null
}

function New-WinMintFirstLogonStartShortcut {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$TargetPath
    )

    $shortcutDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $null = New-Item -ItemType Directory -Path $shortcutDir -Force -ErrorAction Stop
    $shortcutPath = Join-Path $shortcutDir "$Name.lnk"
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = Split-Path -Parent $TargetPath
    $shortcut.IconLocation = "$TargetPath,0"
    $shortcut.Save()
    return $shortcutPath
}

function Set-WinMintFirstLogonStartPins {
    param([Parameter(Mandatory)][string]$AgentProfilePath)

    if (-not (Test-Path -LiteralPath $AgentProfilePath)) { return }
    $agentProfile = Get-Content -LiteralPath $AgentProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $cliOnlyAppIds = @('neovim')
    $selected = @(
        @($agentProfile.browsers) +
        @($agentProfile.editors)
    ) | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_) -and
        [string]$_ -ne 'edge' -and
        $cliOnlyAppIds -notcontains [string]$_
    } | Select-Object -Unique

    $pinnedList = [System.Collections.Generic.List[object]]::new()
    $pinnedList.Add([ordered]@{ desktopAppId = 'Microsoft.Windows.Explorer' }) | Out-Null
    $pinnedList.Add([ordered]@{ packagedAppId = 'windows.immutablecontrolpanel' }) | Out-Null
    $pinnedList.Add([ordered]@{ packagedAppId = 'Microsoft.WindowsTerminal_8wekyb3d8bbwe!App' }) | Out-Null

    $skipped = [System.Collections.Generic.List[string]]::new()
    $displayNames = Get-WinMintFirstLogonPackageDisplayNames -AgentProfilePath $AgentProfilePath
    foreach ($id in $selected) {
        $appId = [string]$id
        $displayName = Get-WinMintFirstLogonAppDisplayName -Id $appId -DisplayNames $displayNames
        $shortcutPath = Resolve-WinMintFirstLogonStartShortcut -DisplayName $displayName
        if (-not $shortcutPath) {
            $exe = Resolve-WinMintFirstLogonAppExecutable -Id $appId
            if ($exe) {
                $shortcutPath = New-WinMintFirstLogonStartShortcut -Name $displayName -TargetPath $exe
            }
        }
        if (-not $shortcutPath) {
            $skipped.Add($appId) | Out-Null
            continue
        }
        $pinnedList.Add([ordered]@{ desktopAppLink = $shortcutPath }) | Out-Null
    }

    $layoutJson = ([ordered]@{ pinnedList = @($pinnedList) } | ConvertTo-Json -Compress -Depth 8)
    Invoke-WinMintFirstLogonReg -Arguments @('add', 'HKCU\Software\Policies\Microsoft\Windows\Explorer', '/v', 'ConfigureStartPins', '/t', 'REG_SZ', '/d', $layoutJson, '/f') -AllowFailure
    Invoke-WinMintFirstLogonReg -Arguments @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer', '/v', 'ConfigureStartPins', '/t', 'REG_SZ', '/d', $layoutJson, '/f') -AllowFailure

    "$(Get-Date -Format 'o') Start pins applied: $layoutJson" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
    if ($skipped.Count -gt 0) {
        "$(Get-Date -Format 'o') Start pins skipped because no Start Menu shortcut or app executable was found: $($skipped -join ', ')" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
    }

    try {
        Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Process explorer.exe
    }
    catch {
        Write-WinMintFirstLogonError "Explorer restart for Start pins failed: $_"
    }
}

function New-WinMintFirstLogonTerminalPowerShellProfile {
    [ordered]@{
        guid = '{2c7d8c64-fb18-43d0-9bd0-bf9f6d5c4e22}'
        name = 'PowerShell'
        commandline = '"%ProgramFiles%\PowerShell\7\pwsh.exe" -NoLogo'
        icon = '%ProgramFiles%\PowerShell\7\pwsh.exe'
        startingDirectory = '%USERPROFILE%'
    }
}

function New-WinMintFirstLogonTerminalWslProfile {
    param([Parameter(Mandatory)][string]$Distro)

    $normalized = switch -Regex ($Distro) {
        '^(NixOS-WSL|NixOS|nixos-wsl)$' { 'NixOS'; break }
        '^(Fedora|FedoraLinux|FedoraLinux-\d+)$' { 'FedoraLinux'; break }
        '^(Arch(?: Linux)?|archlinux)$' { 'archlinux'; break }
        '^(Pengwin|pengwin)$' { 'pengwin'; break }
        '^Ubuntu-\d+\.\d+$' { 'Ubuntu'; break }
        default { $Distro }
    }
    $terminalLocalState = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
    $iconRoot = Join-Path $terminalLocalState 'Icons'
    $displayName = switch ($normalized) {
        'Ubuntu' { 'Ubuntu' }
        'FedoraLinux' { 'Fedora' }
        'archlinux' { 'Arch Linux' }
        'NixOS' { 'NixOS' }
        'pengwin' { 'Pengwin' }
        default { $normalized }
    }
    $guid = switch ($normalized) {
        'Ubuntu' { '{9f23b5e0-8f73-4a90-9d8d-11e8b43d0001}' }
        'FedoraLinux' { '{9f23b5e0-8f73-4a90-9d8d-11e8b43d0002}' }
        'archlinux' { '{9f23b5e0-8f73-4a90-9d8d-11e8b43d0003}' }
        'NixOS' { '{9f23b5e0-8f73-4a90-9d8d-11e8b43d0004}' }
        'pengwin' { '{9f23b5e0-8f73-4a90-9d8d-11e8b43d0005}' }
        default { "{9f23b5e0-8f73-4a90-9d8d-$(([Math]::Abs($normalized.GetHashCode()) % 10000000000).ToString('0000000000'))}" }
    }
    $icon = switch ($normalized) {
        'Ubuntu' { Join-Path $iconRoot 'ubuntu.png' }
        'FedoraLinux' { Join-Path $iconRoot 'fedora.png' }
        'archlinux' { Join-Path $iconRoot 'archlinux.png' }
        'NixOS' { Join-Path $iconRoot 'nixos.png' }
        'pengwin' { Join-Path $iconRoot 'pengwin.png' }
        default { $null }
    }

    $terminalProfile = [ordered]@{
        guid = $guid
        name = $displayName
        commandline = "wsl.exe -d $normalized"
        startingDirectory = '%USERPROFILE%'
    }
    if ($icon -and (Test-Path -LiteralPath $icon)) { $terminalProfile.icon = $icon }
    return $terminalProfile
}

function Repair-WinMintFirstLogonTerminalIcons {
    $terminalLocalState = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
    $iconRoot = Join-Path $terminalLocalState 'Icons'
    $sourceRoots = @(
        'C:\Users\Default\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\Icons',
        'C:\Windows\Setup\Scripts\WinMintAgent\Assets\WindowsTerminal\Icons'
    )
    $null = New-Item -ItemType Directory -Path $iconRoot -Force -ErrorAction SilentlyContinue
    foreach ($name in @('ubuntu.png', 'fedora.png', 'archlinux.png', 'nixos.png', 'pengwin.png')) {
        foreach ($sourceRoot in $sourceRoots) {
            $src = Join-Path $sourceRoot $name
            $dst = Join-Path $iconRoot $name
            if ((Test-Path -LiteralPath $src -PathType Leaf) -and -not (Test-Path -LiteralPath $dst -PathType Leaf)) {
                Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction SilentlyContinue
                break
            }
        }
    }
}

function Set-WinMintFirstLogonTerminalProfiles {
    param([Parameter(Mandatory)][string]$AgentProfilePath)

    $settingsPath = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    if (-not (Test-Path -LiteralPath $settingsPath)) { return }
    Repair-WinMintFirstLogonTerminalIcons
    $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    if (-not $settings.ContainsKey('profiles')) { $settings.profiles = [ordered]@{} }
    if (-not $settings.profiles.ContainsKey('defaults')) {
        $settings.profiles.defaults = [ordered]@{}
    }
    if (-not $settings.profiles.defaults.ContainsKey('font')) {
        $settings.profiles.defaults.font = [ordered]@{}
    }
    $settings.profiles.defaults.font.face = 'Cascadia Code NF'
    $settings.profiles.defaults.colorScheme = 'One Half Dark'
    $settings.profiles.defaults.bellStyle = 'none'
    $settings.centerOnLaunch = $true
    $settings.defaultProfile = '{2c7d8c64-fb18-43d0-9bd0-bf9f6d5c4e22}'
    $settings.disabledProfileSources = @(
        'Windows.Terminal.WindowsPowerShell',
        'Windows.Terminal.PowershellCore',
        'Windows.Terminal.Azure',
        'Windows.Terminal.SSH',
        'Windows.Terminal.Wsl'
    )
    $settings.newTabMenu = @([ordered]@{ type = 'remainingProfiles' })

    $profiles = [System.Collections.Generic.List[object]]::new()
    $profiles.Add((New-WinMintFirstLogonTerminalPowerShellProfile)) | Out-Null
    if (Test-Path -LiteralPath $AgentProfilePath) {
        $agentProfile = Get-Content -LiteralPath $AgentProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $distros = @($agentProfile.modules.wsl.distros | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and [string]$_ -ne 'None' } | Select-Object -Unique)
        foreach ($distro in $distros) {
            $profiles.Add((New-WinMintFirstLogonTerminalWslProfile -Distro ([string]$distro))) | Out-Null
        }
    }
    $settings.profiles.list = @($profiles)
    $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    "$(Get-Date -Format 'o') Windows Terminal profiles finalized: $((@($profiles) | ForEach-Object { [string]$_['name'] }) -join ', ')" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
}

function Set-WinMintFirstLogonInputLanguages {
    # Set the user language list to [display language] + [secondary input languages], with the
    # display language ALWAYS first (primary) and explicitly pinned as the UI language. This is
    # how a secondary keyboard (e.g. Hebrew) is added without ever changing the display/system
    # language. Uses the official International cmdlets, not registry pokes.
    param(
        [string]$DisplayLanguage = 'en-US',
        [string[]]$SecondaryInputLanguages = @()
    )
    if (-not (Get-Command Set-WinUserLanguageList -ErrorAction SilentlyContinue)) { return }
    if ([string]::IsNullOrWhiteSpace($DisplayLanguage)) { $DisplayLanguage = 'en-US' }
    $displayPrimary = (($DisplayLanguage -split '-')[0]).ToLowerInvariant()
    $list = [System.Collections.Generic.List[string]]::new()
    $list.Add($DisplayLanguage)
    foreach ($lang in @($SecondaryInputLanguages)) {
        $tag = [string]$lang
        if ([string]::IsNullOrWhiteSpace($tag)) { continue }
        if ((($tag -split '-')[0]).ToLowerInvariant() -eq $displayPrimary) { continue }  # never displace the display language
        if ($list -notcontains $tag) { $list.Add($tag) }
    }
    Set-WinUserLanguageList -LanguageList @($list) -Force -ErrorAction Stop
    # Hard-pin the UI/display language so a secondary input language can never become the
    # display language (the user requirement: type Hebrew, but the system stays English).
    try { Set-WinUILanguageOverride -Language $DisplayLanguage -ErrorAction SilentlyContinue } catch { }
    "$(Get-Date -Format 'o') Set user language list to: $(@($list) -join ', ') (display pinned to $DisplayLanguage)." |
        Out-File (Join-Path $logDir 'FirstLogon.log') -Append
}

function Set-WinMintFirstLogonRetry {
    # The RunOnce command embeds quoted paths with spaces. reg.exe mangles embedded
    # quotes in a /d value ("ERROR: Invalid syntax"), so write the value with the
    # native registry provider, which stores the string verbatim.
    $runOnce = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    $exe = Resolve-WinMintPowerShellHost
    $command = "`"$exe`" -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$script:WinMintFirstLogonEntryPath`""
    if (-not (Test-Path -LiteralPath $runOnce)) { New-Item -Path $runOnce -Force | Out-Null }
    Set-ItemProperty -LiteralPath $runOnce -Name 'WinMintFirstLogonRetry' -Value $command -Type String -Force
}

function Clear-WinMintFirstLogonRetry {
    $runOnce = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    Remove-ItemProperty -LiteralPath $runOnce -Name 'WinMintFirstLogonRetry' -Force -ErrorAction SilentlyContinue
}

function Clear-WinMintAutoLogonPassword {
    # Removes the plaintext DefaultPassword and AutoLogonCount from the registry.
    # Called ONLY once the agent run fully succeeds. Until then the password must stay
    # resident so auto sign-in survives every install reboot without ever prompting.
    $winlogon = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    foreach ($name in @('DefaultPassword', 'AutoLogonCount')) {
        Invoke-WinMintFirstLogonReg -Arguments @('delete', $winlogon, '/v', $name, '/f') -AllowFailure
    }
}

function Set-WinMintFirstLogonXdgDefaults {
    $xdgRuntimeDir = Join-Path $env:LOCALAPPDATA 'Temp\xdg-runtime'
    foreach ($folder in @('.config', '.cache', '.local', '.local\share', '.local\state', 'bin', '.local\bin')) {
        New-Item -ItemType Directory -Path (Join-Path $env:USERPROFILE $folder) -Force -ErrorAction SilentlyContinue | Out-Null
    }
    New-Item -ItemType Directory -Path $xdgRuntimeDir -Force -ErrorAction SilentlyContinue | Out-Null
    Set-WinMintFirstLogonEnvironmentValue -Name 'XDG_CONFIG_HOME' -Value '%USERPROFILE%\.config'
    Set-WinMintFirstLogonEnvironmentValue -Name 'XDG_DATA_HOME' -Value '%USERPROFILE%\.local\share'
    Set-WinMintFirstLogonEnvironmentValue -Name 'XDG_STATE_HOME' -Value '%USERPROFILE%\.local\state'
    Set-WinMintFirstLogonEnvironmentValue -Name 'XDG_CACHE_HOME' -Value '%USERPROFILE%\.cache'
    Set-WinMintFirstLogonEnvironmentValue -Name 'XDG_RUNTIME_DIR' -Value $xdgRuntimeDir
    Add-WinMintFirstLogonUserPath -Path (Join-Path $env:USERPROFILE 'bin')
    Add-WinMintFirstLogonUserPath -Path (Join-Path $env:USERPROFILE '.local\bin')
    "$(Get-Date -Format 'o') Set XDG defaults: config/data/state/cache + runtime dir; added user bin paths." | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
}

function Add-WinMintFirstLogonUserPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($part in ([string]$current -split ';')) {
        if (-not [string]::IsNullOrWhiteSpace($part)) { $parts.Add($part.Trim()) | Out-Null }
    }
    if (@($parts | Where-Object { $_ -ieq $Path }).Count -eq 0) {
        $parts.Add($Path) | Out-Null
        [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
        $env:PATH = "$env:PATH;$Path"
    }
}

function Set-WinMintFirstLogonClipboardDefaults {
    $clipboardKey = 'HKCU\Software\Microsoft\Clipboard'
    Invoke-WinMintFirstLogonReg -Arguments @('add', $clipboardKey, '/v', 'EnableClipboardHistory', '/t', 'REG_DWORD', '/d', '1', '/f') -AllowFailure
    Invoke-WinMintFirstLogonReg -Arguments @('add', $clipboardKey, '/v', 'CloudClipboardAutomaticUpload', '/t', 'REG_DWORD', '/d', '0', '/f') -AllowFailure
    "$(Get-Date -Format 'o') Clipboard defaults applied: local history on, cloud upload off." | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
}

function Set-WinMintFirstLogonQuietUxDefaults {
    $contentDeliveryKey = 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($name in @(
            'SubscribedContent-310093Enabled',
            'SubscribedContent-338388Enabled',
            'SubscribedContent-338389Enabled',
            'SubscribedContent-338393Enabled',
            'SubscribedContent-353694Enabled',
            'SubscribedContent-353696Enabled',
            'SubscribedContent-353698Enabled',
            'SoftLandingEnabled',
            'SystemPaneSuggestionsEnabled',
            'SilentInstalledAppsEnabled',
            'PreInstalledAppsEnabled',
            'OemPreInstalledAppsEnabled',
            'RotatingLockScreenEnabled',
            'RotatingLockScreenOverlayEnabled'
        )) {
        Invoke-WinMintFirstLogonReg -Arguments @('add', $contentDeliveryKey, '/v', $name, '/t', 'REG_DWORD', '/d', '0', '/f') -AllowFailure
    }

    $advancedKey = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    foreach ($entry in @(
            @{ Name = 'ShowTaskViewButton'; Data = '0' },
            @{ Name = 'TaskbarDa'; Data = '0' },
            @{ Name = 'TaskbarMn'; Data = '0' },
            @{ Name = 'ShowCopilotButton'; Data = '0' },
            @{ Name = 'Start_AccountNotifications'; Data = '0' }
        )) {
        Invoke-WinMintFirstLogonReg -Arguments @('add', $advancedKey, '/v', $entry.Name, '/t', 'REG_DWORD', '/d', $entry.Data, '/f') -AllowFailure
    }

    Invoke-WinMintFirstLogonReg -Arguments @('add', 'HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings', '/v', 'IsDynamicSearchBoxEnabled', '/t', 'REG_DWORD', '/d', '0', '/f') -AllowFailure
    Invoke-WinMintFirstLogonReg -Arguments @('add', 'HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement', '/v', 'ScoobeSystemSettingEnabled', '/t', 'REG_DWORD', '/d', '0', '/f') -AllowFailure
    foreach ($toastId in @('Windows.SystemToast.BackupReminder', 'Windows.SystemToast.Suggested')) {
        $toastKey = "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\$toastId"
        Invoke-WinMintFirstLogonReg -Arguments @('add', $toastKey, '/v', 'Enabled', '/t', 'REG_DWORD', '/d', '0', '/f') -AllowFailure
    }
    Invoke-WinMintFirstLogonReg -Arguments @('add', 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer', '/v', 'EnableAutoTray', '/t', 'REG_DWORD', '/d', '1', '/f') -AllowFailure
    "$(Get-Date -Format 'o') Quiet UX defaults applied: setup prompts, Spotlight, taskbar affordances, and noisy system toasts disabled." |
        Out-File (Join-Path $logDir 'FirstLogon.log') -Append
}

function Set-WinMintFirstLogonAutoLogonPersistent {
    # Keep auto sign-in alive across EVERY install reboot until the agent completes.
    # Windows clears DefaultPassword once the unattend AutoLogonCount is consumed, so a
    # later reboot would land on a password prompt. Re-establish the FULL autologon here -
    # AutoAdminLogon + DefaultUserName/DefaultDomainName + DefaultPassword - from the
    # staged setup profile, and delete AutoLogonCount so it is unlimited. The agent can
    # reboot mid-run; this guarantees the next boot signs in automatically without a
    # prompt. Disabled and wiped only on success (Disable-WinMintAutoAdminLogon /
    # Clear-WinMintAutoLogonPassword).
    $winlogon = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Invoke-WinMintFirstLogonReg -Arguments @('add', $winlogon, '/v', 'AutoAdminLogon', '/t', 'REG_SZ', '/d', '1', '/f') -AllowFailure
    Invoke-WinMintFirstLogonReg -Arguments @('delete', $winlogon, '/v', 'AutoLogonCount', '/f') -AllowFailure

    # Re-stamp the credentials so autologon survives even after Windows clears them.
    try {
        $setupProfile = Read-WinMintFirstLogonSetupProfile
        $account = if ($setupProfile -and $setupProfile.PSObject.Properties['account']) { $setupProfile.account } else { $null }
        if ($account -and [bool]($account.PSObject.Properties['autoLogon'] -and $account.autoLogon)) {
            $userName = [string]$account.userName
            $password = [string]$account.password
            if (-not [string]::IsNullOrEmpty($userName)) {
                Invoke-WinMintFirstLogonReg -Arguments @('add', $winlogon, '/v', 'DefaultUserName', '/t', 'REG_SZ', '/d', $userName, '/f') -AllowFailure
                # Local account: the autologon domain is the computer name.
                Invoke-WinMintFirstLogonReg -Arguments @('add', $winlogon, '/v', 'DefaultDomainName', '/t', 'REG_SZ', '/d', $env:COMPUTERNAME, '/f') -AllowFailure
            }
            if (-not [string]::IsNullOrEmpty($password)) {
                Invoke-WinMintFirstLogonReg -Arguments @('add', $winlogon, '/v', 'DefaultPassword', '/t', 'REG_SZ', '/d', $password, '/f') -AllowFailure
            }
        }
    }
    catch {
        Write-WinMintFirstLogonError "Autologon credential re-stamp failed: $_"
    }
}

function Set-WinMintFirstLogonLocationServicesPolicy {
    param([bool]$Enabled)

    $policyPath = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'
    $findMyDevicePath = 'HKLM\SOFTWARE\Policies\Microsoft\FindMyDevice'
    if ($Enabled) {
        foreach ($name in @('DisableLocation', 'DisableWindowsLocationProvider', 'DisableLocationScripting')) {
            Invoke-WinMintFirstLogonReg -Arguments @('delete', $policyPath, '/v', $name, '/f') -AllowFailure
        }
        Invoke-WinMintFirstLogonReg -Arguments @('delete', $findMyDevicePath, '/v', 'AllowFindMyDevice', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', 'HKLM\SYSTEM\CurrentControlSet\Services\lfsvc', '/v', 'Start', '/t', 'REG_DWORD', '/d', '3', '/f') -AllowFailure
        try { Set-Service -Name lfsvc -StartupType Manual -ErrorAction SilentlyContinue } catch { }
    }
    else {
        Invoke-WinMintFirstLogonReg -Arguments @('add', $policyPath, '/v', 'DisableLocation', '/t', 'REG_DWORD', '/d', '1', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $policyPath, '/v', 'DisableWindowsLocationProvider', '/t', 'REG_DWORD', '/d', '1', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $policyPath, '/v', 'DisableLocationScripting', '/t', 'REG_DWORD', '/d', '1', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $findMyDevicePath, '/v', 'AllowFindMyDevice', '/t', 'REG_DWORD', '/d', '0', '/f') -AllowFailure
    }
}

function Get-WinMintFirstLogonServiceSnapshot {
    param([string]$Name)
    try {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        $start = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -Name Start -ErrorAction SilentlyContinue).Start
        if (-not $svc) { return [ordered]@{ name = $Name; present = $false; status = ''; start = $start } }
        return [ordered]@{ name = $Name; present = $true; status = [string]$svc.Status; startType = [string]$svc.StartType; start = $start }
    }
    catch {
        return [ordered]@{ name = $Name; present = $false; status = ''; startType = ''; start = $null; error = $_.Exception.Message }
    }
}

function Restore-WinMintDmaRegionalDefaults {
    $setupProfile = Read-WinMintFirstLogonSetupProfile
    $dmaInterop = [bool](Get-WinMintFirstLogonNestedProfileValue -BuildProfile $setupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'enabled' -Default $false)
    $reportPath = Join-Path $logDir 'FirstLogon_RegionalRestore.json'
    if (-not $dmaInterop) {
        $report = [ordered]@{
            enabled = $false
            compliant = $true
            errors = @()
        }
        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
        return [pscustomobject]@{ Enabled = $false; Compliant = $true; Report = $reportPath }
    }

    $errors = [System.Collections.Generic.List[string]]::new()
    $setupCountry = [string](Get-WinMintFirstLogonNestedProfileValue -BuildProfile $setupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'setupCountry' -Default 'Ireland')
    $setupUserLocale = [string](Get-WinMintFirstLogonNestedProfileValue -BuildProfile $setupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'setupUserLocale' -Default 'en-IE')
    $setupGeoId = [int](Get-WinMintFirstLogonNestedProfileValue -BuildProfile $setupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'setupHomeLocationGeoId' -Default 68)
    $restoreTimeZoneId = [string](Get-WinMintFirstLogonNestedProfileValue -BuildProfile $setupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'restoreTimeZoneId' -Default '')
    $restoreGeoId = [int](Get-WinMintFirstLogonNestedProfileValue -BuildProfile $setupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'restoreHomeLocationGeoId' -Default 244)
    $restoreUserLocale = [string](Get-WinMintFirstLogonNestedProfileValue -BuildProfile $setupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'restoreUserLocale' -Default '')
    $restoreLocationServices = [bool](Get-WinMintFirstLogonNestedProfileValue -BuildProfile $setupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'restoreLocationServices' -Default $true)
    if ([string]::IsNullOrWhiteSpace($restoreTimeZoneId) -and $setupProfile -and $setupProfile.PSObject.Properties['regional']) {
        $regionalTimeZoneProp = $setupProfile.regional.PSObject.Properties['timeZoneId']
        if ($regionalTimeZoneProp) { $restoreTimeZoneId = [string]$regionalTimeZoneProp.Value }
    }
    if (-not [string]::IsNullOrWhiteSpace($restoreTimeZoneId)) {
        try {
            Set-TimeZone -Id $restoreTimeZoneId -ErrorAction Stop
            "$(Get-Date -Format 'o') Restored Windows time zone to $restoreTimeZoneId after DMA setup." |
                Out-File (Join-Path $logDir 'FirstLogon.log') -Append
        }
        catch {
            $errors.Add("Time zone restore failed for ${restoreTimeZoneId}: $_") | Out-Null
            Write-WinMintFirstLogonError "Time zone restore failed for ${restoreTimeZoneId}: $_"
        }
    }
    try {
        Set-WinHomeLocation -GeoId $restoreGeoId -ErrorAction Stop
        "$(Get-Date -Format 'o') Restored Windows home location GeoID to $restoreGeoId after DMA setup." |
            Out-File (Join-Path $logDir 'FirstLogon.log') -Append
    }
    catch {
        $errors.Add("Home location restore failed for GeoID ${restoreGeoId}: $_") | Out-Null
        Write-WinMintFirstLogonError "Home location restore failed for GeoID ${restoreGeoId}: $_"
    }
    if (-not [string]::IsNullOrWhiteSpace($restoreUserLocale)) {
        try {
            Set-Culture -CultureInfo $restoreUserLocale -ErrorAction Stop
            "$(Get-Date -Format 'o') Restored user culture to $restoreUserLocale after DMA setup." |
                Out-File (Join-Path $logDir 'FirstLogon.log') -Append
        }
        catch {
            $errors.Add("User culture restore failed for ${restoreUserLocale}: $_") | Out-Null
            Write-WinMintFirstLogonError "User culture restore failed for ${restoreUserLocale}: $_"
        }
        # Rebuild the user language list as [display language] + [secondary input languages].
        # This drops the DMA en-IE entry AND adds any configured secondary keyboards (e.g.
        # he-IL), with the display language pinned so it can never switch. Done BEFORE the
        # system/new-user copy below so the result propagates to the welcome screen + new-user
        # defaults.
        $secondaryInputLanguages = @()
        if ($setupProfile -and $setupProfile.PSObject.Properties['regional'] -and $setupProfile.regional.PSObject.Properties['secondaryInputLanguages']) {
            $secondaryInputLanguages = @($setupProfile.regional.secondaryInputLanguages)
        }
        try {
            Set-WinMintFirstLogonInputLanguages -DisplayLanguage $restoreUserLocale -SecondaryInputLanguages $secondaryInputLanguages
        }
        catch {
            $errors.Add("Language list rebuild failed: $_") | Out-Null
            Write-WinMintFirstLogonError "Language list rebuild failed: $_"
        }
    }
    try {
        if (Get-Command Copy-UserInternationalSettingsToSystem -ErrorAction SilentlyContinue) {
            Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true -ErrorAction Stop
            "$(Get-Date -Format 'o') Copied restored international settings to system and new-user defaults." |
                Out-File (Join-Path $logDir 'FirstLogon.log') -Append
        }
    }
    catch {
        $errors.Add("International settings copy failed: $_") | Out-Null
        Write-WinMintFirstLogonError "International settings copy failed: $_"
    }
    try { Set-WinMintFirstLogonLocationServicesPolicy -Enabled $restoreLocationServices }
    catch {
        $errors.Add("Location services policy restore failed: $_") | Out-Null
        Write-WinMintFirstLogonError "Location services policy restore failed: $_"
    }
    if (-not $restoreLocationServices) {
        try {
            Invoke-WinMintFirstLogonReg -Arguments @('add', 'HKLM\SYSTEM\CurrentControlSet\Services\tzautoupdate', '/v', 'Start', '/t', 'REG_DWORD', '/d', '4', '/f') -AllowFailure
            Stop-Service -Name tzautoupdate -ErrorAction SilentlyContinue
            Set-Service -Name tzautoupdate -StartupType Disabled -ErrorAction Stop
            "$(Get-Date -Format 'o') Disabled Auto Time Zone Updater because location services are off." |
                Out-File (Join-Path $logDir 'FirstLogon.log') -Append
        }
        catch {
            $errors.Add("Auto Time Zone Updater disable failed after DMA setup: $_") | Out-Null
            Write-WinMintFirstLogonError "Auto Time Zone Updater disable failed after DMA setup: $_"
        }
    }
    else {
        try {
            Invoke-WinMintFirstLogonReg -Arguments @('add', 'HKLM\SYSTEM\CurrentControlSet\Services\tzautoupdate', '/v', 'Start', '/t', 'REG_DWORD', '/d', '3', '/f') -AllowFailure
            Set-Service -Name tzautoupdate -StartupType Manual -ErrorAction Stop
        }
        catch {
            $errors.Add("Auto Time Zone Updater enable failed after DMA setup: $_") | Out-Null
            Write-WinMintFirstLogonError "Auto Time Zone Updater enable failed after DMA setup: $_"
        }
        "$(Get-Date -Format 'o') Enabled Auto Time Zone Updater because location services are on." |
            Out-File (Join-Path $logDir 'FirstLogon.log') -Append
    }

    $observedTimeZone = $null
    $observedHomeLocation = $null
    $observedCulture = $null
    try { $observedTimeZone = Get-TimeZone } catch { $errors.Add("Time zone verification failed: $_") | Out-Null }
    try { $observedHomeLocation = Get-WinHomeLocation } catch { $errors.Add("Home location verification failed: $_") | Out-Null }
    try { $observedCulture = Get-Culture } catch { $errors.Add("Culture verification failed: $_") | Out-Null }

    $observedGeoIdText = if ($observedHomeLocation) { [string]([int]$observedHomeLocation.GeoId) } else { '0' }
    $observedTimeZoneText = if ($observedTimeZone) { [string]$observedTimeZone.Id } else { '' }
    $observedCultureText = if ($observedCulture) { [string]$observedCulture.Name } else { '' }
    if ($restoreGeoId -gt 0 -and (-not $observedHomeLocation -or [int]$observedHomeLocation.GeoId -ne $restoreGeoId)) {
        $errors.Add("Current home location GeoID '$observedGeoIdText' does not match restore GeoID '$restoreGeoId'.") | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($restoreTimeZoneId) -and (-not $observedTimeZone -or [string]$observedTimeZone.Id -ne $restoreTimeZoneId)) {
        $errors.Add("Current time zone '$observedTimeZoneText' does not match restore time zone '$restoreTimeZoneId'.") | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($restoreUserLocale) -and (-not $observedCulture -or [string]$observedCulture.Name -ne $restoreUserLocale)) {
        $errors.Add("Current culture '$observedCultureText' does not match restore culture '$restoreUserLocale'.") | Out-Null
    }

    $report = [ordered]@{
        enabled = $true
        requested = [ordered]@{
            setupCountry = $setupCountry
            setupUserLocale = $setupUserLocale
            setupHomeLocationGeoId = $setupGeoId
            restoreTimeZoneId = $restoreTimeZoneId
            restoreUserLocale = $restoreUserLocale
            restoreHomeLocationGeoId = $restoreGeoId
            restoreLocationServices = $restoreLocationServices
        }
        observed = [ordered]@{
            timeZoneId = if ($observedTimeZone) { [string]$observedTimeZone.Id } else { '' }
            culture = if ($observedCulture) { [string]$observedCulture.Name } else { '' }
            homeLocationGeoId = if ($observedHomeLocation) { [int]$observedHomeLocation.GeoId } else { 0 }
            homeLocation = if ($observedHomeLocation) { [string]$observedHomeLocation.HomeLocation } else { '' }
            tzautoupdate = Get-WinMintFirstLogonServiceSnapshot -Name 'tzautoupdate'
            locationService = Get-WinMintFirstLogonServiceSnapshot -Name 'lfsvc'
        }
        compliant = ($errors.Count -eq 0)
        errors = $errors.ToArray()
    }
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    return [pscustomobject]@{ Enabled = $true; Compliant = [bool]$report.compliant; Report = $reportPath; Errors = $errors.ToArray() }
}

function Repair-WinMintFirstLogonKnownFolders {
    $errors = [System.Collections.Generic.List[string]]::new()
    $userShellFolders = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $shellFolders = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'
    $knownFolders = @(
        @{ Name = 'Desktop'; Local = 'Desktop' },
        @{ Name = 'Personal'; Local = 'Documents' },
        @{ Name = 'My Pictures'; Local = 'Pictures' },
        @{ Name = 'My Music'; Local = 'Music' },
        @{ Name = 'My Video'; Local = 'Videos' },
        @{ Name = '{374DE290-123F-4565-9164-39C4925E467B}'; Local = 'Downloads' }
    )

    foreach ($folder in @('Desktop', 'Documents', 'Downloads', 'Pictures', 'Music', 'Videos')) {
        New-Item -ItemType Directory -Path (Join-Path $env:USERPROFILE $folder) -Force -ErrorAction SilentlyContinue | Out-Null
    }

    foreach ($known in $knownFolders) {
        $expandValue = "%USERPROFILE%\$($known.Local)"
        $absoluteValue = Join-Path $env:USERPROFILE $known.Local
        try {
            Invoke-WinMintFirstLogonReg -Arguments @('add', $userShellFolders, '/v', $known.Name, '/t', 'REG_EXPAND_SZ', '/d', $expandValue, '/f') -AllowFailure
            Invoke-WinMintFirstLogonReg -Arguments @('add', $shellFolders, '/v', $known.Name, '/t', 'REG_SZ', '/d', $absoluteValue, '/f') -AllowFailure
        }
        catch {
            $errors.Add("Known folder repair failed for $($known.Name): $_") | Out-Null
        }
    }

    $userShell = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
    $shell = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' -ErrorAction SilentlyContinue
    $observed = [ordered]@{}
    foreach ($known in $knownFolders) {
        $userProp = if ($userShell) { $userShell.PSObject.Properties[$known.Name] } else { $null }
        $shellProp = if ($shell) { $shell.PSObject.Properties[$known.Name] } else { $null }
        $observed[$known.Name] = [ordered]@{
            userShellFolder = if ($userProp) { [string]$userProp.Value } else { '' }
            shellFolder = if ($shellProp) { [string]$shellProp.Value } else { '' }
        }
    }

    $report = [ordered]@{
        timestamp = Get-Date -Format o
        expectedRoot = '%USERPROFILE%'
        observed = $observed
        compliant = ($errors.Count -eq 0)
        errors = $errors.ToArray()
    }
    $path = Join-Path $logDir 'FirstLogon_KnownFolders.json'
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    "$(Get-Date -Format 'o') Known folder verification written to $path" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
}

function Invoke-WinMintFirstLogonOneDriveRemoval {
    "$(Get-Date -Format 'o') Removing OneDrive user integration" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
    foreach ($name in @('OneDrive', 'OneDriveSetup')) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    foreach ($setup in @(
            "$env:SystemRoot\System32\OneDriveSetup.exe",
            "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
            "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
        )) {
        if (Test-Path -LiteralPath $setup) {
            try {
                Start-Process -FilePath $setup -ArgumentList '/uninstall' -WindowStyle Hidden -Wait -ErrorAction Stop | Out-Null
            }
            catch {
                Write-WinMintFirstLogonError "OneDrive uninstall failed for ${setup}: $_"
            }
        }
    }

    $setupFiles = @(
        "$env:SystemRoot\System32\OneDriveSetup.exe",
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
        "$env:SystemRoot\System32\OneDriveSetup.exe.bak",
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe.bak",
        "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
    )
    foreach ($setupFile in $setupFiles) {
        if (-not (Test-Path -LiteralPath $setupFile)) { continue }
        try {
            takeown.exe /f $setupFile | Out-Null
            icacls.exe $setupFile /grant '*S-1-5-32-544:F' | Out-Null
            Remove-Item -LiteralPath $setupFile -Force -ErrorAction Stop
        }
        catch {
            Write-WinMintFirstLogonError "OneDrive installer file removal failed for ${setupFile}: $_"
        }
    }

    foreach ($folder in @('Desktop', 'Documents', 'Downloads', 'Pictures', 'Music', 'Videos')) {
        New-Item -ItemType Directory -Path (Join-Path $env:USERPROFILE $folder) -Force -ErrorAction SilentlyContinue | Out-Null
    }

    $userShellFolders = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $shellFolders = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'
    $knownFolders = @(
        @{ Name = 'Desktop'; Local = 'Desktop' },
        @{ Name = 'Personal'; Local = 'Documents' },
        @{ Name = 'My Pictures'; Local = 'Pictures' },
        @{ Name = 'My Music'; Local = 'Music' },
        @{ Name = 'My Video'; Local = 'Videos' },
        @{ Name = '{374DE290-123F-4565-9164-39C4925E467B}'; Local = 'Downloads' }
    )
    foreach ($known in $knownFolders) {
        $expandValue = "%USERPROFILE%\$($known.Local)"
        $absoluteValue = Join-Path $env:USERPROFILE $known.Local
        Invoke-WinMintFirstLogonReg -Arguments @('add', $userShellFolders, '/v', $known.Name, '/t', 'REG_EXPAND_SZ', '/d', $expandValue, '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $shellFolders, '/v', $known.Name, '/t', 'REG_SZ', '/d', $absoluteValue, '/f') -AllowFailure
    }

    foreach ($regArgs in @(
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableFileSync', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableFileSyncNGSC', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisablePersonalSync', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableLibrariesDefaultSaveToOneDrive', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKCR\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}', '/v', 'System.IsPinnedToNameSpaceTree', '/t', 'REG_DWORD', '/d', '0', '/f'),
            @('add', 'HKCR\WOW6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}', '/v', 'System.IsPinnedToNameSpaceTree', '/t', 'REG_DWORD', '/d', '0', '/f')
        )) {
        Invoke-WinMintFirstLogonReg -Arguments $regArgs -AllowFailure
    }

    foreach ($runKey in @(
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run',
            'HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
            'HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            'HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        )) {
        foreach ($value in @('OneDrive', 'OneDriveSetup')) {
            Invoke-WinMintFirstLogonReg -Arguments @('delete', $runKey, '/v', $value, '/f') -AllowFailure
        }
    }

    foreach ($root in @(
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Active Setup\Installed Components',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Active Setup\Installed Components',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
            'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\App Paths',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
            'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SyncRootManager',
            'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace'
        )) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            $text = @(
                $key.PSChildName
                if ($props) { $props.PSObject.Properties | ForEach-Object { [string]$_.Value } }
            ) -join "`n"
            if ($text -match '(?i)OneDrive|OneDriveSetup\.exe') {
                try {
                    Remove-Item -LiteralPath $key.PSPath -Recurse -Force -ErrorAction Stop
                }
                catch {
                    Write-WinMintFirstLogonError "OneDrive registry residue removal failed for $($key.Name): $_"
                }
            }
        }
    }

    Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object {
            $_.TaskName -match '(?i)OneDrive' -or
            $_.TaskPath -match '(?i)OneDrive' -or
            @($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -match '(?i)OneDrive|OneDriveSetup\.exe'
        } |
        Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue

    Remove-Item -LiteralPath @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive",
        "$env:ProgramData\Microsoft OneDrive",
        "$env:SystemDrive\OneDriveTemp"
    ) -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\OneDrive*.lnk" -Force -ErrorAction SilentlyContinue

    $oneDriveRoots = @(
        Join-Path $env:USERPROFILE 'OneDrive'
        Get-ChildItem -LiteralPath $env:USERPROFILE -Directory -Filter 'OneDrive -*' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
    )
    foreach ($root in @($oneDriveRoots | Where-Object { $_ -and (Test-Path -LiteralPath $_) })) {
        $children = @(Get-ChildItem -LiteralPath $root -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($children.Count -eq 0) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
        else {
            Write-WinMintFirstLogonError "OneDrive folder not removed because it contains files: $root"
        }
    }

    $policy = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' -ErrorAction SilentlyContinue
    $userShell = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
    $shellFolderAudit = @{}
    foreach ($known in $knownFolders) {
        $property = if ($userShell) { $userShell.PSObject.Properties[$known.Name] } else { $null }
        $shellFolderAudit[$known.Name] = if ($property) { $property.Value } else { $null }
    }
    $runResidue = foreach ($runKey in @(
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
            'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run',
            'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\RunOnce',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        )) {
        $props = Get-ItemProperty -LiteralPath $runKey -ErrorAction SilentlyContinue
        foreach ($value in @('OneDrive', 'OneDriveSetup')) {
            $property = if ($props) { $props.PSObject.Properties[$value] } else { $null }
            if ($property) { [ordered]@{ path = $runKey; name = $value; value = $property.Value } }
        }
    }
    $registryResidue = foreach ($root in @(
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Active Setup\Installed Components',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Active Setup\Installed Components',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
            'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\App Paths',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
            'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SyncRootManager',
            'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace'
        )) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            $text = @(
                $key.PSChildName
                if ($props) { $props.PSObject.Properties | ForEach-Object { [string]$_.Value } }
            ) -join "`n"
            if ($text -match '(?i)OneDrive|OneDriveSetup\.exe') {
                [ordered]@{ path = $key.Name }
            }
        }
    }
    $oneDriveAudit = [ordered]@{
        timestamp = Get-Date -Format o
        installerFiles = @($setupFiles | ForEach-Object {
                [ordered]@{ path = $_; exists = [bool](Test-Path -LiteralPath $_) }
            })
        policy = [ordered]@{
            disableFileSync = if ($policy) { $policy.DisableFileSync } else { $null }
            disableFileSyncNGSC = if ($policy) { $policy.DisableFileSyncNGSC } else { $null }
            disablePersonalSync = if ($policy) { $policy.DisablePersonalSync } else { $null }
            disableLibrariesDefaultSaveToOneDrive = if ($policy) { $policy.DisableLibrariesDefaultSaveToOneDrive } else { $null }
        }
        shellFolders = $shellFolderAudit
        namespacePinned = [ordered]@{
            clsid64 = (Get-ItemProperty `
                    -LiteralPath 'Registry::HKEY_CLASSES_ROOT\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' `
                    -Name 'System.IsPinnedToNameSpaceTree' `
                    -ErrorAction SilentlyContinue).'System.IsPinnedToNameSpaceTree'
            clsid32 = (Get-ItemProperty `
                    -LiteralPath 'Registry::HKEY_CLASSES_ROOT\WOW6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' `
                    -Name 'System.IsPinnedToNameSpaceTree' `
                    -ErrorAction SilentlyContinue).'System.IsPinnedToNameSpaceTree'
        }
        scheduledTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.TaskName -match '(?i)OneDrive' -or
                    $_.TaskPath -match '(?i)OneDrive' -or
                    @($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -match '(?i)OneDrive|OneDriveSetup\.exe'
                } |
                ForEach-Object { "$($_.TaskPath)$($_.TaskName)" })
        runResidue = @($runResidue)
        registryResidue = @($registryResidue)
        leftoverFolders = @($oneDriveRoots | Where-Object { $_ } | ForEach-Object {
                [ordered]@{ path = $_; exists = [bool](Test-Path -LiteralPath $_) }
            })
    }
    $oneDriveAudit['compliant'] = (
        @($oneDriveAudit.installerFiles | Where-Object exists).Count -eq 0 -and
        $null -ne $oneDriveAudit.policy.disableFileSync -and [int]$oneDriveAudit.policy.disableFileSync -eq 1 -and
        $null -ne $oneDriveAudit.policy.disableFileSyncNGSC -and [int]$oneDriveAudit.policy.disableFileSyncNGSC -eq 1 -and
        $null -ne $oneDriveAudit.policy.disablePersonalSync -and [int]$oneDriveAudit.policy.disablePersonalSync -eq 1 -and
        $null -ne $oneDriveAudit.policy.disableLibrariesDefaultSaveToOneDrive -and [int]$oneDriveAudit.policy.disableLibrariesDefaultSaveToOneDrive -eq 1 -and
        $null -ne $oneDriveAudit.namespacePinned.clsid64 -and [int]$oneDriveAudit.namespacePinned.clsid64 -eq 0 -and
        $null -ne $oneDriveAudit.namespacePinned.clsid32 -and [int]$oneDriveAudit.namespacePinned.clsid32 -eq 0 -and
        @($oneDriveAudit.scheduledTasks).Count -eq 0 -and
        @($oneDriveAudit.runResidue).Count -eq 0 -and
        @($oneDriveAudit.registryResidue).Count -eq 0
    )
    $oneDriveAuditPath = Join-Path $logDir 'FirstLogon_OneDriveAudit.json'
    $oneDriveAudit | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $oneDriveAuditPath -Encoding UTF8
    "$(Get-Date -Format 'o') OneDrive audit written to $oneDriveAuditPath" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
}

function Disable-WinMintAutoAdminLogon {
    $winlogon = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Invoke-WinMintFirstLogonReg -Arguments @('add', $winlogon, '/v', 'AutoAdminLogon', '/t', 'REG_SZ', '/d', '0', '/f')
}

function Clear-WinMintFirstLogonRecovery {
    try { Clear-WinMintFirstLogonRetry } catch { Write-WinMintFirstLogonError "FirstLogon retry cleanup failed: $_" }
    try { Invoke-WinMintFirstLogonReg -Arguments @('delete', 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce', '/v', 'WinMintFirstLogon', '/f') -AllowFailure }
    catch { Write-WinMintFirstLogonError "HKLM RunOnce cleanup failed: $_" }
    try { Disable-WinMintAutoAdminLogon } catch { Write-WinMintFirstLogonError "AutoAdminLogon disable failed: $_" }
    try { Clear-WinMintAutoLogonPassword } catch { Write-WinMintFirstLogonError "AutoLogon password cleanup failed: $_" }
}

function Remove-WinMintResidualPayload {
    # No-trace cleanup after a SUCCESSFUL run: the FirstLogon experience is meant to be
    # transient. Remove WinMint-owned setup payloads without deleting the whole
    # C:\Windows\Setup\Scripts directory, which may contain OEM/source-ISO files.
    # The user's own saved verification report (on the Desktop, only if they clicked Save) is
    # untouched. The removals run via a detached PowerShell host after a short delay so this
    # still-running script and transcript release their file handles first.
    $fileNames = @(
        'Audit-LiveInstall.ps1',
        'DefaultUser.ps1',
        'FirstLogon.ps1',
        'SetupComplete.cmd',
        'SetupComplete.ps1',
        'Specialize.ps1',
        'WinMintSetupPlan.json',
        'WinMintSetupProfile.json'
    )
    $programDataRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    if ([string]::IsNullOrWhiteSpace($programDataRoot)) { $programDataRoot = $env:ProgramData }
    $localAppDataRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localAppDataRoot)) { $localAppDataRoot = $env:LOCALAPPDATA }
    $payloadDirectoryNames = @('SetupComplete', 'WinMintAgent')
    $fileTargets = $fileNames | ForEach-Object { Join-Path $payloadDir $_ }
    $directoryTargets = @(
        @($payloadDirectoryNames | ForEach-Object { Join-Path $payloadDir $_ })
        (Join-Path $programDataRoot 'WinMint'),
        (Join-Path $localAppDataRoot 'WinMint')
    )
    $cleanupSpec = [ordered]@{
        payloadRoot = $payloadDir
        fileNames = @($fileNames)
        payloadDirectoryNames = @($payloadDirectoryNames)
        stateRoots = @($programDataRoot, $localAppDataRoot)
        stateDirectoryName = 'WinMint'
        fileTargets = @($fileTargets)
        directoryTargets = @($directoryTargets)
    }
    $cleanupSpecJson = $cleanupSpec | ConvertTo-Json -Depth 5 -Compress
    $cleanupSpecBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($cleanupSpecJson))
    $cleanupScript = @"
`$ErrorActionPreference = 'Continue'
Start-Sleep -Seconds 4
`$specJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$cleanupSpecBase64'))
`$spec = `$specJson | ConvertFrom-Json
function Resolve-WinMintCleanupPath {
    param([Parameter(Mandatory)][string]`$Path)
    try { return [IO.Path]::GetFullPath(`$Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) }
    catch { return '' }
}
`$payloadRoot = Resolve-WinMintCleanupPath -Path ([string]`$spec.payloadRoot)
`$fileNames = @(`$spec.fileNames | ForEach-Object { [string]`$_ })
`$payloadDirectoryNames = @(`$spec.payloadDirectoryNames | ForEach-Object { [string]`$_ })
`$stateRoots = @(`$spec.stateRoots | ForEach-Object { Resolve-WinMintCleanupPath -Path ([string]`$_) } | Where-Object { -not [string]::IsNullOrWhiteSpace(`$_) })
`$stateDirectoryName = [string]`$spec.stateDirectoryName
`$resolvedFileTargets = @(`$spec.fileTargets | ForEach-Object { Resolve-WinMintCleanupPath -Path ([string]`$_) } | Where-Object { -not [string]::IsNullOrWhiteSpace(`$_) })
`$resolvedDirectoryTargets = @(`$spec.directoryTargets | ForEach-Object { Resolve-WinMintCleanupPath -Path ([string]`$_) } | Where-Object { -not [string]::IsNullOrWhiteSpace(`$_) })
foreach (`$target in `$resolvedFileTargets) {
    `$parent = Resolve-WinMintCleanupPath -Path ([IO.Path]::GetDirectoryName(`$target))
    `$leaf = [IO.Path]::GetFileName(`$target)
    if (`$parent -eq `$payloadRoot -and `$fileNames -contains `$leaf -and (Test-Path -LiteralPath `$target -PathType Leaf)) {
        Remove-Item -LiteralPath `$target -Force -ErrorAction SilentlyContinue
    }
}
foreach (`$target in `$resolvedDirectoryTargets) {
    if (`$target.Length -le 3) { continue }
    `$parent = Resolve-WinMintCleanupPath -Path ([IO.Path]::GetDirectoryName(`$target))
    `$leaf = [IO.Path]::GetFileName(`$target)
    `$isPayloadDirectory = (`$parent -eq `$payloadRoot -and `$payloadDirectoryNames -contains `$leaf)
    `$isStateDirectory = (`$stateRoots -contains `$parent -and `$leaf -eq `$stateDirectoryName)
    if (-not (`$isPayloadDirectory -or `$isStateDirectory)) { continue }
    if (Test-Path -LiteralPath `$target -PathType Container) {
        Remove-Item -LiteralPath `$target -Recurse -Force -ErrorAction SilentlyContinue
    }
}
function Resolve-WinMintWindowsPowerShellHost {
    `$sysnative = Join-Path `$env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath `$sysnative) { return `$sysnative }
    `$system32 = Join-Path `$env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath `$system32) { return `$system32 }
    return 'powershell.exe'
}
try {
    `$restoreCommand = '`$ErrorActionPreference = ''Stop''; ' +
        '`$drive = `$env:SystemDrive; ' +
        'if ([string]::IsNullOrWhiteSpace(`$drive)) { `$drive = ''C:'' }; ' +
        'Enable-ComputerRestore -Drive (`$drive + ''\''); ' +
        'Checkpoint-Computer -Description ''WinMint post-install complete'' -RestorePointType MODIFY_SETTINGS'
    `$encodedRestore = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(`$restoreCommand))
    `$restoreProcess = Start-Process -FilePath (Resolve-WinMintWindowsPowerShellHost) -ArgumentList @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-EncodedCommand',
        `$encodedRestore
    ) -WindowStyle Hidden -PassThru
    if (-not `$restoreProcess.WaitForExit(600000)) {
        try { `$restoreProcess.Kill() } catch { }
    }
} catch { }
"@
    $encodedCleanup = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cleanupScript))
    try {
        Start-Process -FilePath (Resolve-WinMintPowerShellHost) -ArgumentList @(
            '-NoLogo',
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-WindowStyle',
            'Hidden',
            '-EncodedCommand',
            $encodedCleanup
        ) -WindowStyle Hidden | Out-Null
        "$(Get-Date -Format 'o') Scheduled no-trace purge and final post-install restore point." |
            Out-File (Join-Path $logDir 'FirstLogon.log') -Append
    }
    catch { Write-WinMintFirstLogonError "No-trace purge schedule failed: $_" }
}

function Stop-WinMintFirstLogonUnelevated {
    param([Parameter(Mandatory)][string]$Reason)

    Write-WinMintFirstLogonError $Reason
    Remove-Item -LiteralPath (Join-Path $logDir 'FirstLogon_self-elevation.flag') -Force -ErrorAction SilentlyContinue
    $state = New-WinMintFirstLogonRunState
    $state['status'] = 'failed'
    $state['failure'] = 'notElevated'
    $state['error'] = $Reason
    try {
        Save-WinMintFirstLogonState -State $state
    }
    catch { Write-WinMintFirstLogonError "FirstLogon state write failed: $_" }
    if ([int]$state.attempts -ge $script:WinMintFirstLogonMaxAttempts) {
        Write-WinMintFirstLogonError "FirstLogon retry cap reached ($($state.attempts)); clearing autologon recovery state."
        Clear-WinMintFirstLogonRecovery
    }
    else {
        try { Set-WinMintFirstLogonRetry } catch { Write-WinMintFirstLogonError "FirstLogon retry registration failed: $_" }
        try { Set-WinMintFirstLogonAutoLogonPersistent } catch { Write-WinMintFirstLogonError "AutoLogon persistence failed: $_" }
    }
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
    exit 1
}

# ── Elevation guarantee ───────────────────────────────────────────────────────
# FirstLogon does machine-wide work (HKLM writes, service changes, autologon teardown).
# FirstLogonCommands usually hand an elevated token, but for a CUSTOM split-token admin
# account that is not guaranteed - a filtered (standard) token would make those operations
# fail with access-denied. If this instance is not elevated, re-launch it elevated via a
# Highest-privilege scheduled task (runs with the full admin token, no UAC prompt) and let
# that instance do the work. Harmless when already elevated.
$script:WinMintElevated = $false
try {
    $script:WinMintElevated = Test-WinMintTokenElevated
}
catch { $script:WinMintElevated = $false }
"$(Get-Date -Format 'o') FirstLogon running elevated: $script:WinMintElevated" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
if (-not $script:WinMintElevated) {
    $elevFlag = Join-Path $logDir 'FirstLogon_self-elevation.flag'
    if (Test-Path -LiteralPath $elevFlag) {
        Stop-WinMintFirstLogonUnelevated -Reason 'FirstLogon is NOT elevated and self-elevation was already attempted; aborting before machine-wide setup so RunOnce can retry.'
    }
    else {
        try {
            Set-Content -LiteralPath $elevFlag -Value (Get-Date -Format o) -Encoding ASCII
            $exe = Resolve-WinMintPowerShellHost
            $taskName = 'WinMintFirstLogonElevated'
            $tr = "`"$exe`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script:WinMintFirstLogonEntryPath`""
            & schtasks.exe /Create /TN $taskName /TR $tr /SC ONCE /ST 23:59 /RL HIGHEST /F 2>&1 | Out-Null
            $elevOk = ($LASTEXITCODE -eq 0)
            if ($elevOk) { & schtasks.exe /Run /TN $taskName 2>&1 | Out-Null; $elevOk = ($LASTEXITCODE -eq 0) }
            if ($elevOk) {
                "$(Get-Date -Format 'o') FirstLogon re-launched elevated via scheduled task '$taskName'; standard-token instance exiting." | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
                try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
                exit 0
            }
            Stop-WinMintFirstLogonUnelevated -Reason 'Self-elevation scheduled task could not be created/started; aborting before machine-wide setup so RunOnce can retry.'
        }
        catch { Stop-WinMintFirstLogonUnelevated -Reason "Self-elevation failed: $_; aborting before machine-wide setup so RunOnce can retry." }
    }
}

function Invoke-WinMintFirstLogonAppxCleanup {
    $setupProfile = Read-WinMintFirstLogonSetupProfile
    $prefixes = @()
    if ($setupProfile -and $setupProfile.PSObject.Properties['appxRemovalPrefixes']) {
        $prefixes = @($setupProfile.appxRemovalPrefixes | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }
    $aiPrefixes = @()
    if ($setupProfile -and $setupProfile.PSObject.Properties['aiRemoval'] -and $setupProfile.aiRemoval.PSObject.Properties['appxPrefixes']) {
        $aiPrefixes = @($setupProfile.aiRemoval.appxPrefixes | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }
    if ($aiPrefixes.Count -gt 0) {
        $prefixes = @($prefixes | Where-Object { $_ -notin $aiPrefixes })
    }
    if ($prefixes.Count -eq 0) {
        return
    }

    $reportPath = Join-Path $logDir 'FirstLogon_AppxCleanup.json'
    $result = [ordered]@{
        generatedAt = Get-Date -Format o
        prefixes = @($prefixes)
        removedProvisioned = @()
        removedInstalled = @()
        failed = @()
    }

    foreach ($pkg in @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)) {
        $name = [string]$pkg.DisplayName
        $packageName = [string]$pkg.PackageName
        if ([string]::IsNullOrWhiteSpace($name) -and [string]::IsNullOrWhiteSpace($packageName)) { continue }
        if (-not ($prefixes | Where-Object { $name -like "*$_*" -or $packageName -like "*$_*" })) { continue }
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $packageName -ErrorAction Stop | Out-Null
            $result.removedProvisioned += [ordered]@{
                displayName = $name
                packageName = $packageName
            }
            "$(Get-Date -Format 'o') Removed provisioned AppX package: $name ($packageName)" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
        }
        catch {
            $result.failed += [ordered]@{
                kind = 'provisioned'
                name = $name
                packageName = $packageName
                error = [string]$_.Exception.Message
            }
            Write-WinMintFirstLogonError "Provisioned AppX removal failed for $name ($packageName): $_"
        }
    }

    foreach ($pkg in @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)) {
        $name = [string]$pkg.Name
        $packageFullName = [string]$pkg.PackageFullName
        if ([string]::IsNullOrWhiteSpace($name) -and [string]::IsNullOrWhiteSpace($packageFullName)) { continue }
        if (-not ($prefixes | Where-Object { $name -like "*$_*" -or $packageFullName -like "*$_*" })) { continue }
        try {
            Remove-AppxPackage -Package $packageFullName -AllUsers -ErrorAction Stop
            $result.removedInstalled += [ordered]@{
                name = $name
                packageFullName = $packageFullName
            }
            "$(Get-Date -Format 'o') Removed installed AppX package: $name ($packageFullName)" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
        }
        catch {
            $result.failed += [ordered]@{
                kind = 'installed'
                name = $name
                packageFullName = $packageFullName
                error = [string]$_.Exception.Message
            }
            Write-WinMintFirstLogonError "Installed AppX removal failed for $name ($packageFullName): $_"
        }
    }

    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
}

