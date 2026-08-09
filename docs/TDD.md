# TDD plan — WinMint v2 Smoke

**Authority:** PLAN, ARCHITECTURE, DESIGN grill, module designs, TDD skill.  
**Rule:** No test at an unconfirmed seam.  
**Backlog:** [TICKETS](TICKETS.md) (closed index — next work is maintainer pick / new issue).

## Speed rules

| | Rule |
|---|------|
| **Should** | Day-to-day = S1–S3 (`just check` + fakes); Smoke = `Test` lane + stub jobs; metal jobs share S3 executor; CI = scaffold only (no VM / no ISO); S4 fail-fast on stalls (don’t burn the 90‑min wall-clock timeout) |
| **Could** | Diff VHD from a parent base; rebuild ISO only when plan/payload digests change; careful servicing workdir reuse — harness-only, ticket **10** |
| **Don’t** | Skip S4 hard evidence; invent a Hyper-V-only settle/executor path “for speed” |

## Confirmed seams (test here only)

| Seam | Module interface | Dependency category | Tickets (post-gate) |
|------|------------------|---------------------|---------------------|
| **S1** | BuildPlan (`TryParseProfile`, `SerializeProfile`, `Plan`) | In-process | 01, 09, 11, 16 |
| **S1b** | Host keep-flag presets + Wizard packages (`KeepFlagPresets.TryExpand` + `IdList.FromMultiline` → Profile → Plan/Serialize) | In-process | 15, 22 |
| **S1c** | `ProfileFile.TryLoad` (host Profile + `passwordPath` materialization) | Local-substitutable OS (real temp dirs) | 91 |
| **S2** | ImageServicing (`Apply`) | True external (DISM) — fake when port exists | 02, 09 |
| **S3** | ProvisioningSession (`Run` + env adapters) | Local-substitutable OS | 03–08, 13, 16, 21 |
| **S4** | Hyper-V Smoke acceptance (“run → guest evidence”) | Harness + VM | 10 |
| **S5** | Metal Apply acceptance (“build → apply evidence”, pre-wipe) | Harness on build host | 63 |

Do **not** test: private phase helpers, splash pixels (except status→presenter via `ISplashPresenter`), DISM internals, v1 scripts, evidence JSON as control plane.

**S4 vs S5:** S4 proves FirstLogon inside a Hyper-V VM (splash, DMA, unlock). S5 proves ImageServicing Apply on the **physical build host** (ISO built, driver inventory, digests) — **never** a bare-metal install or USB boot. Substituting S4 for S5 (or vice versa) is invalid.

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
| passwordPath purity (ticket **91**) | Path-only parse never reads; both sources conflict; unresolved path fails Plan; serialize omits inline password when path set |

### S1c — ProfileFile

- Real temporary directories only (no `IFileSystem` port).
- Assert: absolute + Profile-relative resolution (CWD-independent), ambient drive/root-relative fail closed, missing Profile/password file, CR/LF strip, empty file → Plan `account.password.required`, source conflict before password-file I/O, authored path retained.

### S2 — ImageServicing

- Prefer fake elevated runner when introduced (same PR as port).
- Assert: stage order, Shell stamp path param, lane params; not ISO bytes.
- Kernels: no Profile branching (architecture violation if present).
- **Invariant 7:** never commit multi-edition WIM — Mount splits; Export fail-closes ([IMAGESERVICING](design/IMAGESERVICING.md#invariants)).

### S3 — ProvisioningSession

See [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md#s3-test-strategy-locked). Hyper-V **not** required. Use `SessionEnvironment` fakes + `TimeProvider`. Assert paint-before-settle **order**; wall-clock paint budget is S4.

### S4 — Hyper-V acceptance

- One harness entry → **guest** evidence (`tools/vm/`).
- Splash before Explorer; DMA hard fields; unlock; lane marker; record time-to-first-paint ([SPLASH](design/SPLASH.md)).
- Keep-flag: apply digests `removed.appx.<id>=absent` for acceptance pinned remove-list (ADR-006 / ticket **14**).
- Not part of `just check`. Does **not** prove bare-metal driver correctness.

### S5 — Metal acceptance (pre-wipe)

- One harness entry → **Apply workdir** evidence (`tools/metal/`).
- Real elevated Apply against Source ISO offline WIM on the build host — safe on the install-target laptop (no wipe, no USB boot).
- Assert: `evidence.json` lane + digests; when Profile has `drivers`, `WinMint-DriverInventory.json` (firmware excluded, included count > 0) and `DisableCoInstallers` digest.
- Fixture assert tests: `[Trait("Category", "Metal")]` — excluded from `just check`.
- Destructive bare-metal install is **manual only**, after S5 green — never automated by the harness.

## Gate commands

```powershell
just check          # S1–S3 (excludes Category=S4 and Category=Metal)
# maintainer:
just metal ISO=…    # S5 — ticket 63 gate B (pre-wipe)
just metal-assert WORK=…
just smoke          # S4 Hyper-V — ticket 10
```

## Anti-patterns

- Private-method tests / InternalsVisibleTo to reach past `Run`.
- File mailbox control-plane assertions.
- Whole-unattend snapshots without Ireland/autologon targets.
- Horizontal “write all tests then code.”
- MediatR/Generic Host for testability theater.
