# Ephemeral triple score — 2026-08-11

**Rubric:** [2026-08-11-ephemeral-score-rubric.md](2026-08-11-ephemeral-score-rubric.md)

## Ship status

| Work | Status |
|------|--------|
| `/primary-gate` + `/validate` in tree + on `origin/main` | **done** |
| Wizard Release = Gate B; `packageStrict` evidence/assert | **done** |
| `just check` green | **done** |
| Live Worker deploy (`winmint.yanai.sh`) | **done** (`/primary-gate` + `/validate` 200) |

Cold check: `/`, `/primary-gate`, `/validate` → 200.

## Maintainer deploy (if routes regress)

```powershell
cd cloudflare\winmint
# WSL aarch64 works for wrangler@4 deploy on this host:
wsl -e bash -lc 'cd /mnt/c/Users/yanai/Projects/winmint/cloudflare/winmint && npx --yes wrangler@4 deploy --config wrangler.jsonc'
```

After deploy, verify:

```powershell
irm 'https://winmint.yanai.sh/validate' | Select-Object -First 8
irm 'https://winmint.yanai.sh/primary-gate' | Select-Object -First 8
```

## Scores

| Lens | Local / `main` | Live |
|------|----------------|------|
| Prospect | **9** | **9** |
| Full-flow | **9** | **9** |
| Architect | **9** | **9** |

Durable-default advice still applies?: **no**
