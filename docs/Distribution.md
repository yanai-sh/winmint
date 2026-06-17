# Distribution

WinMint is distributed as a small bootstrap script plus a versioned release bundle.

The bootstrap script is intentionally small. It queries the GitHub release,
downloads the `WinMint-<version>.zip` asset and matching `.sha256` into a unique
temporary session directory, requires and verifies the checksum, extracts the
bundle into that same session, then launches the packaged GPUI executable. The
temporary session is removed after the launched process exits. Backend
entrypoints run under PowerShell 7.6.2+; the bootstrapper uses Windows
PowerShell 5.1 only long enough to acquire or locate that runtime and hand off to
the packaged product.

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
.\winmint.ps1 -InstallRoot C:\WinMint\cache
.\winmint.ps1 -CacheRelease
```

By default, `irm https://winmint.yanai.sh | iex` is ephemeral. It does not
create `%LOCALAPPDATA%\WinMint\versions` or keep a release cache after the
launched process exits. `-InstallRoot` and `-CacheRelease` are explicit
developer/debug escape hatches for preserving an extracted release.

Bootstrap failures are grouped by operation and failure kind so users can tell
whether the problem is network access, release integrity, package shape,
PowerShell runtime acquisition, elevation, relaunch, usage, or an unexpected
failure. The launcher prints the active operation, the reason, recovery guidance,
and whether retrying is safe. Integrity failures are intentionally marked unsafe
to retry until the release asset is corrected; network, runtime, elevation, and
most relaunch failures can be retried after fixing the local condition.

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
smoke-tests the packaged launch path from an isolated install root, and uploads
both assets with clobber semantics for a rerun.

Run the same release smoke test locally after creating a bundle:

```powershell
.\tools\release\Test-WinMintReleaseLaunch.ps1 -BundlePath .\dist\WinMint-v0.1.0.zip -Version v0.1.0
```

The smoke test verifies the zip hash, checks required and forbidden packaged
paths, runs a packaged CLI help command from the extracted tree, and exercises
`winmint.ps1 -NoLaunch` against a local mock release endpoint. The bootstrap
smoke asserts that the default launch path uses temporary execution and leaves no
durable `%LOCALAPPDATA%\WinMint\versions` cache. It also forces a bad-checksum
release and asserts that the bootstrapper reports an integrity failure, recovery
guidance, retry safety, and temp cleanup. It does not start the GUI by default;
add `-LaunchGui` for a manual packaged-GUI launch check.

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

Use release-mode validation only after the packaged GUI binary exists:

```powershell
.\tools\validation\Validate.ps1 -RunReleaseSmoke
```
