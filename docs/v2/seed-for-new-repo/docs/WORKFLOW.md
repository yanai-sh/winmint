# Agent workflow (idea → Smoke → next vertical)

WinMint v2 is a **multi-session** build. Use the Matt Pocock skill flow below. Do not start coding from a blank chat without a spec and tickets.

## After the repo exists

1. **`/setup-matt-pocock-skills`** — configure issue tracker, triage labels, doc layout.
2. Confirm **`CONTEXT.md`** and **`docs/decisions/`** are present (from the seed copy).
3. In **one unbroken planning window** (don’t compact until tickets exist):
   - **`/to-spec`** — synthesize the **Smoke** vertical only (see [ARCHITECTURE.md](ARCHITECTURE.md)). Destination: Hyper-V green with splash + DMA evidence.
   - **`/to-tickets`** — approve tracer-bullet tickets with blocking edges (pre-planned commit history).
4. Then **`/implement` one ticket per session**, fresh context each time. Each run: TDD → code-review → commit when asked.
5. After Smoke is green: new `/to-spec` + `/to-tickets` for the next vertical (e.g. Avalonia wizard). Do not bolt every future feature onto the Smoke ticket set.

### Wayfinder

**Skip `/wayfinder` by default.** Architecture fog was cleared before the repo was created. Use wayfinder only if writing the Smoke spec stalls on a sharp undecided question; destination then is “Smoke spec ready,” not “all of WinMint.”

## Commits and milestones

| Artifact | Owner | Meaning |
|----------|--------|---------|
| **Milestone** | Spec destination | e.g. “Smoke Hyper-V green” from `/to-spec` |
| **Planned commits** | Approved tickets | Each `/to-tickets` slice ≈ one (or few) intentional commits; blockers first |
| **Commit execution** | `/implement` | Build that ticket only; conventional commit when requested |
| **Blocking edges** | Issue tracker | Work only the frontier (unblocked tickets) |
| **Later milestones** | New spec | Wizard, debloat, hardware = new `/to-spec` + `/to-tickets` |

**History rule:** keep planned slice boundaries visible. Don’t merge half-tickets; don’t squash away the ticket-shaped history unless the team explicitly chooses squash merges.

## Out of scope for the first spec

- Avalonia wizard (after Smoke)
- Debloat / keep-flag matrix
- BitLocker / device-encryption policy
- Physical hardware acceptance
- Back-compat with WinMint v1 profiles or CLI
