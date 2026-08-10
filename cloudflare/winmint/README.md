# WinMint Bootstrap Worker

Short launcher for users (no git clone, no source zip):

```powershell
irm https://winmint.yanai.sh | iex
irm https://winmint.yanai.sh/cli | iex
```

The Worker serves [`winmint.ps1`](../../winmint.ps1) as `text/plain` from GitHub (`BOOTSTRAP_URL`). `/cli` returns a tiny wrapper that fetches `/` and invokes `-Headless`.

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
```
