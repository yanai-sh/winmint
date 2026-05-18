#Requires -Version 7.3

function Import-WinMintFrozenBitmap {
    param([Parameter(Mandatory)][string]$Path)

    $ms = [System.IO.MemoryStream]::new([System.IO.File]::ReadAllBytes($Path))
    try {
        $bmp = [System.Windows.Media.Imaging.BitmapImage]::new()
        $bmp.BeginInit()
        $bmp.StreamSource = $ms
        $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.EndInit()
        $bmp.Freeze()
        return $bmp
    } finally {
        $ms.Close()
    }
}

function Import-WinMintSvgPathGeometry {
    param([Parameter(Mandatory)][string]$Path)

    [xml]$svg = Get-Content -LiteralPath $Path -Raw
    $pathNode = $svg.SelectSingleNode('//*[local-name()="path" and @d]')
    if ($null -eq $pathNode) {
        throw "SVG contains no path data: $Path"
    }

    $geometry = [System.Windows.Media.Geometry]::Parse($pathNode.GetAttribute('d'))
    $geometry.Freeze()
    return $geometry
}

function Get-WinMintAssetPath {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$RelativePath
    )

    return Join-Path $State.RepositoryRoot $RelativePath
}
