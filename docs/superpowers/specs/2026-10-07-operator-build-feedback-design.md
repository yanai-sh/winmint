# Operator build feedback (Wizard pane + elevated/CLI trail)

**Date:** 2026-10-07 · **Status:** accepted · **Build contract only** (ADR-014 — not living law)

Brainstorm artifact. Behaviour after land lives in `servicing/`, `tools/host/`, `src/WinMint.Wizard/`, `src/WinMint.Cli/`, and contract tests.

Extends [2026-10-07-host-console-ux-design.md](./2026-10-07-host-console-ux-design.md): that pass owned Watch / `$PSStyle` / heartbeat console split and **deferred** Wizard chrome + DISM stdout suppression. This pass lifts those deferrals for **ISO Apply** (Wizard Review + elevated Servicing + Cli parent). Smoke Watch remains out of scope as a dashboard product (CONTEXT).

## Problem

When a user builds a WinMint ISO, Apply feedback is dominated by DISM ASCII `%` bars and tool chatter (`The operation completed successfully.`, dense `reg` ok lines). The Wizard Review pane already tails the stage log into `StatusTail` and shows an indeterminate `ProgressBar` while busy — but the tail is the same noisy file. Elevated/CLI mirrors that noise. Users cannot tell which stage is running or that work is still alive.

## Decisions locked in brainstorm

| Topic | Choice |
|-------|--------|
| Audience | **Both** Wizard and elevated/CLI (shared human trail) |
| Progress honesty | **Real % when known** (BITS/hash/stage cues); **no fake %** |
| Indeterminate | **Mandatory motion** — Wizard spinner (or animated `…`); elevated `Write-Progress` / cycling status |
| Trail content | **Milestones only**; raw DISM/`reg` stdout in a **side sink** |
| Architecture | **Tee at Servicing boundary** (DISM wrapper + logged-kernel), not a typed event bus |

## Goals

1. Wizard Review build pane always shows readable stage feedback and never looks frozen (spinner/`…` when indeterminate; real `%` when known).
2. Elevated Apply and Cli progress consumers read the same human trail — no DISM bars on operator surfaces.
3. Full DISM (and similar tool) transcripts remain on disk for failure forensics and agents who open the sink.
4. `apply-status.txt` keys stay `updated` / `stage` / `log` (pointer at human trail).

## Non-goals

- Spectre / OpenTUI / Gallery TUI packages (CONTEXT + existing helper ban)
- Structured progress event bus / JSONL operator protocol (revisit only if Wizard outgrows file tail)
- Smoke Watch as product dashboard; Check-status chrome
- Guest / Supervisor logging
- Changing opcode plan order or Profile schema
- Fake completion % from stage index alone (stage `i/n` may appear as **text**, not as a filled “done” bar)
- Auto-spawn Watch from `just check`
- Perfect silence from every inbox tool in v1 (`reg.exe` spam may be a follow-up if not cheap)

## Channel split

| Channel | Where | Job |
|---------|--------|-----|
| **Human trail** | Stage `.log` (path in `apply-status` `log=`) | Milestones: start, sparse proof, `{Opcode} running Ns`, ok/fail |
| **Tool sink** | Workdir `dism-transcript.log` (stage banners) | Raw DISM stdout/stderr; optional later sinks for other tools |
| **Status** | `apply-status.txt` | Unchanged keys; `stage=` opcode/phase; `log=` human trail |
| **Wizard motion** | Avalonia Review | Indeterminate spinner + optional determinate bar; stage line + filtered/milestone tail |
| **Elevated motion** | Interactive Admin console | `$PSStyle` phase lines + `Write-Progress` (existing helper) |

```text
kernels
  → DISM wrapper → dism-transcript.log (raw)
  → milestones   → stage .log (human trail)
Invoke-WinMintLoggedKernel tees kernel success-stream → trail
                       ↘ console Write-Progress / phase (no heartbeat host spam)
apply-status → Wizard poll / Cli / Orchestrator
Wizard Review ← stage line + trail tail + UI motion
```

## Servicing boundary

### DISM wrapper

Introduce one Servicing helper (name illustrative: `Invoke-WinMintDism`) used by Mount / Unmount / Add-Package / Export / driver inject / WIM-MSU expand / Get-* that currently stream progress:

- Invoke `dism.exe` with stdout/stderr appended to workdir **`dism-transcript.log`**, with a banner line per invocation (`=== stage=… argv=… ===`).
- Do **not** write DISM ASCII progress bars into the human trail or `Write-Host` them.
- Exit code ≠ 0 → throw / fail stage as today; trail gets a short fail line; transcript keeps full text; `failure.json` message may reference the transcript path when useful.
- Exit 0 → no mandatory extra trail line if the kernel already emits `… ok`; optional one-liner only when the kernel would otherwise be silent for a long op.

Prefer **one transcript file** with banners over many `*.dism.log` siblings (less sprawl under `.scratch` / workdirs).

### Logged kernel

`Invoke-WinMintLoggedKernel` keeps writing kernel success-stream lines to the human trail and driving heartbeats via `Write-WinMintHostHeartbeat` (trail + `Write-Progress`, no scrolling host heartbeat).

Defense in depth: if a line matches DISM bar shape (`^\s*\[.*\d+\.\d+%\s*\]`), do not tee it to the console; optionally omit from trail (should already be absent if wrappers are used).

### `reg.exe` and other chatter

v1 focus is DISM. If `The operation completed successfully.` / per-value `policy ok` noise remains painful after DISM is gone, rate-limit or sink in a follow-up — not a blocker for this design.

## Trail message patterns

Unchanged grain from host-console UX (human trail):

| Kind | Pattern | Example |
|------|---------|---------|
| Start | `{what} start …` | `Catalog BITS start KB5129195` |
| Proof | sparse meaningful units | `quality hash 25% 1024/4096 MB` |
| Heartbeat | `{Opcode} running {N}s` | every ~20s of kernel silence |
| Done | `{what} ok …` / fail | `AddQualityUpdates ok …` |
| Phase | Servicing plan | `Apply  11/14  AddQualityUpdates` / `… ok  508.1s` |

No fake percent. BITS/hash proof `%` is real measured progress.

Wizard and Watch already filter pure heartbeats from display tails where helpers exist; Wizard should prefer milestone-looking lines and may drop heartbeat lines from `StatusTail` the same way Watch does.

## Wizard Review pane

Existing Review chrome (`ProgressBar` indeterminate while `Build.IsBusy`, `BuildStatus`, `StatusTail` ScrollViewer) is the pane — deepen it, do not invent a second “monitor” surface.

| Element | Behaviour |
|---------|-----------|
| **Stage line** | Human stage from `apply-status` (`Building: AddQualityUpdates` / `Failed: …`) |
| **Status tail** | Last N lines of **human** trail (not transcript); filter heartbeats; monospace as today |
| **Indeterminate** | Keep/ensure visible spinner (or animated dots in the stage line) whenever busy and no real `%` |
| **Determinate** | v1: parse sparse **proof** lines already on the human trail (e.g. `quality hash 25% …`) when present and fresh; otherwise stay indeterminate. No new `apply-status` keys. A later thin field is out of scope unless the trail parse proves too brittle. |
| **Step cue** | Optional text `Step 11 of 14` when parseable from phase lines — **not** a fake-full progress bar |

Polling continues via `ServicingWorkspace.TryReadProgress` + log tail (share-read). No in-process DISM from Wizard.

Cancel / UAC / flash guidance unchanged.

## Elevated console + Cli

- Phase lines + `Write-Progress` Minimal (+ OSC when interactive VT) as in host-console UX.
- Cli `OnApplyProgress` continues to surface operator lines from the parent poller; those lines should already be human-grade once the trail is clean.
- Redirected / `TERM=dumb` / `NO_COLOR`: plain trail only; no VT games.

## Relationship to prior host-console UX spec

| Prior non-goal / note | This pass |
|----------------------|-----------|
| Wizard Avalonia UI deferred | **In scope** (Review pane motion + clean tail) |
| Re-skinning / suppressing DISM stdout deferred | **In scope** (sink + wrappers) |
| Structured event bus rejected | Still rejected |
| Spectre / dashboard rejected | Still rejected |
| `apply-status` keys frozen | Still frozen |
| Trail heartbeats kept for agents | Still kept (display may filter) |

## Testing

- Contract: DISM wrapper / logged-kernel must not place bar-shaped lines on the human trail (fixture or probe).
- Contract: helper still bans Spectre; `Write-WinMintHostProgress` / heartbeat behaviour remains.
- Wizard unit/presentation: busy + empty `%` ⇒ indeterminate visible; tail excludes bar lines and optionally heartbeats.
- `just check` green.

## Success

- Building an ISO in the Wizard: readable stage + tail; continuous motion (spinner/`…` or real `%`); no DISM bars in the pane.
- Elevated Apply / Cli: same human trail; DISM bars only in `dism-transcript.log`.
- Failures still diagnosable from transcript + `failure.json` + stage log.
- No Spectre; no fake completion %; `apply-status` keys unchanged.

## Rejected

- Display-only filtering while leaving bars in the shared trail (CLI/agents stay ugly)
- Spectre / OpenTUI for host or Wizard
- Typed progress bus before the file channel is proven insufficient
- Using stage index alone as a determinate “% complete” bar
