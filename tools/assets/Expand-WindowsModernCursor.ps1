Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$zipPath = Join-Path $root 'assets\cursors\Windows-11-Modern-Cursor.zip'
$extractTo = Join-Path $root 'assets\cursors\_extract'
if (Test-Path -LiteralPath $extractTo) { Remove-Item -LiteralPath $extractTo -Recurse -Force }
[System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractTo)
Get-ChildItem -LiteralPath (Join-Path $extractTo 'Windows-11-Modern-Light') -Name
