#requires -Version 7.6
<#
.SYNOPSIS
  Flash the WinPE apply splash for 3 seconds. Press ESC to close it. Not part of just check.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $repo 'src\WinMint.WinPeApply\WinMint.WinPeApply.csproj'
dotnet build $project -c Debug --nologo -v q
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$built = Join-Path $repo 'src\WinMint.WinPeApply\bin\Debug\net11.0-windows'
$stage = Join-Path ([IO.Path]::GetTempPath()) 'winmint-splash-flash'
if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
Copy-Item -LiteralPath $built -Destination $stage -Recurse
Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\cmd.exe') -Destination (Join-Path $stage 'cmd.exe') -Force
@(
    '@echo off'
    'powershell.exe -NoProfile -Command "Start-Sleep -Seconds 3"'
    'exit /b 0'
) | Set-Content -LiteralPath (Join-Path $stage 'LaunchApply.cmd') -Encoding ascii

Write-Host 'Apply splash for 3 seconds. Press ESC to close it.'
$previous = $env:WINMINT_SPLASH_ESCAPE
$env:WINMINT_SPLASH_ESCAPE = '1'
try {
    $proc = Start-Process -FilePath (Join-Path $stage 'WinMintApply.exe') -WorkingDirectory $stage -Wait -PassThru
    exit $proc.ExitCode
}
finally {
    if ($null -eq $previous) { Remove-Item Env:WINMINT_SPLASH_ESCAPE }
    else { $env:WINMINT_SPLASH_ESCAPE = $previous }
}
