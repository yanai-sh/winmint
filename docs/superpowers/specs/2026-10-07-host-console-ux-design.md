# Host console UX (Apply / Smoke / Watch)

**Date:** 2026-10-07 · **Status:** accepted · **Build contract only** (ADR-014 — not living law)

Brainstorm artifact. Behaviour after land lives in `tools/host/`, `servicing/`, `tools/vm/`, and contract tests.

## Problem

Elevated Apply and Watch during Smoke show the same stage log as a scrolling dump: `AddQualityUpdates running 37s/58s/…` as new host lines, sparse quality chatter, DISM’s own ASCII bars, and bare `pwsh.exe` consoles. Humans cannot tell what is happening; the trail is still useful for agents.

## Goals

1. Interactive host console is easy to follow while still communicating truth (real stage, real opcode, real failures).
2. Durable plain trail (stage `.log` + `apply-status.txt`) remains scrape-stable for agents and a **future Wizard ISO-build tail** (not Smoke Watch).
3. New host windows spawn via Windows Terminal when `wt.exe` is available.

## Non-goals

- Wizard Avalonia UI in this pass (file channel is the Wizard constraint only)
- Spectre / OpenTUI / dashboard product (CONTEXT: avoid monitor UI as product)
- Structured progress event bus
- Changing `apply-status` keys (`updated` / `stage` / `log`)
- Re-skinning or suppressing DISM’s own progress stdout
- Auto-spawn Watch from `just check`
- Guest / Supervisor logging
- Reopening UAC parent poll / failure enrich / maintainer-check tokens (already landed)

## Channel split

| Channel | Where | Job |
|--------|--------|-----|
| **Trail** | Stage `.log`, pointers in `apply-status.txt` | Plain lines: start, sparse proof, `{Opcode} running {N}s`, ok/fail. Agents + future Wizard. |
| **Console** | Interactive elevated Admin / Smoke / Host Apply | `$PSStyle` phase lines; in-place `Write-Progress` (Minimal). No new host line per heartbeat. |
| **Watch** | `Watch-Host` window | Snapshot of status files + **filtered** trail tail (drop pure heartbeats). |

```text
kernels → Invoke-WinMintLoggedKernel → trail (.log)
                                   ↘ console (Write-Progress / phase)
trail + apply-status → Watch-Host (filtered)
trail + apply-status → future Wizard (ISO build only)
```

**Coupling rule:** kernel stdout/stderr still tee into trail and console. Kernel **silence heartbeats** are trail-primary; console shows the same liveness via `Write-Progress -Status` only.

## Native PowerShell 7.6+ / Windows Terminal

Inbox only — no new packages.

| Feature | Use |
|--------|-----|
| `$PSStyle.Progress.View = 'Minimal'` | Single-line progress (already initialized) |
| `Write-Progress -Activity/-Status/-PercentComplete` | In-place console liveness and % |
| `$PSStyle.Progress.UseOSCIndicator = $true` | When interactive and `$Host.UI.SupportsVirtualTerminal` — WT tab progress |
| `$PSStyle` Bold / Foreground | Phase lane coloring (existing `Write-WinMintHostPhase`) |
| Default `OutputRendering = Host` | ANSI stripped from redirected output; trail writes stay plain strings |
| `wt.exe new-tab --title … -d … -- pwsh …` | Spawn Watch (and similar) when `wt` resolves; else `Start-Process pwsh` |

Respect `NO_COLOR` / `TERM=dumb` (engine already disables VT / PlainText) — no OSC or decorative host path when non-interactive or non-VT.

Do **not** use `Write-Information` as the primary operator channel (`$InformationPreference` defaults to SilentlyContinue).

## Helper seam

Extend [`tools/host/Write-WinMintHostProgress.ps1`](../../../tools/host/Write-WinMintHostProgress.ps1):

| API | Role |
|-----|------|
| `Write-WinMintHostPhase` | Keep — stage/opcode start and outcome lines |
| `Write-WinMintHostProgress` | Keep — `Write-Progress` Minimal |
| `Write-WinMintHostHeartbeat` | **New** — write `{Opcode} running {N}s` to trail (`-LogWriter` / line for caller); console = `Write-Progress -Status` only (no `Write-Host`) |
| `Test-WinMintTrailHeartbeatLine` | **New** — `$true` when line matches silence-heartbeat noise (`^\S+ running \d+s$`) |
| `Select-WinMintWatchLogTail` | **New** — take last N non-heartbeat lines from a log tail for Watch |
| `Format-WinMintHostWatch` | Upgrade layout clarity; callers pass already-filtered tail |
| `Initialize-WinMintHostProgress` | Also set `UseOSCIndicator` when interactive + VT |
| `Start-WinMintHostWatchProcess` | **New** — spawn Watch via `wt` or `pwsh`; Watch self-stamps PID marker |

Watch PID: `Watch-Host` writes `$PID` to the marker path at start when `-MarkerPath` is bound (parent may create the window via `wt`, whose PID is not the watcher).

## Message patterns (trail)

| Kind | Pattern | Example |
|------|---------|---------|
| Start | `{what} start …` | `Catalog BITS start KB5066835` |
| Proof | sparse meaningful units | `quality hash 25% 1024/4096 MB` (trail; console may use progress %) |
| Heartbeat | `{Opcode} running {N}s` | every ~20s of kernel silence |
| Done | `{what} ok …` / fail | `AddQualityUpdates ok …` |

No fake percent. DISM’s `[=..%]` bars remain as DISM emits them.

## Surfaces

| Surface | Change |
|--------|--------|
| `Invoke-WinMintLoggedKernel` | Heartbeat via `Write-WinMintHostHeartbeat`; stop `Write-Host` for running ticks |
| Quality / BITS / hash / expand | Keep milestone `Write-Output` / trail announcements; long waits and hash % drive helper progress on console (rate-limit host chatter) |
| `Invoke-ServicingPlan` phases | Keep phase lines; stage-index progress when known |
| Smoke | Host lines stay on helper; wait beats stay honest (no fake %); Watch spawn via helper |
| `Watch-Host` | Filtered tail; clearer format string |
| Host Apply / CLI parent | Clearer sentences where cheap; Orchestrator `still` / `quiet` / stage protocol unchanged |
| Maintainer-check tokens | Unchanged |

## Rejected

- Spectre / OpenTUI / dashboard product
- Approach B (typed progress event bus) before Wizard needs it
- Console-only polish without Watch / `wt`
- Removing heartbeats from the trail file
- Wizard UI work in this pass

## Success

- Elevated Apply: clear start/ok lines; no scrolling `Opcode running Ns` host spam; liveness via `Write-Progress` (+ OSC in WT when interactive)
- Stage logs still contain heartbeats and milestones
- Watch: readable snapshot; heartbeats filtered from displayed tail; spawned via `wt` when available
- Redirected / CI: plain trail, no VT games
- `just check` green; helper still bans Spectre
