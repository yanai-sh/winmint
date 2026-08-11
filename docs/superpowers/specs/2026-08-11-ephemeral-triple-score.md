# Ephemeral triple score — 2026-08-11

**Rubric:** [2026-08-11-ephemeral-score-rubric.md](2026-08-11-ephemeral-score-rubric.md)

## Ship status

| Work | Status |
|------|--------|
| `/primary-gate` + `/validate` in tree + on `origin/main` | **done** |
| Wizard Release = Gate B; `packageStrict` evidence/assert | **done** |
| `just check` green | **done** |
| Live Worker deploy (`winmint.yanai.sh`) | **blocked** until wrangler/workerd or API deploy (win32 arm64) |

Cold check until deploy: `/` 200, `/primary-gate` / `/validate` may still 404.

## Maintainer deploy (required for live 9)

```powershell
cd cloudflare\winmint
# Use an environment where wrangler/workerd runs (x64 host, WSL, or CI), then:
npx wrangler@4 deploy --config wrangler.jsonc
```

After deploy, verify:

```powershell
irm 'https://winmint.yanai.sh/validate' | Select-Object -First 8
irm 'https://winmint.yanai.sh/primary-gate' | Select-Object -First 8
```

## Scores until Worker deploy

| Lens | Local / `main` | Live |
|------|----------------|------|
| Prospect | **9** | **8** (docs promise routes that 404) |
| Full-flow | **9** | **7** (one-shot broken live) |
| Architect | **9** | **9** |

Durable-default advice still applies?: **no**
