# Ephemeral triple score — 2026-08-11

**Rubric:** [2026-08-11-ephemeral-score-rubric.md](2026-08-11-ephemeral-score-rubric.md)

## Ship status

| Work | Status |
|------|--------|
| `/primary-gate` + `/validate` in tree + on `origin/main` | **done** |
| Wizard Release = Gate B; `packageStrict` evidence/assert | **done** |
| `just check` green | **done** |
| Live Worker deploy (`winmint.yanai.sh`) | **done** (`/primary-gate` + `/validate` 200) |

Cold check (2026-08-11, post-OAuth deploy): `/`, `/validate`, `/primary-gate`, `/cli` → **200**.

Pre-ship live was Prospect **8** / Full-flow **7** (routes 404); local stayed ahead until Worker caught up. That lag is closed.

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

### Prospect — 9 / 9 (local = live)

**Earned:** Cold `irm` lobby; release zip refuses missing `.sha256`; README Quickstart is no-clone + ADR-001 / Alpha / ephemeral; live `/validate` is a no-ISO first win; Worker routes match what docs promise.

**Not 10:** Still lab-shaped (pwsh 7.6+ / Just bootstrap via winget; `/primary-gate` needs query params or throws usage). Peer-recommend the **try** path, not a frictionless consumer lobby.

### Full-flow — 9 / 9 (local = live)

**Earned:** Live one-shot `/primary-gate` (or session + `just primary-gate`) reaches Gate B with workdir under `%LOCALAPPDATA%\WinMint\work\sl7-primary` (survives TEMP toolkit delete); soft `metal` ≠ wipe story; Rufus DD + digest SHA + wait honesty documented. No durable toolkit default required.

**Not 10:** Ephemeral Wizard wipe still leans on second-terminal / one-shot handoff — not a near in-Wizard one-command chain.

### Architect — 9 / 9 (local = live)

**Earned:** Mandatory release checksum; Gate B = Release + package-strict on metal / Wizard Release / `/primary-gate` / `primary-gate`; evidence can stamp `packageStrict` and Release assert fail-closes without it; Status does not sell Gate B as Primary wipe proven.

**Not 10 / accepted soft edge:** Cli `Release` without `--package-strict` remains warn-only for maintainer builds (rubric: do not demerit alone). Host seams are strong; not “nothing left to distrust.”

## Open from this ship?

Nothing blocking. Optional polish toward **10** (not required for ship close):

- Prospect: fewer try-path lab caveats
- Full-flow: tighter in-Wizard Gate B chain (fewer handoffs)

Do **not** chase durable LocalAppData toolkit default for scores.
