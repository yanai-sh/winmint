# Wizard edition probe — design lock

**Date:** 2026-08-05  
**Status:** Spec’d for ticket · DESIGN still parks until implement unlocks  
**Related:** Phase A/B Wizard UX; [IMAGESERVICING](../../design/IMAGESERVICING.md) §8–10; `servicing/Wim-Metadata.ps1`; CTT/WIM-discipline findings (2026-08-05)

## Locks

| Topic | Decision |
|-------|----------|
| Where | Host-side, unelevated, **before** Apply — not a servicing kernel |
| Semantics | Probe selects the **source archive index** Mount will export to a **single-index** `install.wim`. It does **not** add unattend `ImageInstall` `/IMAGE/INDEX` MetaData — after Apply, Setup sees one image (existing invariant §8). |
| Input | Existing Source ISO path (already chosen on Source step) |
| Fields | Rows use Get-WimInfo field set aligned with WIM discipline: **Index, Name, Architecture, Edition** (when present), **Version/Build** when present |
| Incomplete metadata | Empty / `undefined` / missing **Name** → do not offer as a safe pick (fail that row or fail the probe with a readable code). Same footgun class as CTT “DISM exit 0, bad metadata.” |
| Parser | **Reuse** `ConvertFrom-WimInfoText` / `servicing/Wim-Metadata.ps1` (or shared fixture from that helper) — do not invent a second Get-WimInfo dialect in C# |
| Apply path | Selected index → existing `ServicingRun.WimIndex` / `WizardBuildInput.WimIndex` only |
| Default | Keep host-SKU default (`HostEdition`) until user picks; whole-probe failure → keep default + surface error (fail open on probe UX, fail closed on Build with bad index later) |
| Kernels | Unchanged — still opaque `wimIndex` param; no edition branching |
| Ordering | Prefer implement **after / against** WIM metadata helper (already in tree); do not race a fork |
| Out | Changing Cli Smoke Pro default; mounting/exporting during probe; unattend ImageInstall MetaData; WebView2; auto-pick by marketing-name heuristics; true DISM % progress |

## Product role

Author can see which editions are **in this ISO** and choose which source index Apply will export, instead of trusting Home=1 / Pro=3 folklore when the media differs. Wrong index = wrong Name/Edition in the committed single image; incomplete metadata is treated as unsafe.

## Gate

Avalonia-free probe unit tests (golden Get-WimInfo text via Wim-Metadata / fake adapter); Wizard Source UI shows picker when probe succeeds with complete rows. `just check` green. Manual: real multi-edition ISO → list matches `dism /Get-WimInfo`; incomplete-Name fixture refused.
