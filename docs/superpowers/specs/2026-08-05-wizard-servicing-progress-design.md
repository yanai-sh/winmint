# Wizard servicing stage progress — design lock

**Date:** 2026-08-05  
**Status:** Shipped (issue **59**) · DESIGN unlocked for opcode-stage progress  
 
**Related:** Phase B busy/cancel; [IMAGESERVICING](../../design/IMAGESERVICING.md); `servicing/RunPlan.ps1` `apply-status.txt`

## Locks

| Topic | Decision |
|-------|----------|
| Honesty | Progress = **opcode stage** from existing `{work}/apply-status.txt` (`stage=`, `log=`), not inventing a fake checklist |
| UI | Review (or Build chrome): current stage label + optional index/count once known; keep busy + Cancel |
| Polling | Unelevated host watches status file while elevated Apply runs (same work dir Wizard already chose) |
| Enrichment | Optional thin RunPlan fields (stage index/count) only if needed for UX — still opcode-granular |
| Cancel | Existing `CancellationToken` → kill elevated tree; no promise of clean mid-DISM rollback beyond today’s leftover-mount cleanup |
| Out | True DISM byte/% progress channels; Progress bar lied against wall-clock; stage list when Apply has not started |

## Product role

During Build, author sees which servicing opcode is running (and which log file), so a long Apply does not look hung.

## Gate

Unit tests: status-file parser / watcher with temp files (no DISM). Manual: Save → Build → UAC → UI advances through Mount…Export…BuildIso → done/fail.
