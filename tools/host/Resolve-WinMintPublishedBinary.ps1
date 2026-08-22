#requires -Version 7.6
# Mtime freshness aligned with ImageServicing.FindSourceNewerThan. Dot-source; do not run.

function Test-WinMintPublishedBinaryCurrent {
    param(
        [Parameter(Mandatory)] [string] $PublishedExe,
        [string[]] $SourceRoots
    )
    if (-not (Test-Path -LiteralPath $PublishedExe -PathType Leaf)) {
        return $true
    }
    $published = (Get-Item -LiteralPath $PublishedExe).LastWriteTimeUtc
    $now = [datetime]::UtcNow
    foreach ($root in @($SourceRoots)) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root -PathType Container)) {
            continue
        }
        $stale = Get-ChildItem -LiteralPath $root -Filter '*.cs' -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -notmatch '[\\/](obj|bin)[\\/]' -and
                $_.LastWriteTimeUtc -le $now -and
                $_.LastWriteTimeUtc -gt $published
            } |
            Select-Object -First 1
        if ($null -ne $stale) { return $false }
    }
    return $true
}
