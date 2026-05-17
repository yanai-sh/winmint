#Requires -Version 7.3
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Get-ElementBounds {
    param([System.Windows.Automation.AutomationElement]$Element)
    $rect = $Element.Current.BoundingRectangle
    return @{
        x      = [int][Math]::Round($rect.X)
        y      = [int][Math]::Round($rect.Y)
        width  = [int][Math]::Round($rect.Width)
        height = [int][Math]::Round($rect.Height)
    }
}

function Get-SupportedPatternNames {
    param([System.Windows.Automation.AutomationElement]$Element)
    $patterns = [System.Collections.Generic.List[string]]::new()
    $known = @(
        @{ Name = 'Invoke';    Pattern = [System.Windows.Automation.InvokePattern]::Pattern },
        @{ Name = 'Toggle';    Pattern = [System.Windows.Automation.TogglePattern]::Pattern },
        @{ Name = 'Selection'; Pattern = [System.Windows.Automation.SelectionItemPattern]::Pattern },
        @{ Name = 'Value';     Pattern = [System.Windows.Automation.ValuePattern]::Pattern },
        @{ Name = 'Text';      Pattern = [System.Windows.Automation.TextPattern]::Pattern },
        @{ Name = 'Scroll';    Pattern = [System.Windows.Automation.ScrollPattern]::Pattern }
    )
    foreach ($entry in $known) {
        $box = $null
        if ($Element.TryGetCurrentPattern($entry.Pattern, [ref]$box)) {
            $patterns.Add([string]$entry.Name)
        }
    }
    return $patterns.ToArray()
}
