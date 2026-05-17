#Requires -Version 7.3
# Theme palettes + Set-Theme for cinematic WinWS UI (requires Bootstrap/Interop.ps1 for WinWSNative).

$script:DarkPalette = [ordered]@{
    WindowForegroundBrush = '#F6F8FB'
    AccentBrush       = '#0078D4'
    AccentHoverBrush  = '#1A9BE5'
    AccentPressBrush  = '#005FB4'
    ButtonFgBrush     = '#FFFFFF'
    LogoTextBrush     = '#FFFFFF'
    AccentDimBrush    = '#2B0078D4'
    CloseHoverBrush   = '#C42B1C'
    ClosePressedBrush = '#9E1E11'
    CloseFgBrush      = '#FFFFFF'
    SurfaceBrush      = '#00000000'
    CardBrush         = '#2B2B2B'
    FieldBrush        = '#0FFFFFFF'
    FieldBorderBrush  = '#33FFFFFF'
    LineBrush         = '#33FFFFFF'
    LineStrongBrush   = '#45FFFFFF'
    LabelBrush        = '#AFAFAF'
    TextPrimary       = '#FFFFFF'
    TextPrimaryBrush  = '#FFFFFF'
    TextSecondary     = '#C5C5C5'
    TextTertiary      = '#8A8A8A'
    TextMutedBrush    = '#8A8A8A'
    TextDisabled      = '#606060'
    DangerBrush       = '#F1707B'
    DangerSoftBrush   = '#2A171A'
    PanelBrush        = '#2B2B2B'
    WarnBrush         = '#F1707B'
    SuccessBrush      = '#6CCB5F'
    SuccessHoverBrush = '#52B246'
    SuccessPressBrush = '#3D8B33'
    PickerBg          = '#252525'
    PickerHover       = '#383838'
    PickerSelected    = '#1A5A8EC8'
    PickerSelectedFg  = '#FFFFFF'
    SeparatorBrush    = '#333333'
    InfoBg            = '#1A2B3C'
    WarnBg            = '#2A171A'
    AccentBg          = '#0D5A8EC8'
    SwitchTrackBrush  = '#454545'
}

$script:LightPalette = [ordered]@{
    WindowForegroundBrush = '#1A1A1A'
    AccentBrush       = '#0067C0'
    AccentHoverBrush  = '#005BA4'
    AccentPressBrush  = '#004A90'
    ButtonFgBrush     = '#FFFFFF'
    LogoTextBrush     = '#1A1A1A'
    AccentDimBrush    = '#220067C0'
    CloseHoverBrush   = '#C42B1C'
    ClosePressedBrush = '#9E1E11'
    CloseFgBrush      = '#FFFFFF'
    SurfaceBrush      = '#00000000'
    CardBrush         = '#F9F9F9'
    FieldBrush        = '#FFFFFF'
    FieldBorderBrush  = '#33000000'
    LineBrush         = '#33000000'
    LineStrongBrush   = '#45000000'
    LabelBrush        = '#4F4F4F'
    TextPrimary       = '#1A1A1A'
    TextPrimaryBrush  = '#1A1A1A'
    TextSecondary     = '#6B6B6B'
    TextTertiary      = '#9E9E9E'
    TextMutedBrush    = '#9E9E9E'
    TextDisabled      = '#B0B0B0'
    DangerBrush       = '#C42B1C'
    DangerSoftBrush   = '#FDE7E9'
    PanelBrush        = '#F9F9F9'
    WarnBrush         = '#C42B1C'
    SuccessBrush      = '#0F7B0F'
    SuccessHoverBrush = '#128212'
    SuccessPressBrush = '#0D5F0D'
    PickerBg          = '#FFFFFFFF'
    PickerHover       = '#0F000000'
    PickerSelected    = '#123570AC'
    PickerSelectedFg  = '#1C3F6B'
    SeparatorBrush    = '#D0D0D0'
    InfoBg            = '#E4EDF7'
    WarnBg            = '#FDE7E9'
    AccentBg          = '#0A3570AC'
    SwitchTrackBrush  = '#C8C8C8'
}

function Get-SystemAccentColor {
    try {
        $ns   = 'Windows.UI.ViewManagement'
        $uiT  = [type]"$ns.UISettings, $ns, ContentType=WindowsRuntime"
        $ctT  = [type]"$ns.UIColorType, $ns, ContentType=WindowsRuntime"
        $ui   = $uiT::new()
        $toHex = { param($c) '#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B }
        return @{
            Base   = & $toHex $ui.GetColorValue($ctT::Accent)
            Light1 = & $toHex $ui.GetColorValue($ctT::AccentLight1)
            Light2 = & $toHex $ui.GetColorValue($ctT::AccentLight2)
            Dark1  = & $toHex $ui.GetColorValue($ctT::AccentDark1)
            Dark2  = & $toHex $ui.GetColorValue($ctT::AccentDark2)
            Dark3  = & $toHex $ui.GetColorValue($ctT::AccentDark3)
        }
    } catch {
        Write-Verbose "System accent unavailable: $($_.Exception.Message)"
        return $null
    }
}

function Get-SystemTheme {
    try {
        $val = Get-ItemPropertyValue `
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' `
            'AppsUseLightTheme' -ErrorAction Stop
        return $val -eq 0 ? 'Dark' : 'Light'
    } catch {
        return 'Dark'
    }
}

function Set-Theme {
    param([string]$Mode, [System.Windows.Window]$Win, [switch]$Animate)
    $palette = if ($Mode -eq 'Light') { $script:LightPalette } else { $script:DarkPalette }
    $conv    = [System.Windows.Media.ColorConverter]::new()

    foreach ($key in $palette.Keys) {
        $color = [System.Windows.Media.Color]$conv.ConvertFromString($palette[$key])
        $existing = $Win.Resources[$key]
        if ($existing -is [System.Windows.Media.SolidColorBrush] -and -not $existing.IsFrozen) {
            $existing.Color = $color
        } else {
            $Win.Resources[$key] = [System.Windows.Media.SolidColorBrush]::new($color)
        }
    }

    $sys = Get-SystemAccentColor
    if ($null -ne $sys) {
        $accentHex      = if ($Mode -eq 'Dark') { $sys.Base   } else { $sys.Dark1  }
        $accentHoverHex = if ($Mode -eq 'Dark') { $sys.Light1 } else { $sys.Dark2  }
        $accentPressHex = if ($Mode -eq 'Dark') { $sys.Dark1  } else { $sys.Dark3  }
        $accentDimHex   = if ($Mode -eq 'Dark') { '#2B' + $sys.Base.Substring(1) } else { '#22' + $sys.Dark1.Substring(1) }
        $accentBgHex       = if ($Mode -eq 'Dark') { '#0D' + $sys.Base.Substring(1)  } else { '#0A' + $sys.Dark1.Substring(1) }
        $pickerSelectedHex = if ($Mode -eq 'Dark') { '#1A' + $sys.Base.Substring(1)  } else { '#12' + $sys.Dark1.Substring(1) }
        foreach ($kv in @{
            AccentBrush      = $accentHex
            AccentHoverBrush = $accentHoverHex
            AccentPressBrush = $accentPressHex
            AccentDimBrush   = $accentDimHex
            AccentBg         = $accentBgHex
            PickerSelected   = $pickerSelectedHex
        }.GetEnumerator()) {
            $color    = [System.Windows.Media.Color]$conv.ConvertFromString($kv.Value)
            $existing = $Win.Resources[$kv.Key]
            if ($existing -is [System.Windows.Media.SolidColorBrush] -and -not $existing.IsFrozen) {
                $existing.Color = $color
            } else { $Win.Resources[$kv.Key] = [System.Windows.Media.SolidColorBrush]::new($color) }
        }
    }

    $bgHex = if ($Mode -eq 'Light') { '#01EFEFEF' } else { '#01000000' }
    $Win.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]$conv.ConvertFromString($bgHex))

    $script:ThemeMode = $Mode

    try {
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($Win)).Handle
        if ($hwnd -ne [IntPtr]::Zero) {
            [WinWSNative]::EnableMica($hwnd, ($Mode -eq 'Dark'))
        }
    }
    catch {
        Write-Verbose "DWM theme update skipped: $($_.Exception.Message)"
    }
}
