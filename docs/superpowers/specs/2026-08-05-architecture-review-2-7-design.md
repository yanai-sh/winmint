# Architecture review leftovers 2–7

**Date:** 2026-08-05  
**Status:** Approved (batch-grill)  
**Locks:** Act #2+#4 · Defer #3+#7 · Reject #5 (silence) · Reject+trail #6 · one commit on `dev` · no ROADMAP entries

## Outcome

Mix (grill C): act on cheap Worth-exploring; reject Speculative with trails where agents would re-open locked interfaces; defer the rest with footnotes.

## Decisions

| # | Candidate | Disposition | Ship |
|---|-----------|-------------|------|
| 2 | Catalog-id match locality | **Act** | Fake calls `MatchesCatalogId`; KEEPFLAG Offline vs live field map; PS predicate stays divergent |
| 3 | RunJobs Fail ceremony | **Defer** | PROVISIONINGSESSION footnote — extract when next job-kind edit touches branches |
| 4 | Win32RegionLocaleTests past seam | **Act** | xUnit `HostCultureMutating` collection (`DisableParallelization`) |
| 5 | BuildPlan catalog-membership helper | **Reject** | Silence (deletion test fails) |
| 6 | Collapse `DocumentErrors` | **Reject+trail** | BUILDPLAN locked-interface note |
| 7 | Cli plan dump vs Materialize serializers | **Defer** | BUILDPLAN footnote next to #48-class serialize defer |

## Out of scope (not ROADMAP)

Document here so future architecture reviews do not invent a backlog. Do **not** add these to [ROADMAP](../../ROADMAP.md).

- Shared Contracts assembly for catalog-id match
- Align Offline `PackageName` matcher to live FamilyName/FullName without a real mismatch bite
- Redesign `IRegionSnapshot` / move locale probe fully behind the port for this change
- Extract RunJobs `Fail(…)` as a standalone deepen
- Fourth-catalog `ValidateCatalogMembership` helper
- Merge Cli `WritePlanArtifacts` into Materialize `*File` serializers before the next StageParams drift
- New ADR or GitHub issues for Reject/Defer (footnotes + this spec are the trail)

## Packaging

One session, one commit on `dev`. No tickets. No PR (solo).
