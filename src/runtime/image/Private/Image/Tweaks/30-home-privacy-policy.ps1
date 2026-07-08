#Requires -Version 7.6

# Baseline Home-safe privacy posture. Telemetry stays at AllowTelemetry=1
# (Required) — the Home-correct minimum; it is NOT set to 0 (Enterprise-only,
# ignored on Home). Does not touch location services.

Add-WinMintRegistryTweakModule @{
    id = 'home-privacy-policy'
    description = 'Windows 11 Home privacy baseline'
    scope = 'machine and default user registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Minimize Home-safe telemetry and suggestion surfaces without using Enterprise-only claims or disabling location services.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\DataCollection'; name = 'AllowTelemetry'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\DataCollection'; name = 'DoNotShowFeedbackNotifications'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\InputPersonalization'; name = 'AllowInputPersonalization'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config'; name = 'AutoConnectAllowedOEM'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config'; name = 'WiFISenseAllowed'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy'; name = 'TailoredExperiencesWithDiagnosticDataEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'; name = 'HasAccepted'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Input\TIPC'; name = 'Enabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\InputPersonalization'; name = 'RestrictImplicitInkCollection'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\InputPersonalization'; name = 'RestrictImplicitTextCollection'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore'; name = 'HarvestContacts'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'Start_AccountNotifications'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.BackupReminder'; name = 'Enabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested'; name = 'Enabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\SystemSettings\AccountNotifications'; name = 'EnableAccountNotifications'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Mobility'; name = 'OptedIn'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\CDP'; name = 'DragTrayEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } }
    )
    remove = @()
}

