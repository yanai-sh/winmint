# WinMint Bootstrap Worker

Short launcher for users (no git clone, no source zip):

```powershell
irm https://winmint.yanai.sh | iex
irm https://winmint.yanai.sh/cli | iex
irm 'https://winmint.yanai.sh/validate?ProfilePath=samples\smoke.profile.json' | iex
irm 'https://winmint.yanai.sh/primary-gate?SourceIso=C:\path\to\source.iso&ProfilePath=samples\sl7.profile.json' | iex
```

The Worker serves [`winmint.ps1`](../../winmint.ps1) as `text/plain` from GitHub (`BOOTSTRAP_URL`).

| Path | Behavior |
|------|----------|
| `/`, `/winmint`, `/winmint.ps1` | Raw bootstrap |
| `/cli`, `/cli.ps1` | Wrapper that fetches `/` and invokes `-Headless` (pass args via scriptblock if needed) |
| `/validate`, `/validate.ps1` | Wrapper that invokes `-Headless -ValidateOnly`; bake `ProfilePath` (default `samples/smoke.profile.json`), optional `Work`, `Repository`, `Version`, `Force`, `CacheRelease` |
| `/primary-gate`, `/primary-gate.ps1` | Wrapper that always invokes `-PrimaryGate`; bake args from query: `SourceIso` (required), `ProfilePath` (default `samples/sl7.profile.json`), optional `Work`, `Repository`, `Version`, `Force`, `CacheRelease` |

Deploy the Worker after changing wrappers — live `winmint.yanai.sh` serves the last deploy. Raw `/` still tracks `BOOTSTRAP_URL` (usually `main` `winmint.ps1`).

## Deploy

```powershell
cd cloudflare\winmint
bunx wrangler@latest deploy --config wrangler.jsonc
```

Or upload the Worker via the Cloudflare dashboard / API (`winmint-bootstrap` script) with `BOOTSTRAP_URL` set to the raw `winmint.ps1` on **main** (bring `main` up to date before relying on `irm | iex`).

`yanai.sh` must be managed by Cloudflare. Do not put JS challenges / Bot Fight Mode in front of `winmint.yanai.sh` — `irm | iex` cannot pass them.

## Verify

```powershell
irm https://winmint.yanai.sh | Select-Object -First 5
irm 'https://winmint.yanai.sh/validate' | Select-Object -First 8
irm 'https://winmint.yanai.sh/primary-gate' | Select-Object -First 8
```
