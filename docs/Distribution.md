# Distribution

WinMint is distributed as a small bootstrap script plus a versioned release bundle.

The bootstrap script is intentionally small. It queries the GitHub release, downloads
the `WinMint-<version>.zip` asset, verifies the `.sha256` asset when present,
extracts the bundle into `%LOCALAPPDATA%\WinMint\versions\<version>`, then launches
`WinMint-GUI.ps1` with PowerShell 7.3+.

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
irm https://winmint.yanai.sh/cli | iex
```

Passing parameters through a pipeline is awkward. Use a scriptblock when arguments
are needed:

```powershell
& ([scriptblock]::Create((irm https://winmint.yanai.sh))) -Version v0.1.0
```

Useful launcher switches:

```powershell
.\winmint.ps1 -Version v0.1.0
.\winmint.ps1 -Gui
.\winmint.ps1 -NoLaunch
.\winmint.ps1 -Force
```

`irm https://winmint.yanai.sh | iex` and `-Gui` start the packaged GPUI entry
point. Use the release bundle's `WinMint-CLI.ps1` for profile-backed console
builds:

```powershell
pwsh -NoProfile -File .\WinMint-CLI.ps1 new C:\WinMint\profiles\surface.json -TargetDevice ThisPC -DriverSource Host
pwsh -NoProfile -File .\WinMint-CLI.ps1 build C:\WinMint\profiles\surface.json -DryRun
```

## Release Build

CI is split by intent. `.github/workflows/ci.yml` validates normal pushes and pull
requests. `.github/workflows/release.yml` publishes only when a `v*` tag is pushed
or when the release workflow is run manually with a version input.

Create the release assets from the repo root:

```powershell
.\tools\release\New-WinMintReleaseBundle.ps1 -Version v0.1.0
```

The bundle shape is defined in `config\release-manifest.json`. The release tool
builds and packages `apps\gui\bin\WinMint-GUI.exe`; release users do not
need Rust, Cargo, MSVC, or `tools\gui`. Keep developer-only service source,
local fixtures, and generated payloads out of the release by adding them to the
manifest `exclude` list instead of relying on ad hoc cleanup in the packaging script.
The bootstrapper requires the matching `.sha256` asset for the selected zip and
refuses to install a release without it.

Upload both files from `dist\` to the matching GitHub release:

```text
WinMint-v0.1.0.zip
WinMint-v0.1.0.zip.sha256
```

The bootstrapper prefers an exact asset named `WinMint-<tag>.zip`, then falls
back to the first WinMint-looking `.zip` asset.

Manual release path:

```powershell
git tag v0.1.0
git push origin v0.1.0
```

The release workflow reruns validation, builds `dist\WinMint-<tag>.zip` and
`dist\WinMint-<tag>.zip.sha256`, creates the matching GitHub release when needed,
and uploads both assets with clobber semantics for a rerun.

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
bootstrap; `/winmint` and `/winmint.ps1` are aliases. `/cli` and `/cli.ps1` serve
a small wrapper that invokes the canonical bootstrap with `-Headless`.

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
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-GUI.ps1
```

Run validation before building a release:

```powershell
.\tools\validation\Validate.ps1
```
