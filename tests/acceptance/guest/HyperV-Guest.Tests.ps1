#Requires -Version 7.6

BeforeAll {
    if (-not $TestData -or -not $TestData.GuestSignals) {
        throw 'HyperV-Guest.Tests.ps1 requires -TestData @{ GuestSignals = ...; Tier = ...; WslDistros = ... }'
    }
    $script:Signals = $TestData.GuestSignals
    $script:Tier = [string]$TestData.Tier
    $script:WslDistros = @($TestData.WslDistros)
}

Describe 'Hyper-V guest desktop signals' {
    It 'has an account picture bitmap' {
        $script:Signals.AccountPictureBmpExists | Should -Be $true
    }

    It 'records Start pin policy when present' {
        if ($null -eq $script:Signals.StartPins) {
            Set-ItResult -Inconclusive -Because 'ConfigureStartPins not set on this SKU'
        }
        [string]$script:Signals.StartPins | Should -Not -BeNullOrEmpty
    }
}

Describe 'Hyper-V full tier guest signals' {
    It 'includes Ubuntu Terminal profile when Ubuntu WSL is selected' -Skip:( $TestData.Tier -ne 'Full' -or 'Ubuntu' -notin @($TestData.WslDistros) ) {
        $script:Signals.UbuntuProfileExists | Should -Be $true
    }

    It 'includes NixOS Terminal profile when NixOS-WSL is selected' -Skip:( $TestData.Tier -ne 'Full' -or 'NixOS-WSL' -notin @($TestData.WslDistros) ) {
        $script:Signals.NixProfileExists | Should -Be $true
    }
}
