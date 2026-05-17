# WinMint Bootstrap Worker

This Worker backs the short launcher:

```powershell
irm https://winmint.yanai.sh | iex
```

It serves `winmint.ps1` as `text/plain` from the canonical GitHub source.
The Worker is only an alias; the PowerShell bootstrapper remains the source of
truth.

## Deploy

`yanai.sh` must be managed by Cloudflare. The Worker uses `winmint.yanai.sh` as a
custom domain, so Cloudflare manages the DNS and certificate for that subdomain.
The future `yanai.sh` site can own the apex domain independently. The Worker
serves the bootstrap at `/`; `/winmint` and `/winmint.ps1` are aliases.

Do not challenge this hostname. `irm | iex` cannot pass JavaScript, managed
challenge, Bot Fight Mode, Access, or browser integrity gates. If the zone has
strict defaults, add a narrowly scoped Cloudflare configuration/WAF skip rule for
`http.host eq "winmint.yanai.sh"`:

- Security Level: Essentially Off
- Browser Integrity Check: Off
- Skip managed challenges, Bot Fight Mode, and WAF managed rules for this host

```powershell
cd cloudflare\winmint
bunx wrangler@latest deploy --config wrangler.jsonc
```

Verify:

```powershell
irm https://winmint.yanai.sh -OutFile .\winmint.ps1
Get-Content .\winmint.ps1 -TotalCount 20
irm https://winmint.yanai.sh | iex
```

## Local Dev

```powershell
cd cloudflare\winmint
bunx wrangler@latest dev --config wrangler.jsonc
```

The deployed Worker uses `BOOTSTRAP_URL` from `wrangler.jsonc`. Change that value
only if the canonical bootstrap location changes.
