# Samples

| Sample | Purpose | Lane | Wipe risk |
|--------|---------|------|-----------|
| `sl7.profile.json` | **Maintainer Smoke** + Gate B / Primary wipe — this machine’s install target | Release via `primary-gate`; Smoke uses Test lane | Yes — needs `passwordPath` |
| `acceptance.profile.json` | Thin debloat pin list (Acceptance preset); same Israel DMA settle as SL7 | Test | No |
| `smoke.profile.json` | Minimal Hyper-V / warm-media plumbing | Test | No |
| `israel.profile.json` | DMA settle-only lab | Test | No |

Host preset **`recommended`** expands to remove-lists at plan time; JSON never embeds preset names.

Product-curated host path (issue #136): `just curated-emit` / `winmint emit-defaults --out …` (see `CuratedDefaults` in Orchestrator). Distinct from Primary `sl7.profile.json`.

`sl7.profile.json` password: `.scratch/sl7.password` (next to the sample; do not commit it).
`just smoke` / `just smoke-maintainer` default to `sl7.profile.json`.
