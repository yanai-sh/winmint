# SetupComplete machine-phase module: stamp Winlogon Autologon for the profile account.
# Dot-sourced by SetupComplete.ps1; relies on script-scope $logDir and Get-ScSetupProfile*.
#
# Windows OOBE often leaves DefaultUserName=defaultuser0 after SetupComplete. With
# AutoAdminLogon still on, the next logon tries defaultuser0 and can hang on
# FirstLogonAnim ("Just a moment") — FirstLogonCommands never fire. Re-stamp the
# Local+autoLogon profile account here (same values FirstLogon persists later).

function Invoke-ScAutoLogonStamp {
    $result = [ordered]@{
        generatedAt = Get-Date -Format o
        skipped = $false
        reason = ''
        before = $null
        after = $null
        stamped = $false
    }

    $accountMode = [string](Get-ScSetupProfileValue -Section 'account' -Name 'accountMode' -Default 'Local')
    $autoLogon = [bool](Get-ScSetupProfileValue -Section 'account' -Name 'autoLogon' -Default $false)
    $userName = [string](Get-ScSetupProfileValue -Section 'account' -Name 'userName' -Default '')
    $password = [string](Get-ScSetupProfileValue -Section 'account' -Name 'password' -Default '')

    if ($accountMode -ne 'Local' -or -not $autoLogon) {
        $result.skipped = $true
        $result.reason = 'account.autoLogon not enabled for Local account'
        $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $logDir 'SetupComplete_AutoLogon.json') -Encoding UTF8
        Write-ScLog 'Skipping Winlogon autologon stamp (Local+autoLogon not selected).'
        return
    }
    if ([string]::IsNullOrWhiteSpace($userName) -or [string]::IsNullOrEmpty($password)) {
        $result.skipped = $true
        $result.reason = 'missing account.userName or account.password'
        $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $logDir 'SetupComplete_AutoLogon.json') -Encoding UTF8
        Write-ScLog 'Skipping Winlogon autologon stamp (missing userName/password in setup profile).'
        return
    }

    $winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    try {
        $wl = Get-ItemProperty -LiteralPath $winlogon -ErrorAction Stop
        $result.before = [ordered]@{
            DefaultUserName = [string]$wl.DefaultUserName
            DefaultDomainName = [string]$wl.DefaultDomainName
            AutoAdminLogon = [string]$wl.AutoAdminLogon
            AutoLogonCount = $(if ($null -ne $wl.PSObject.Properties['AutoLogonCount']) { [string]$wl.AutoLogonCount } else { '' })
            hasDefaultPassword = (-not [string]::IsNullOrEmpty([string]$wl.DefaultPassword))
        }
    }
    catch {
        $result.before = [ordered]@{ error = [string]$_.Exception.Message }
    }

    try {
        if (-not (Test-Path -LiteralPath $winlogon)) {
            $null = New-Item -Path $winlogon -Force -ErrorAction Stop
        }

        Set-ItemProperty -LiteralPath $winlogon -Name 'AutoAdminLogon' -Value '1' -Type String -Force
        Set-ItemProperty -LiteralPath $winlogon -Name 'DefaultUserName' -Value $userName -Type String -Force
        Set-ItemProperty -LiteralPath $winlogon -Name 'DefaultDomainName' -Value $env:COMPUTERNAME -Type String -Force
        Set-ItemProperty -LiteralPath $winlogon -Name 'DefaultPassword' -Value $password -Type String -Force
        Remove-ItemProperty -LiteralPath $winlogon -Name 'AutoLogonCount' -ErrorAction SilentlyContinue

        $result.stamped = $true
        $wlAfter = Get-ItemProperty -LiteralPath $winlogon -ErrorAction Stop
        $result.after = [ordered]@{
            DefaultUserName = [string]$wlAfter.DefaultUserName
            DefaultDomainName = [string]$wlAfter.DefaultDomainName
            AutoAdminLogon = [string]$wlAfter.AutoAdminLogon
            AutoLogonCount = $(if ($null -ne $wlAfter.PSObject.Properties['AutoLogonCount']) { [string]$wlAfter.AutoLogonCount } else { '' })
            hasDefaultPassword = (-not [string]::IsNullOrEmpty([string]$wlAfter.DefaultPassword))
        }

        $beforeUser = [string]$result.before.DefaultUserName
        if ($beforeUser -ieq 'defaultuser0' -or ($beforeUser -and $beforeUser -ne $userName)) {
            Write-ScLog "Winlogon autologon restamped: DefaultUserName '$beforeUser' -> '$userName' (cleared AutoLogonCount)."
        }
        else {
            Write-ScLog "Winlogon autologon stamped for '$userName' (AutoAdminLogon=1, AutoLogonCount cleared)."
        }
    }
    catch {
        $result.failed = [string]$_.Exception.Message
        "Autologon stamp failed: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
        Write-ScLog "Winlogon autologon stamp failed: $($_.Exception.Message)"
    }

    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $logDir 'SetupComplete_AutoLogon.json') -Encoding UTF8
}
