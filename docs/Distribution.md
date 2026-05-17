# Distribution

WinMint is distributed as a small bootstrap script plus a versioned release bundle.

The bootstrap script is intentionally small. It queries the GitHub release, downloads
the `WinMint-<version>.zip` asset, verifies the `.sha256` asset when present,
extracts the bundle into `%LOCALAPPDATA%\WinMint\versions\<version>`, then launches
`WinMint-UI.ps1` with PowerShell 7.3+.

## User Launch

Inspect-first path:

```powershell
irm https://winmint.yanai.sh -OutFile .\winmint.ps1
notepad .\winmint.ps1
.\winmint.ps1
```

Short path:

```powershell
irm https://winmint.yanai.sh | iex
```

Passing parameters through a pipeline is awkward. Use a scriptblock when arguments
are needed:

```powershell
& ([scriptblock]::Create((irm https://winmint.yanai.sh))) -Version v0.1.0
```

Useful launcher switches:

```powershell
.\winmint.ps1 -Version v0.1.0
.\winmint.ps1 -DryRun
.\winmint.ps1 -ExportHostDrivers
.\winmint.ps1 -Headless -ProfilePath C:\WinMint\profiles\surface.json -Yes
.\winmint.ps1 -Gui
.\winmint.ps1 -NoLaunch
.\winmint.ps1 -Force
```

`irm https://winmint.yanai.sh | iex` starts the current PowerShell/WPF UI. Use
`-Headless` for the console build path. Use `-Gui` only for the WIP GPUI lab; the
launcher fails with a clear message when a release does not package that lab yet.

## Release Build

Create the release assets from the repo root:

```powershell
.\scripts\release\New-WinMintReleaseBundle.ps1 -Version v0.1.0
```

The bundle shape is defined in `config\release-manifest.json`. Keep developer-only
service source, local fixtures, and generated payloads out of the
release by adding them to the manifest `exclude` list instead of relying on
ad hoc cleanup in the packaging script.

Upload both files from `dist\` to the matching GitHub release:

```text
WinMint-v0.1.0.zip
WinMint-v0.1.0.zip.sha256
```

The bootstrapper prefers an exact asset named `WinMint-<tag>.zip`, then falls
back to the first WinMint-looking `.zip` asset.

## Cloudflare Alias

The short `winmint.yanai.sh` command is backed by the Cloudflare Worker in
`cloudflare\winmint`. Deploy it after the repo is pushed:

```powershell
cd cloudflare\winmint
bunx wrangler@latest deploy --config wrangler.jsonc
```

The Worker uses `winmint.yanai.sh` as a custom domain and serves the canonical
`winmint.ps1` source as `text/plain`. The future portfolio/blog site can
own the apex `yanai.sh` domain independently. The root path serves the
bootstrap; `/winmint` and `/winmint.ps1` are aliases.

The hostname must not be protected by a JavaScript challenge, managed challenge,
Cloudflare Access, Bot Fight Mode, browser integrity check, or WAF rule that can
challenge command-line clients. Scope any bypass only to `winmint.yanai.sh`.

Raw GitHub fallback:

```powershell
irm https://raw.githubusercontent.com/yanai-sh/winmint/main/winmint.ps1 | iex
```

## Local Development

For development, run the script directly from the working tree:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-UI.ps1
```

Run validation before building a release:

```powershell
.\scripts\Validation\Validate.ps1
```
