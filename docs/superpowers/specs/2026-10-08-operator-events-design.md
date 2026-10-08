# Operator events (wide events + Spectre Watch + Wizard Review)

**Date:** 2026-10-08 · **Status:** approved (brainstorm) · **Build contract only** (ADR-014 — not living law)

Brainstorm artifact. Behaviour after land lives in `servicing/`, `tools/host/`, Watch host, `src/WinMint.Wizard/`, `src/WinMint.Cli/`, and contract tests.

Supersedes operator-facing parts of:

- [2026-10-07-host-console-ux-design.md](./2026-10-07-host-console-ux-design.md) — free-form milestone trail as primary story; Spectre ban for Watch; heartbeat lines on trail
- [2026-10-07-operator-build-feedback-design.md](./2026-10-07-operator-build-feedback-design.md) — filtered stage-log tail as Wizard story; “no event bus / no Spectre” for operator surfaces

**Kept from those specs:** DISM transcript sink (`dism-transcript.log`); `apply-status.txt` keys `updated` / `stage` / `log`; real `%` only when measured; no fake `%` from stage index; Wizard Review as product ISO-build surface; Smoke/Check status files remain projection-only (harness must not decide from Watch).

## Problem

Channel split (trail / transcript / status) landed, but the **operator story** is still free-form kernel `Write-Output`: long PackageName lines, mid-word wrap in Watch, heartbeat noise, and Wizard `StatusTail` as a monospace dump. Clip hacks and filters do not fix the model. Maintainers live in Watch during Smoke; builders live in Wizard Review — both need one structured story and deliberate presentation.

## Decisions (brainstorm)

| Topic | Choice |
|-------|--------|
| Story model | **Wide event per opcode** (`opcode.end`) + rare `proof` + run bookends |
| Live during opcode | **Status + UI motion only** — no `{Opcode} running Ns` events |
| On-disk shape | **`apply-events.jsonl` canonical**; human rows **derived at render time** |
| Surfaces | **Wizard Review + Spectre Watch** in one pass (shared events) |
| Spectre / TUI | **Allowed for Watch only**; Wizard stays Avalonia; Servicing stays inbox pwsh |
| `apply-status` keys | Unchanged (`updated` / `stage` / `log`) |
| `log=` target | Path to **`apply-events.jsonl`** |
| `opcode.start` events | **Omitted** — `stage=` is “now” |
| Parallel free-form stage `.log` milestones | **Retired** as operator trail |

## Goals

1. One append-only event stream every consumer can render without scraping prose.
2. Watch is visually clear in Windows Terminal (Spectre Live: fixed chrome + event table; no mid-word wrap dumps).
3. Wizard Review shows the same story as designed rows + mandatory motion (spinner or real proof `%`).
4. DISM noise stays in `dism-transcript.log` only.
5. Failures remain diagnosable: last failed `opcode.end` + `failure.json` + transcript path.

## Non-goals

- Spectre (or any TUI package) in Servicing kernels or Wizard
- OpenTUI / JS TUI rewrite of Watch
- Check-status Spectre / auto-spawn Watch from `just check`
- Guest / Supervisor logging
- Changing opcode plan order or Profile schema
- Fake completion `%` from stage index alone
- Making Watch a product dashboard that harnesses decide from (CONTEXT: Smoke/Check status stay watch-only projections)
- Networked event bus / OTLP / evlog package (pwsh + files; wide-event *ideas* only)

## Channel split

| Channel | Where | Job |
|---------|--------|-----|
| **Events** | `{WorkDirectory}/apply-events.jsonl` | `run.start` / `run.end` / `opcode.end` / `proof` |
| **Status** | `apply-status.txt` | Live stage pointer; `log=` → events file |
| **Tool sink** | `dism-transcript.log` | Raw DISM stdout/stderr with per-invoke banners |
| **Elevated motion** | Admin console | `$PSStyle` phase lines + `Write-Progress` (no trail heartbeats) |
| **Wizard motion** | Review pane | Spinner when busy without fresh proof `%`; determinate from `proof` only |
| **Watch motion** | Spectre Live header | Stage / stall / wall / alive from status age |

```text
plan / kernels
  → DISM wrapper          → dism-transcript.log
  → Write-ApplyEvent      → apply-events.jsonl
  → apply-status          → stage= / log=apply-events.jsonl / updated=
Watch (Spectre)  ← status + JSONL
Wizard Review    ← status + JSONL
Cli parent       ← status (+ last summary optional)
```

## Event model

**Module (illustrative name):** Apply operator events — small **write** interface at Servicing; Watch / Wizard / Cli / contracts only **read and render**.

**File:** append-only JSONL. Never rewrite prior lines.

### Kinds (v1)

| `kind` | When | Role |
|--------|------|------|
| `run.start` | Plan begins | Bookend |
| `opcode.end` | Opcode finishes (ok or fail) | **Wide event** — primary story row |
| `proof` | Measured progress only | e.g. quality hash `%` |
| `run.end` | Plan finishes | Bookend (overall outcome) |

No `opcode.start`. No heartbeat kinds.

### `opcode.end` fields (contract)

| Field | Notes |
|-------|--------|
| `ts` | ISO-8601 UTC |
| `runId` | Same id the run already uses where available |
| `kind` | `opcode.end` |
| `opcode` | Opcode name |
| `index` / `count` | Stage position when known |
| `outcome` | `ok` \| `fail` |
| `durationMs` | Wall duration for that opcode |
| `summary` | Short human string, **≤80 characters**, display-safe |
| `detail` | Optional object (counts, catalog ids — not PackageFullName novels) |
| `error` | Optional `{ message, transcriptHint? }` on fail |

### `proof` fields (contract)

| Field | Notes |
|-------|--------|
| `ts`, `runId`, `kind`, `opcode` | As above |
| `label` | e.g. `quality-hash` |
| `percent` | 0–100 when known |
| `summary` | ≤80 chars |

### Invariants

- Events never contain DISM ASCII bars, full PackageFamily dumps, or `reg.exe` chatter.
- Emitters keep `summary` short; renderers may clip further to console/pane width.
- Residual bar-shaped lines must not be written to JSONL (defense in depth if anything still tees).

### Writer seam

Plan loop emits `run.*` and `opcode.end` (duration, outcome). Kernels emit `proof` only where measured progress already exists. Free-form milestone `Write-Output` is not the operator trail.

**Logged kernel:** stop treating arbitrary success-stream lines as the human story. Heartbeat helper must not append trail/`running Ns` events under this design; elevated liveness is `Write-Progress` + status `updated=` only.

## Watch (Spectre)

**Audience:** maintainer Smoke / Host Apply — chrome, not harness truth.

**Dependency:** Spectre.Console on the **Watch host only**. Packaging default: small .NET console project (e.g. `src/WinMint.Watch` or `tools/host/WinMint.Watch`) spawned instead of / alongside today’s `Watch-Host.ps1` entry. Pure-pwsh Spectre is rejected (awkward hosting); `Watch-Host.ps1` may remain a thin launcher into the console app.

**Layout (monitor pattern):**

1. **Header** — title, verdict/phase, stall/wall, current `stage`, alive indicator from status freshness.
2. **Event table** — `run.*` / `opcode.end` / `proof` rows: time · opcode · outcome · summary (width-clipped). No raw JSON dump.
3. **Footer** — quit hint; on fail, transcript / failure path from last failed event or `failure.json`.

**Behavior:** Spectre Live redraw; follow newest events. Spawn via `wt.exe` when available (existing spawn helper).

## Wizard Review

**Audience:** product ISO build.

- Stage hero from `apply-status` + motion (spinner or proof `%`).
- Event list = same semantic rows as Watch (Avalonia styling, not Spectre).
- Fail: `summary` + path hints to transcript / `failure.json`.
- `ApplyBuildPresentation` (or successor) parses JSONL + status — retire heartbeat/bar filters over free-form stage logs as the primary path.

## Elevated console + Cli

- Phase lines + `Write-Progress` Minimal (+ OSC when interactive VT) as today.
- No scrolling heartbeat host lines; no DISM bars on console.
- Cli poller: stage from status; optional last `opcode.end.summary`.
- `NO_COLOR` / redirected: plain rendering of summaries, no VT games.

## DISM sink

Unchanged intent from 2026-10-07 operator-build-feedback:

- `Invoke-WinMintDism` appends raw stdout/stderr to `dism-transcript.log` with stage banners.
- Exit ≠ 0 → fail stage; `opcode.end` carries short error; transcript keeps full text.

## Smoke / Check

- Smoke may still spawn Watch; Watch reads the same JSONL + status.
- `smoke-status.json` / stall / wall / apply-fail flip **unchanged** — harness must not read Watch UI or Smoke status to decide Apply truth (ImageServicing `apply-status` / `failure.json` remain).
- Check-status Spectre **out of scope**.

## Relationship to prior specs

| Prior choice | This pass |
|--------------|-----------|
| Free-form stage `.log` milestones as trail | **Replaced** by JSONL wide events |
| Trail heartbeats for agents | **Removed** from event stream; liveness = status + UI |
| Spectre banned | **Lifted for Watch only** |
| Structured event bus rejected | **File JSONL accepted** (not a network bus) |
| Wizard filtered log tail | **Wizard event list from JSONL** |
| DISM transcript sink | **Kept** |
| `apply-status` key names | **Kept** |
| Watch as product dashboard | **Still rejected** (maintainer chrome only) |

## Testing

- Contract: JSONL schema / required fields; `summary` length; no bar-shaped payloads in events.
- Contract: `log=` points at events file; status keys unchanged.
- Watch host: renders table without mid-word wrapping long detail (clip); Spectre dependency confined to Watch project.
- Wizard presentation tests: busy + no proof ⇒ indeterminate; proof `%` ⇒ determinate; fail row surfaces summary.
- Servicing: opcode failure writes `opcode.end` with `outcome=fail`; DISM noise absent from JSONL.
- `just check` green (no live Apply mutex).
- Manual smoke: Watch + Wizard show the same opcode story; transcript still has DISM bars.

## Success

- Smoke Watch: scannable Spectre header + event rows; no PackageName wrap spam.
- Wizard Review: same story, polished Avalonia list + motion.
- Agents/forensics: JSONL + `dism-transcript.log` + `failure.json`.
- One write path for the story; two renderers (Spectre, Avalonia).

## Rejected

- Presentation-only clip/filter on free-form trails as the end state
- Typed milestones without wide `opcode.end` (half-measure)
- Status-schema enrichment instead of events (Approach 2)
- Spectre-first Watch with JSONL deferred (Approach 3)
- Spectre in Wizard or Servicing
- Parallel prose trail file alongside JSONL (drift)
- `opcode.start` events duplicating `stage=`
- Heartbeat lines as events under live-A
- Fake `%` from `index/count` alone
