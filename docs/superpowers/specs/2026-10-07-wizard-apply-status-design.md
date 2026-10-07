# Wizard Apply status deepening (Review pane)

**Date:** 2026-10-07 · **Status:** accepted · **Build contract only** (ADR-014 — not living law)

Agreed direction: deepen **Wizard Review** only. No dedicated Avalonia log/monitor window. No Spectre. Smoke may keep terminal Watch as a maintainer stopgap.

Extends [2026-10-07-operator-build-feedback-design.md](./2026-10-07-operator-build-feedback-design.md) (trail + DISM sink already landed).

## Problem

Review already has ProgressBar, StepCue, and StatusTail, but during long quiet stages (e.g. DISM Mount) the pane feels static: heartbeats are filtered from the tail, elapsed is not first-class, and failure does not point at `dism-transcript.log`. Polling also skips UI updates when only the heartbeat advances (presentation key ignores elapsed).

## Goals

1. While busy, Review always shows **motion** (indeterminate bar or real `%`) plus **elapsed** for the current stage.
2. Sticky **stage header** (opcode / failed) + optional **Step i/n** text (not fake `%`).
3. Short **activity list** of milestones (no heartbeats, no DISM bars).
4. On failure: clear message from `failure.json` when present; hint path to workdir `dism-transcript.log` when that file exists.
5. Same file channel: `apply-status.txt` keys unchanged.

## Non-goals

- Dedicated Avalonia Attach / log window
- Changing Watch-Host into a product UI (leave stopgap alone)
- Structured progress event bus
- Fake completion `%` from stage index
- Spectre / OpenTUI / new NuGet

## Presentation model

Extend `ApplyBuildPresentation` / `ApplyBuildPresentationFormat`:

| Field | Source |
|-------|--------|
| `StageLine` | `Building: {opcode}` / `Failed: {opcode}` |
| `AliveLine` | Latest trail heartbeat → `MountInstallWim · 18m 23s` (or `working…` if stage active and no heartbeat yet) |
| `ProgressPercent` | Latest `quality hash N%` only |
| `IsProgressIndeterminate` | true when no real `%` |
| `StepCue` | Latest `Apply i/n` phase line → `Step i of n` |
| `StatusTail` / activity lines | Filtered milestones (existing) |
| `FailureDetail` | `failure.json` message when stage is `failed:*` |
| `TranscriptHint` | If `{work}/dism-transcript.log` exists → short path hint string |

Poll loop: update **AliveLine / progress / step every tick** even when StageLine+tail unchanged.

## Review layout (busy)

Single composition under Build (no second window):

1. Stage line (BuildStatus)
2. Alive line (elapsed) — visible whenever busy
3. StepCue (if any)
4. ProgressBar (always when busy)
5. Activity: ScrollViewer of milestone lines (existing StatusTail)
6. On fail: FailureDetail + TranscriptHint above Flash

## Success

- Long MountInstallWim in Wizard: bar spins, alive elapsed advances each poll, milestones visible.
- Hash phase: bar determinate from trail proof.
- Failure: user sees message + transcript path without opening Watch.
- `just check` green; no new Avalonia window project.
