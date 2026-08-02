# TDD plan — WinMint v2 Smoke

**Authority:** PLAN, ARCHITECTURE, DESIGN grill, module designs, TDD skill.  
**Rule:** No test at an unconfirmed seam.  
**Backlog:** [TICKETS](TICKETS.md) (Released — implement by ticket).

## Speed rules

| | Rule |
|---|------|
| **Should** | Day-to-day = S1–S3 (`just check` + fakes); Smoke = `Test` lane + stub jobs; CI = scaffold only (no VM / no ISO); S4 fail-fast on stalls (don’t burn the 90‑min wall-clock timeout) |
| **Could** | Diff VHD from a parent base; rebuild ISO only when plan/payload digests change; careful servicing workdir reuse — harness-only, ticket **10** |
| **Don’t** | Skip S4 hard evidence; invent a Hyper-V-only settle/executor path “for speed” |

## Confirmed seams (test here only)

| Seam | Module interface | Dependency category | Tickets (post-gate) |
|------|------------------|---------------------|---------------------|
| **S1** | BuildPlan (`TryParseProfile`, `Plan`) | In-process | 01, 09 |
| **S2** | ImageServicing (`Apply`) | True external (DISM) — fake when port exists | 02, 09 |
| **S3** | ProvisioningSession (`Run` + env adapters) | Local-substitutable OS | 03–08 |
| **S4** | Smoke acceptance (“run → evidence”) | Harness | 10 |

Do **not** test: private phase helpers, splash pixels (except status→presenter via `ISplashPresenter`), DISM internals, v1 scripts, evidence JSON as control plane.

## Good test criteria

- Assert **observable outcomes** through the module interface.
- Expected values from **spec literals** (Ireland GeoID `68`, password required, opcodes, lane names).
- Survive internal refactors; mock **adapters**, not private collaborators.
- Vertical slices: one failing test → minimal code → next. No bulk “all tests first.”

## Per-seam strategy

### S1 — BuildPlan

| Slice | Red assertion |
|-------|----------------|
| Bad JSON | Document errors |
| No password + Local+autoLogon | Plan failure |
| DMA on | Ireland latch + settle targets |
| Default Plan | Stub jobs + Test lane + opcodes (not .ps1 paths) |
| Release lane (ticket **09**) | `ExportWim` params differ |

### S2 — ImageServicing

- Prefer fake elevated runner when introduced (same PR as port).
- Assert: stage order, Shell stamp path param, lane params; not ISO bytes.
- Kernels: no Profile branching (architecture violation if present).

### S3 — ProvisioningSession

See [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md#s3-test-strategy-locked). Hyper-V **not** required. Use `SessionEnvironment` fakes + `TimeProvider`. Assert paint-before-settle **order**; wall-clock paint budget is S4.

### S4 — Acceptance

- One harness entry → evidence.
- Splash before Explorer; DMA hard fields; unlock; lane marker; record time-to-first-paint ([SPLASH](design/SPLASH.md)).
- Not part of `just check`.

## Gate commands

```powershell
just check          # scaffold / later S1–S3
# post-gate:
just smoke          # S4 — ticket 10
```

## Anti-patterns

- Private-method tests / InternalsVisibleTo to reach past `Run`.
- File mailbox control-plane assertions.
- Whole-unattend snapshots without Ireland/autologon targets.
- Horizontal “write all tests then code.”
- MediatR/Generic Host for testability theater.
