# Ephemeral triple score — 2026-08-11

**Rubric:** [2026-08-11-ephemeral-score-rubric.md](2026-08-11-ephemeral-score-rubric.md)

## Ship status

| Work | Status |
|------|--------|
| `/primary-gate` + `/validate` in tree + on `origin/main` | **done** |
| Wizard Release = Gate B; `packageStrict` evidence/assert | **done** |
| `just check` green | **done** |
| Live Worker deploy (`winmint.yanai.sh`) | **done** (`/primary-gate` + `/validate` 200) |
| Lobby `/validate` default + shrunk host caveats | **done** (README) |
| In-Wizard Gate B Build + progress + flash strip | **done** |

Cold check (2026-08-11, post-OAuth deploy): `/`, `/validate`, `/primary-gate`, `/cli` → **200**.

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
| Prospect | **9→pending 10 audit** | **9→pending 10 audit** |
| Full-flow | **9→pending 10 audit** | **9→pending 10 audit** |
| Architect | **9** | **9** |

Durable-default advice still applies?: **no**

### Prospect — polish landed (re-audit for 10)

**Earned previously:** Cold `irm` lobby; release zip refuses missing `.sha256`; README Quickstart is no-clone + ADR-001 / Alpha / ephemeral; live `/validate` is a no-ISO first win; Worker routes match what docs promise.

**Raised for 10:** Hero `irm …/validate` needs no query; host prerequisites moved under `<details>`; first-win copy states Alpha / ephemeral / no wipe.

### Full-flow — polish landed (re-audit for 10)

**Earned previously:** Live one-shot `/primary-gate`; Gate B workdir survives TEMP; soft `metal` ≠ wipe; Rufus DD + digest SHA + wait honesty documented.

**Raised for 10:** Wizard Release → Build auto-saves profile to workdir and runs Apply in-app; indeterminate progress + multi-hour wait honesty while busy; FLASH strip (Rufus DD + `outputIso.sha256`) after success; CLI recipe demoted to expander; Source copy states Gate B ≠ Primary install.

### Architect — 9 / 9

**Earned:** Mandatory release checksum; Gate B fail-closed; Status / Wizard copy audited for Gate B ≠ Primary proven.

**Accepted soft edge:** Cli `Release` without `--package-strict` remains warn-only (rubric: do not demerit alone).

## Open from this ship?

Independent re-audit for Prospect/Full-flow **10**. Do **not** chase durable LocalAppData toolkit default for scores. Do not fail-close Cli soft Release for scores.
