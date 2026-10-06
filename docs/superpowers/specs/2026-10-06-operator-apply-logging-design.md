# Operator Apply logging (CLI / Host Apply)

**Date:** 2026-10-06 · **Status:** accepted · **Build contract only** (ADR-014 — not living law)

Brainstorm + adversarial review artifact. Behaviour after land lives in Orchestrator / Cli / maintainer-check + tests.

## Goals

For non-elevated `winmint build` / Host Apply (inherits via CLI):

1. Is Apply still moving? — stage transitions + sparse proof the stage log is growing
2. Which opcode / log if it died?
3. Maintainer-check: success vs advisory token honesty

## Non-goals

Unified logger, JSON log lines, TUI / Watch auto-spawn, guest / smoke overhaul, InjectDrivers DISM streaming, compose ISO-hash progress, validate honesty, rewriting `apply-status` on kernel heartbeat, Host Apply script-level poll loop.

## Design

### Failure enrich (both elevation modes)

`failure.json` already carries `opcode`. Parent must surface opcode + work dir + apply-status stage + log path in `servicing.plan.failed`. Crashed path (no failure.json) names work dir and status hint.

### UAC wait / poll

Only when not already elevated (`runas` / `UseShellExecute`). Replace blocking `WaitForExit` with ~1s timeout loop; cancel-via-Kill unchanged.

Emit rules (callback into CLI — Orchestrator must not reference Cli):

- `stage=` change — one line (skip still-spam on `idle`/`done`; surface `failed:*`)
- same stage + stage log **length grew** — rate-limited `still` (~20s, parent Stopwatch)
- same stage + log exists + no growth ~60s — **one** `quiet` warn, then silence until growth / stage change
- log truncated (length decrease) — reset baseline
- cancel — stop emits

Do **not** rewrite `apply-status` from the 20s kernel heartbeat (log already gets `Opcode running Ns`; Watch tails the log). Do **not** use `updated=` wall-clock age for liveness.

Already-elevated: no poll (child owns console); failure enrich still applies.

### Maintainer bolt-on

`Invoke-MaintainerCheck.ps1`: print `quality-check ok` only when exit 0; on advisory print `maintainer-check advisory`.

## Rejected

- Shared “bar framework” / CONTEXT vocabulary for tokens
- Refresh `apply-status.updated=` for liveness (clock-jump + torn Set-Content)
- Parent Stopwatch-only still without log growth
- Full observability / wide-event JSON / OpenTUI
- Auto-spawn Watch-Host from CLI
- Porting Wizard’s 20-line apply tail UI into Orchestrator

## Success

- Non-elevated Apply: stage transitions + sparse still tied to log growth
- Failed Apply: opcode + paths when files exist
- Already-elevated: no poll spam; failures still enriched
- Maintainer exit 2 never prints `quality-check ok`
- `just check` green
