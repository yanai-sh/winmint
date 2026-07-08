# ADR-008: BuildProfile schema v4 breaking migration

**Status:** Accepted  
**Date:** 2026-07-07

### Context

Profile v3 mixed tweak toggles, legacy privacy shapes, and authored AppX prefixes. v4 consolidates subtractive intent under `keep` and posture under structured enums.

### Decision

`schemaVersion` must be **4**; v3 profiles are rejected at validation. Migrate external v3 with `tools/dev/Convert-WinMintBuildProfileV3ToV4.ps1` (archive after migration window — Track 5).

Breaking schema changes require schema + contract tests in the same change.

### Consequences

Single profile vocabulary for CLI, wizard, and engine.

### Review trigger

Next breaking schema only with migrator + ADR superseding this one.
