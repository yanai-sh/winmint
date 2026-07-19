#Requires -Version 5.1

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


function Invoke-WinMintFirstLogonOneDriveRemoval {
    "$(Get-Date -Format 'o') Removing OneDrive user integration" | Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
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
    $oneDriveAuditPath = Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon_OneDriveAudit.json'
    $oneDriveAudit | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $oneDriveAuditPath -Encoding UTF8
    "$(Get-Date -Format 'o') OneDrive audit written to $oneDriveAuditPath" | Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
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
    $ctx = Get-WinMintFirstLogonContext
    $payloadDirectoryNames = @('SetupComplete', 'WinMintAgent')
    $fileTargets = $fileNames | ForEach-Object { Join-Path $ctx.PayloadDir $_ }
    $retainDiagnosticState = Test-WinMintSetupRetainFirstLogonArtifacts
    $directoryTargets = @($payloadDirectoryNames | ForEach-Object { Join-Path $ctx.PayloadDir $_ })
    if (-not $retainDiagnosticState) {
        $directoryTargets += @(
            (Join-Path $programDataRoot 'WinMint'),
            (Join-Path $localAppDataRoot 'WinMint')
        )
    }
    $cleanupSpec = [ordered]@{
        payloadRoot = $ctx.PayloadDir
        fileNames = @($fileNames)
        payloadDirectoryNames = @($payloadDirectoryNames)
        stateRoots = @($programDataRoot, $localAppDataRoot)
        stateDirectoryName = 'WinMint'
        retainDiagnosticState = $retainDiagnosticState
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
        if ($retainDiagnosticState) {
            "$(Get-Date -Format 'o') Scheduled payload purge and final post-install restore point; profile diagnostic artifacts retained." |
                Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
        }
        else {
            "$(Get-Date -Format 'o') Scheduled no-trace purge and final post-install restore point." |
                Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
        }
    }
    catch { Write-WinMintFirstLogonError "No-trace purge schedule failed: $_" }
}

function Get-WinMintFirstLogonAppxSystemExemptResolution {
    $setupProfile = Read-WinMintFirstLogonSetupProfile
    if ($setupProfile -and $setupProfile.PSObject.Properties['appxSystemExemptPrefixes']) {
        $prefixes = @($setupProfile.appxSystemExemptPrefixes | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        return [pscustomobject]@{
            Prefixes = $prefixes
            Source   = 'setup-profile'
            Warning  = $null
        }
    }
    # No hardcoded catalog copy — stale push-only fallbacks drift from config/appx-removal.json.
    return [pscustomobject]@{
        Prefixes = @()
        Source   = 'missing'
        Warning  = 'setup profile missing appxSystemExemptPrefixes; live AppX cleanup cannot apply Tier-0 exempt filter. Restage ISO or push an updated setup profile.'
    }
}

function Get-WinMintFirstLogonAppxSystemExemptPrefixes {
    return @((Get-WinMintFirstLogonAppxSystemExemptResolution).Prefixes)
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
    $exemptResolution = Get-WinMintFirstLogonAppxSystemExemptResolution
    $systemExempt = @($exemptResolution.Prefixes)
    $skippedSystemExempt = @($prefixes | Where-Object { $_ -in $systemExempt })
    if ($systemExempt.Count -gt 0) {
        $prefixes = @($prefixes | Where-Object { $_ -notin $systemExempt })
    }
    if ($prefixes.Count -eq 0 -and [string]::IsNullOrWhiteSpace([string]$exemptResolution.Warning)) {
        return
    }

    $reportPath = Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon_AppxCleanup.json'
    $result = [ordered]@{
        generatedAt = Get-Date -Format o
        prefixes = @($prefixes)
        systemExemptSource = [string]$exemptResolution.Source
        systemExemptPrefixes = @($systemExempt)
        systemExemptWarning = [string]$exemptResolution.Warning
        skippedSystemExempt = @($skippedSystemExempt)
        removedProvisioned = @()
        removedInstalled = @()
        leftoverMatching = @()
        failed = @()
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$exemptResolution.Warning)) {
        Write-WinMintFirstLogonError ([string]$exemptResolution.Warning)
        "$(Get-Date -Format 'o') $($exemptResolution.Warning)" |
            Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
    }
    # Fail closed: without staged exempts, live removal can strip Tier-0 packages from a stale prefix list.
    if ([string]$exemptResolution.Source -eq 'missing') {
        $result.skippedBecause = 'missing-system-exempt-prefixes'
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
        return
    }
    if ($prefixes.Count -eq 0) {
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
        return
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
            "$(Get-Date -Format 'o') Removed provisioned AppX package: $name ($packageName)" | Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
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
            "$(Get-Date -Format 'o') Removed installed AppX package: $name ($packageFullName)" | Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
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

    foreach ($pkg in @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)) {
        $name = [string]$pkg.Name
        $packageFullName = [string]$pkg.PackageFullName
        if ([string]::IsNullOrWhiteSpace($name) -and [string]::IsNullOrWhiteSpace($packageFullName)) { continue }
        if (-not ($prefixes | Where-Object { $name -like "*$_*" -or $packageFullName -like "*$_*" })) { continue }
        $result.leftoverMatching += [ordered]@{
            name = $name
            packageFullName = $packageFullName
        }
    }
    if (@($result.leftoverMatching).Count -gt 0) {
        "$(Get-Date -Format 'o') Live AppX cleanup leftovers still matching removal prefixes: $(@($result.leftoverMatching.name) -join ', ')" |
            Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
    }

    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
}

