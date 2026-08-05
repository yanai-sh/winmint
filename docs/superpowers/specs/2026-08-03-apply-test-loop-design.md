# Apply test-loop improvements

**Date:** 2026-08-03  
**Status:** Approved (design dialogue)  
**Locks:** `--reuse-media` = keep workdir media; stall handling = heartbeat + `STALL_SUSPECT` (no kill)

## Problem

A cold maintainer Apply against a consumer multi-edition ISO is multi-hour (mostly DISM I/O: media copy, single-image export, Unmount/Commit, oscdimg). Day-to-day testing must stay on fakes/`just check`; when a full Apply is needed, reuse prior media, exclude AV where possible, keep the Test lane, and surface progress so long commits are observable without false auto-kills.

## Goals (five wins)

1. **Day-to-day vs maintainer Apply** — document and recipe-separate the fast loop from full Apply.
2. **`--reuse-media`** — skip ISO robocopy + multi→single export when workdir media is already a valid single-image WIM.
3. **Defender exclusions** — one elevated host recipe for `.scratch` (optional ISO path).
4. **Stay on Test lane** — default unchanged; warn loudly if Apply runs with `Release`.
5. **Progress heartbeat** — `<work>/apply-status.txt` every ~30s; `STALL_SUSPECT` if log quiet and `wimserv` CPU flat >10m; never kill processes.

## Non-goals

- Separate cache directory outside `--work`
- Auto-kill of DISM/`wimserv` on stall suspect
- CI full-ISO Apply
- Release-lane export optimization (ticket 09)
- Changing invariant 7 (single-image WIM before commit)

## Design

### 1. Testing loops (docs + Just)

- README short **Testing loops** section:
  - Daily: `just check` (no ISO, fake elevated runner in unit tests).
  - Maintainer Apply: multi-hour; use `just apply-maintainer` / `--reuse-media` after a successful cold run.
- `just apply-maintainer ISO WORK PROFILE="samples/smoke.profile.json"`:
  - Prints a one-line wall-clock warning.
  - Invokes Cli `build` with `--iso` / `--work` / profile; passes `--reuse-media` when `WORK/media/sources/.winmint-single-index` exists (else cold).
  - Requires prior `just publish-provisioning` (document; fail via existing supervisor-missing path if absent).

### 2. `--reuse-media` (Cli → Mount kernel)

**Cli**

- `bool` option `--reuse-media` on `build`.
- Plumb into `ServicingRun` (new field `ReuseMedia`).
- `ImageServicing.Materialize` adds `reuseMedia=true|false` to `MountInstallWim` parameters.

**Mount-InstallWim.ps1**

When `reuseMedia` is true:

| Condition | Behavior |
|-----------|----------|
| `media/sources/install.wim` missing, or marker missing, or WIM index count ≠ 1 | **Fail closed** with message to re-run without `--reuse-media` |
| Valid single-image + marker | Skip ISO mount/robocopy; skip Export-Image; mount index 1 |

When `reuseMedia` is false/absent: keep current behavior (copy if no WIM; export if multi-index; marker reuse for mount index).

Marker file remains `media/sources/.winmint-single-index` (existing).

### 3. Defender exclusions

- `just exclude-scratch ISO=""` → elevated pwsh:
  - `Add-MpPreference -ExclusionPath` for `<repo>/.scratch`
  - If `ISO` non-empty, also exclude that file path
- Document admin requirement and that this is host-local hygiene, not a product dependency.
- No other MP preference changes.

### 4. Test lane default + Release warning

- Defaults stay `ImageQualityLane.Test` (no change to BuildPlan defaults).
- In Cli `RunApply`, after a successful plan load: if `artifacts.Manifest.ImageQuality == Release`, write one stderr line warning that Release is slower (`compression=max` + cleanup) and Test is preferred for iterative Apply.
- Do not block Release.

### 5. Heartbeat + stall suspect (`RunPlan.ps1`)

- At start: write/clear `<WorkDirectory>/apply-status.txt`.
- Background job every ~30s while stages run:
  - `updated=<iso8601>`
  - `stage=<opcode or idle>`
  - `log=<path to current stage log if any>`
  - `last_line=<last non-empty line of that log, truncated>`
  - `dism_cpu` / `wimserv_cpu` if processes exist
  - If same stage, log mtime unchanged, and `wimserv` CPU delta ≈ 0 for **>10 minutes**: set `STALL_SUSPECT=1` and a one-line reason (still no kill)
- On normal or failure exit: stop job; leave final status snapshot; do not delete the file.
- Maintainer watch: `Get-Content <work>\apply-status.txt -Wait` (document in README / just help text).

## Error handling

- `--reuse-media` invalid media → Mount kernel throw → existing `failure.json` + workdir preserve.
- Heartbeat failures are best-effort (`ponytail:`); must not fail the Apply.
- `exclude-scratch` failures surface as recipe errors (permissions / MpPreference).

## Testing

- Unit test: `Apply` with fake runner asserts `MountInstallWim` parameters include `reuseMedia=true` when `ServicingRun.ReuseMedia` is set.
- Unit test or assert: Cli wiring covered indirectly via Materialize; no DISM in `just check`.
- Heartbeat: no package-wide suite requirement; logic stays in `RunPlan.ps1` (manual maintainer Apply validates). Optional tiny assert only if a pure helper is extracted — YAGNI: keep in script unless extraction is free.

## Files (expected)

| Path | Change |
|------|--------|
| `src/WinMint.Cli/Program.cs` | `--reuse-media`; Release warning |
| `src/WinMint.Orchestrator/ImageServicing.Types.cs` | `ServicingRun.ReuseMedia` |
| `src/WinMint.Orchestrator/ImageServicing.cs` | Materialize param |
| `servicing/Mount-InstallWim.ps1` | Fail-closed reuse path |
| `servicing/RunPlan.ps1` | Heartbeat / `STALL_SUSPECT` |
| `Justfile` | `apply-maintainer`, `exclude-scratch` |
| `README.md` | Testing loops blurb |
| `tests/WinMint.Tests/ImageServicingApplyTests.cs` | `reuseMedia` param |

## Acceptance

- `just check` green.
- Cold Apply unchanged without `--reuse-media`.
- With valid single-image media + `--reuse-media`, Mount log shows reuse skip (no robocopy / no multi-index export).
- `apply-status.txt` updates during Apply; can show `STALL_SUSPECT` without killing.
- Release Apply prints stderr warning; Test does not.
