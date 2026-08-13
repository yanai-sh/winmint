# Spec: Dynamic output ISO filename

**Status:** Shipped — `7e4e938` (`feat(servicing): name Output ISO winmint_{profile}_{lane}_{timestamp}`)  
**Date:** 2026-08-12  
**Authority:** [BUILDPLAN](../design/BUILDPLAN.md) · [IMAGESERVICING](../design/IMAGESERVICING.md) · [CONTEXT](../../CONTEXT.md) (Primary / Gate B)

## Problem

Default output leaf is always `out.iso`. That name is opaque on USB folders, Flash guidance, and workdirs that hold more than one build artifact over time. Operators need the filename itself to say **what** and **when**.

## Goal

When `OutputIsoPath` / `--out` is unset, every build (Wizard, Cli, Smoke, Gate B) writes:

```text
winmint_{profileStem}_{lane}_{yyyyMMdd-HHmmss}.iso
```

Example: `winmint_sl7_Release_20260812-092415.iso`

Still under the existing work directory. Explicit `--out` / `OutputIsoPath` wins unchanged.

## Naming rules

| Part | Source | Notes |
|------|--------|--------|
| `winmint` | literal prefix | Product identity |
| `profileStem` | Profile path file name | Strip `.profile.json` then `.json`; sanitize to `[A-Za-z0-9._-]`; empty → `profile` |
| `lane` | ImageQuality | `Test` or `Release` only |
| timestamp | Local clock at default-path resolution | `yyyyMMdd-HHmmss` (no colons) |

No username/hostname in the leaf — builder identity stays in evidence / host logs.

## Seam

One Orchestrator helper (e.g. `OutputIsoNaming.DefaultFileName` / `DefaultPath`) used by:

- Cli (when `--out` omitted)
- Wizard build (when output path omitted)
- ImageServicing materialize fallback (when `ServicingRun.OutputIsoPath` is null)

Do not fork naming logic into metal scripts.

## Consumers

Anything that today assumes the leaf is `out.iso` must resolve the path from:

1. `evidence.json` → `outputIsoPath` (preferred), or
2. Exactly one `winmint_*.iso` in the workdir (fallback while evidence is mid-write)

Applies to: metal assert, smoke reuse/`SkipApply`, flash guidance copy, artifact hygiene, Justfile/README/`primary-gate` wording, Wizard Review flash strip.

SHA check remains `digests.outputIso.sha256` vs `Get-FileHash` on the resolved path — filename does not replace the digest.

## Out of scope

- Renaming an ISO already on disk
- Changing workdir layout (`sl7-primary`, `.scratch/…`)
- Putting user/host in the filename
- ADR (reversible default; not surprising once docs match)

## Success

- Fresh Gate B / Test metal / Wizard builds produce `winmint_*_{lane}_*.iso` under the workdir
- `evidence.json` `outputIsoPath` matches that file; digest still verifies
- Explicit `--out` still forces an exact path
- `just check` green; metal assert finds the ISO without hardcoding `out.iso`
