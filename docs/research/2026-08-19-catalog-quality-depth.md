# Research: Catalog quality module depth

**Date:** 2026-08-19  
**Question:** Catalog quality (ADR-013) already picks the newest same-train Security Update each Apply. Where is the module shallow, and in what order should it deepen?  
**Method:** Architecture review of the ImageServicing Catalog path (resolve helper, `AddQualityUpdates`, `PatchBootWimApply`, BuildPlan opcode). Not OS proof.

**Product change:** none in this note. Living law stays [ADR-013](../decisions/ADR-013-catalog-lcu.md) and [IMAGESERVICING](../design/IMAGESERVICING.md). Approach all three deepenings in this order.

## Findings

1. **Catalog resolve** — B-release vs Preview vs 26H1 was a cluster of helper functions. Apply and `just quality-check` walked the implementation. Fixture HTML and live Catalog already justify two adapters; the missing seam is one Resolve interface.
2. **PatchBoot leak** — LCU then LaunchApply is a real ordering constraint. `state.json` (`skipped`, package lists) was a second control plane into `PatchBootWimApply`. PackageDir ordered leaf lists are the seam.
3. **Plan vs ImageServicing** — Latest LCU is not Profile intent. BuildPlan emitting `AddQualityUpdates` taught callers a Servicing mechanic at the plan seam. ImageServicing Materialize owns the stage (parallel to Prepared media).

Do not merge LaunchApply into AddQualityUpdates.

## Order

Document (this note + CONTEXT) → Resolve interface → PackageDir seam → Materialize-owned opcode.
