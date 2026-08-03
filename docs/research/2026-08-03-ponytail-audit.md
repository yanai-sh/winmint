# Ponytail audit — WinMint over-engineering (2026-08-03)

**Kind:** complexity audit (lists findings; applies nothing)  
**Lens:** product purpose, not abstract purity  
**Scope:** `src/`, `servicing/`, `payload/`, related design docs — over-engineering and unused flexibility only  
**Out of scope:** correctness bugs, security holes, performance (route those to a normal review)  
**Revised:** same day — reconciled against recent agent sessions ([ticket 02–03 / full Apply](7d900d07-5d59-404d-8e53-f354df5d33db), [BCU → keep-flag wayfinder](ede1a4da-aa21-4b19-a3ab-ee8f61d23980)), open GitHub issues, [TICKETS](../TICKETS.md), and [smoke spec](../specs/2026-07-27-smoke.md)

## Product purpose (the yardstick)

WinMint customizes a user-supplied Windows 11 Source ISO into a tailored install image, then finishes live setup via a single Native AOT Provisioning Supervisor.

| Phase | Who | Job |
|-------|-----|-----|
| Plan | BuildPlan (Orchestrator) | Profile → unattend, stages, payload intent |
| Offline | ImageServicing + elevated `pwsh` kernels | Mutate WIM/ISO; stamp Shell; stage Supervisor + bundle |
| Machine setup | Supervisor `--machine-setup` | Autologon stamp; fail-closed Shell verify; secret hygiene |
| FirstLogon | Supervisor as Winlogon Shell | Splash → DMA settle → jobs → unlock (tickets 04+) |

Smoke stance (explicit): Local+autoLogon only; **lab-grade secrets** — not enterprise credential management ([SECRETS](../design/SECRETS.md)). Password must live in Winlogon `DefaultPassword` for autoLogon to work. Anything that pretends to “manage secrets” beyond that is likely theater relative to purpose.

**Question this audit answers:** what exists without earning its keep against that purpose *today* (post tickets 01–03; Shell tenure not implemented)?

## Executive summary (revised)

The imaging / Winlogon core is appropriately serious — and after the full Apply session, kernels and ISO digests are real product work, not stubs. The main *remaining* complexity smell is still **shipping the full locked ProvisioningSession surface while only Machine setup runs**: empty adapter interfaces (already called out as judgement in the ticket 03 review), unused Shell-tenure fields, and a secret-scrubber *port* around a small JSON redact.

**Do not cut** things the open M1 backlog or ticket Deliver text explicitly require (`build`/`apply`, wipe behavior, stub job *concept* for ticket 06, digests for evidence). **Do not start** keep-flag product code while M1 tickets 04–10 are open.

**net (actionable cuts only): ~−80–120 lines, −0 deps** — primarily inline wipe + drop empty ports/stubs until 04 lands, plus SetupComplete single source. Broader type-narrowing vs locked design is optional and higher process cost.

### Compact ranking (revised)

| # | Tag | Finding | Status vs backlog |
|---|-----|---------|-------------------|
| 1 | `yagni:` | Empty session ports + `Unsupported*`/`Noop*` stubs | Still valid; ticket 03 review agreed. Soften: 04–08 will fill them — prefer “add with first real adapter” over deleting if 04 starts immediately |
| 2 | `yagni:` | Unused Shell-tenure types (`SessionPolicy`, `AppearanceOnce`, `Reboot`, …) | Softened: scheduled for tickets **07–08**; unused *today*, intentional for M1 |
| 3 | `yagni:` | `ISecretScrubber` + `FileSecretScrubber` *as a port* | Still valid. **Wipe itself is required** (ticket 03 Deliver + SECRETS). Inline; don’t delete the behavior |
| 4 | `yagni:` | Embedded `SetupComplete.cmd` vs `payload/scripts/` | Still valid |
| 5 | `yagni:` | Hard-coded `smoke.stub.*` in every plan | Softened: ticket **06** Deliver + smoke story 10; early but on-path |
| 6 | `shrink:` | `DocumentErrors` wrapper | Still valid (mild) |
| 7 | `shrink:` | Hand-rolled `Result<TOk,TErr>` | Optional; design-shaped |
| 8 | `yagni:` | Unused `TimeProvider` until settle/timeouts | Softened: tickets **05/07** |

**Retracted / not actionable as cuts:**

- ~~Cli `apply` ≡ `build`~~ — ticket **02** Deliver explicitly requires both; implement review kept them on purpose.
- ~~`ImageEvidence.Digests` empty~~ — `RunPlan.ps1` now writes `outputIso.sha256` / `installWim.sha256` after full Apply work.

---

## Reconciliation — recent activity, tickets, specs

### Where M1 actually is

| Item | State |
|------|--------|
| Tickets **01–03** | Done (issues #3–#5 closed). Machine setup + secret wipe shipped (`feb0f1c` era) |
| Full Apply / DISM path | Landed in [ticket 02–03 / full Apply](7d900d07-5d59-404d-8e53-f354df5d33db) after stub DoD — real mount/export/oscdimg + digests |
| Next M1 product ticket | **04** Shell splash — blocked on splash spike appendix ([TICKETS](../TICKETS.md), [SPLASH](../design/SPLASH.md)) |
| Open M1 issues | **#6–#12** = tickets 04–10 |
| Open non-M1 | Keep-flag wayfinder **#13** + grilling/task children (**#16–#21**; research siblings closed as decisions land) — **docs/decisions only until ticket 10 green** ([BCU → keep-flag wayfinder](ede1a4da-aa21-4b19-a3ab-ee8f61d23980)) |

Smoke spec destination unchanged: Hyper-V Smoke green with splash + DMA hard-field evidence ([smoke spec](../specs/2026-07-27-smoke.md)). Debloat / keep-flag remains **Out of Scope** for Smoke / “Explicitly not in M1 backlog.”

### What recent sessions change in the audit

1. **Ticket 03 already named empty adapter stubs as judgement debt** — same as Finding 1. Confirms the smell; does not make deleting them free if 04 is next week.
2. **`FileSecretScrubber` was a review fix** (regex wipe → JSON wipe; wipe after Shell fail path) to meet “secret wipe,” not a speculative feature. Audit target is the *abstraction*, not the wipe.
3. **`build`/`apply` dual verbs are ticket text**, not accidental duplication — retract as a cut.
4. **Digests are harness/evidence payload** after real ISO Apply — retract as empty yagni.
5. **Keep-flag wayfinder is the larger *process* risk right now:** grilling #16–#20 / packaging #21 must not pull AppX removal or Profile matrix code into `src/` before M1 Smoke. That would dwarf any ProvisioningSession stub noise.

### Spec / ticket alignment for remaining findings

| Finding | Smoke / TICKETS alignment |
|---------|---------------------------|
| Empty ports | PROVISIONINGSESSION locked bag; tickets **04–08** own the adapters. Prefer fill-on-ticket over delete-then-restore if 04 starts soon |
| Shell-tenure types | Stories 11–13, tickets **07–08** — keep in design; optional to thin C# until then |
| Secret wipe | Story 4 / ticket **03** / SECRETS — **keep behavior**; shrink port |
| Stub jobs in Plan | Story 10 / ticket **06** — early emission OK; empty list until 06 is also fine |
| SetupComplete dual source | No ticket requires embedding — pure drift |
| Keep-flag in `src/` | Spec Out of Scope; wayfinder destination is design-accepted docs only |

## Method

- Walked product vocabulary ([CONTEXT](../../CONTEXT.md)) and secret/session design.
- Inventory of C# / pwsh under `src/`, `servicing/`, `payload/` (excluding `bin`/`obj`).
- Tag hunt: single-implementation interfaces, empty ports, unused fields, duplicate verbs, hand-rolled wrappers.
- Tags: `delete` · `stdlib` · `native` · `yagni` · `shrink` (ponytail-audit vocabulary).

### Approximate source sizes (non-bin lines)

| Lines | Path |
|------:|------|
| 274 | `src/WinMint.Cli/Program.cs` |
| 222 | `servicing/RunPlan.ps1` |
| 219 | `src/WinMint.Orchestrator/BuildPlan.cs` |
| 218 | `src/WinMint.Orchestrator/ImageServicing.cs` |
| 187 | `src/WinMint.Orchestrator/PwshElevatedPlanRunner.cs` |
| 107 | `src/WinMint.Provisioning/ProvisioningSession.cs` |
| 102 | `src/WinMint.Provisioning/ProvisioningSession.Types.cs` |
| 75 | `src/WinMint.Provisioning/Program.cs` |
| 57 | `src/WinMint.Provisioning/BundleLoader.cs` |
| 29 | `src/WinMint.Provisioning/FileSecretScrubber.cs` |
| 26 | `src/WinMint.Orchestrator/Result.cs` |

Provisioning types alone are almost as large as the Machine-setup phase machine — a smell when half the types have zero runtime consumers yet.

---

## Finding 1 — Empty adapter ports (biggest remaining smell)

**Tag:** `yagni:` (timing — not “never needed”)  
**Where:** [`ProvisioningSession.Types.cs`](../../src/WinMint.Provisioning/ProvisioningSession.Types.cs), [`Program.cs`](../../src/WinMint.Provisioning/Program.cs), [`MachineSetupTests.cs`](../../tests/WinMint.Tests/MachineSetupTests.cs)  
**Also noted by:** ticket 03 standards review (“Remaining judgement: empty adapter stubs for later tickets (04–08)”) in [ticket 02–03 / full Apply](7d900d07-5d59-404d-8e53-f354df5d33db)

`SessionEnvironment` requires:

| Member | Status today | Filled by |
|--------|----------------|-----------|
| `IWinlogonRegistry` | Real + test fake — **earned** | 03 |
| `ISecretScrubber` | One file scrubber — Finding 3 | 03 (behavior) |
| `ISplashPresenter` | Empty | **04** |
| `IEvidenceSink?` | Empty | **04** |
| `IRegionSnapshot` | Empty | **05** |
| `IProcessHost` | Empty | **06** |
| `ICheckpointStore` | Empty | **08** |
| `TimeProvider` | Unused by Machine setup | **05/07** |

Production wires four `Unsupported*` marker classes. Tests wire four `Noop*` markers.

**Why it happened:** [PROVISIONINGSESSION](../design/PROVISIONINGSESSION.md) locked the full env bag so tickets 03–08 share one shape.

**Cut advice (revised):** If ticket **04** starts next (after splash spike), **fill Splash/Evidence in place** rather than delete-then-restore the env bag. If Machine setup will sit alone for a while, narrow env to Winlogon (+ wipe) and grow on 04. Don’t leave empty interfaces as eternal noops once 04 lands — that is the actual over-engineering failure mode.

---

## Finding 2 — Shell-tenure types with no Machine-setup consumer

**Tag:** `yagni:` (softened — scheduled M1, unused today)  
**Where:** [`ProvisioningSession.Types.cs`](../../src/WinMint.Provisioning/ProvisioningSession.Types.cs)

Loaded / constructed but unused by `Run(MachineSetup)`:

- `SessionPolicy` — six timeouts + `InputLockMode`; ticket **07** DoD uses FakeTimeProvider + these defaults
- `AppearanceOnce` — ticket **07** (appearance once before unlock)
- `CheckpointState` / `SessionOutcome.Reboot` — ticket **08**
- `EvidenceSnapshot` / `EvidenceEmitted` — ticket **04** (write-only projections)
- Bundle `Dma` / `Jobs` — tickets **05** / **06**

**Replacement:** Keep the locked sketch in the design doc. Thinning C# types before 04 is optional; deleting them only to re-add in two sessions is not lazy. Prefer not growing *more* unused fields.

---

## Finding 3 — `FileSecretScrubber` / `ISecretScrubber` (worked example)

**Tag:** `yagni:` (abstraction) — the *hygiene step* is ticket-required; the *port* is not  
**Where:** [`FileSecretScrubber.cs`](../../src/WinMint.Provisioning/FileSecretScrubber.cs), wipe call in [`ProvisioningSession.cs`](../../src/WinMint.Provisioning/ProvisioningSession.cs)  
**Origin:** Ticket **03** Deliver (“secret wipe”) + [SECRETS](../design/SECRETS.md); JSON implementation landed as a standards-review fix in [ticket 02–03 / full Apply](7d900d07-5d59-404d-8e53-f354df5d33db) (replace regex wipe, keep wipe after Shell verify failure).

### What the code does

After autologon stamp and Shell verify/restamp attempt, Machine setup calls `env.Secrets.Wipe(bundle)`. Production scrubber:

1. Reads `C:\Windows\WinMint\bundle.json` (path injected at construction)
2. Parses with `JsonNode`
3. If `"password"` present, sets it to `""` and writes indented JSON back
4. Logs best-effort

It does **not** clear Winlogon `DefaultPassword` (comment admits that). The `ProvisioningBundle` password string in memory is also not wiped (no clear of the record field).

### What the spec says

[SECRETS.md](../design/SECRETS.md):

> Machine setup \| After successful autologon stamp, **wipe** in-memory password buffers (`ISecretScrubber`)

Also: lab-grade only; guest jobs JSON must not round-trip cleartext password; evidence must redact.

So the *named* contract is in-memory wipe. The *implementation* is disk JSON redact. Spec and code diverge; the interface name papered over that.

### Does the product need it?

| Concern | Need? |
|---------|-------|
| Ticket 03 “secret wipe” / leave cleartext in `bundle.json` | **Yes** — keep the behavior |
| Enterprise secret lifecycle | Explicitly **out** of Smoke |
| Clear Winlogon `DefaultPassword` | **No** — autoLogon requires it |
| Pluggable scrubber strategies | **No** — one guest, one file |
| Fail Machine setup if JSON rewrite throws | Debatable; elevates a hygiene step to a hard gate |

**Replacement:** Inline JSON redact (or rewrite DTO without password) after stamp. Delete `ISecretScrubber` + `FileSecretScrubber` + `RecordingSecretScrubber`. **Do not** remove wipe from the Machine-setup phase machine.

---

## Finding 4 — Dual `SetupComplete.cmd` sources

**Tag:** `yagni:` / `shrink:`  
**Where:** [`ImageServicing.cs`](../../src/WinMint.Orchestrator/ImageServicing.cs) (embedded here-string), [`payload/scripts/SetupComplete.cmd`](../../payload/scripts/SetupComplete.cmd)

Materialize writes a hard-coded `@echo off` + Supervisor invoke into `payload/SetupComplete.cmd`. The repo already has the same script under `payload/scripts/`. Drift risk is real (comments already disagree slightly on ticket numbering). No ticket requires embedding.

**Replacement:** Copy/stage the repo file into the work payload directory (same pattern as Supervisor publish copy).

~~Former Finding 4 (Cli `apply` ≡ `build`) **retracted:**~~ ticket **02** Deliver requires both verbs; implement review explicitly kept the twin.

---

## Finding 5 — Stub jobs baked into every plan

**Tag:** `yagni:` (softened)  
**Where:** [`BuildPlan.cs`](../../src/WinMint.Orchestrator/BuildPlan.cs)

Every successful `Plan` emits `smoke.stub.ready` and `smoke.stub.complete`. Ticket **06** Deliver and smoke story 10 call for a Smoke stub job set. Early emission is on-path for M1, not a random placeholder forever — but Machine setup and tickets 04–05 never execute them.

**Replacement (optional):** Empty job list until ticket 06; or leave as-is if you want bundle/plan shape stable for harness work.

~~Former Digests finding **retracted:**~~ `servicing/RunPlan.ps1` hashes output ISO / install.wim into `ImageEvidence.Digests` after the full Apply path.

---

## Finding 6 — `DocumentErrors` wrapper

**Tag:** `shrink:`  
**Where:** [`DocumentErrors.cs`](../../src/WinMint.Orchestrator/DocumentErrors.cs) (3 lines of type)

`DocumentErrors` is a record holding `IReadOnlyList<DocumentError>`. Call sites always unwrap `.Issues`.

**Replacement:** `Result<Profile, IReadOnlyList<DocumentError>>` (or `List<>`). Keep `DocumentError` itself — the structured code/path is useful for Cli reporting.

---

## Finding 7 — Hand-rolled `Result<TOk, TErr>`

**Tag:** `shrink:` (optional)  
**Where:** [`Result.cs`](../../src/WinMint.Orchestrator/Result.cs)

Used consistently by BuildPlan / ImageServicing / Cli — matches the deep-module sketches in design docs. Not accidental. Cost is ~35 lines plus ceremonial `Result.Ok`/`Fail` at every return.

**Replacement:** Keep if typed plan/apply errors are a conscious house style. Otherwise `(TOk? ok, TErr? err)` or exceptions at the Cli edge are shorter. **Do not** introduce a NuGet Result library — that would be the opposite of ponytail.

---

## Finding 8 — Unused `TimeProvider`

**Tag:** `yagni:` (softened)  
**Where:** `SessionEnvironment.Time`

Correct seam for settle deadlines and fake clocks (tickets **05/07**, FakeTimeProvider in 07 DoD). Machine setup only checks `CancellationToken` and never reads `env.Time`.

**Replacement:** Harmless to keep with the env bag; add real use with timeout/settle tickets.

---

## What is *not* over-engineered

These match purpose and earn their complexity:

| Piece | Why it stays |
|-------|----------------|
| `IWinlogonRegistry` + `Win32WinlogonRegistry` | Real OS boundary; fake enables S3 without Hyper-V; encodes defaultuser0 / Shell fail-closed |
| Elevated `pwsh -File` kernels + `IElevatedPlanRunner` | Port shipped *with* test fake (ticket 02 rule); DISM must stay out of unelevated Cli |
| Real DISM/oscdimg path + ISO digests | Full Apply session made evidence hashes real harness input |
| Cli `build` **and** `apply` | Ticket 02 Deliver |
| Secret *wipe behavior* after Machine setup stamp | Ticket 03 + SECRETS (shrink the port, keep the step) |
| BuildPlan Profile parse + password-required plan failure | Trust boundary for Smoke account mode |
| Opcode stage list (not script paths in Profile) | Protects Architecture invariant: no Profile `if` in kernels |
| Workdir preserved on failure | Operability for long Apply runs |
| Single Supervisor binary as Shell | Core product bet vs v1 multi-pwsh + peer Splash |

Do not “simplify” those into in-process DISM from the wizard or guest PowerShell — that would fight [AGENTS.md](../../AGENTS.md) and DESIGN locks.

---

## Tension with locked design

[PROVISIONINGSESSION](../design/PROVISIONINGSESSION.md) **accepted** the full `Run(mode, bundle, env)` bag including empty-capable adapters. This audit does **not** reopen the grill. It records:

1. Locked interface ≠ every field must be *used* in ticket 03.
2. Empty interfaces are judgement debt (ticket 03 review); the fix on the critical path is **fill them in tickets 04–08**, not necessarily delete them the day before 04.
3. SECRETS naming `ISecretScrubber` for “wipe in-memory buffers” invited a class that does disk redact — shrink that without dropping wipe.

Practical stance given open **#6** (ticket 04): prefer fill-on-04 over a narrowing refactor that fights the locked sketch, unless Machine setup will idle alone for a long time.

---

## Suggested cut order (if acted on later)

Do not apply from this document unless a ticket asks. Suggested sequence by payoff / risk **after** reconciling with open backlog:

1. **Inline secret redact; delete `FileSecretScrubber` + `ISecretScrubber`** — keep wipe in the phase machine; drop the port. Align SECRETS wording with disk hygiene if you touch the doc.
2. **Stage `payload/scripts/SetupComplete.cmd` instead of embedding** — remove drift; no ticket conflict.
3. **On ticket 04 start:** replace `UnsupportedSplashPresenter` / null Evidence with real adapters — do not leave empty ports once the ticket that owns them is active.
4. **Optional:** empty stub jobs until ticket 06; thin `DocumentErrors`.
5. **Avoid:** collapsing `build`/`apply` without amending ticket 02 / docs; removing Digests; shipping keep-flag AppX/Profile code before ticket **10**.

Estimated payoff if 1–2 land: **~−80–120 lines, 0 deps removed**.

---

## Anti-finding — what would be over-engineering *next*

From [BCU → keep-flag wayfinder](ede1a4da-aa21-4b19-a3ab-ee8f61d23980) and open issues **#13 / #16–#21**:

- Implementing offline AppX remove, FirstLogon rehydrate cleanup, or Profile keep-matrix **in `src/` now** while M1 tickets **04–10** are open.
- Bundling Bulk Crap Uninstaller (research already rejects this).
- Growing ImageServicing / ProvisioningSession for debloat before the wayfinder packaging ticket (#21) produces an accepted design module + ADR.

That path is larger than any ProvisioningSession stub smell in this audit.

---

## Boundaries reminder

| In this audit | Not in this audit |
|---------------|-------------------|
| Unused flexibility, premature ports, duplicate sources | Whether wipe-fail should fail Machine setup |
| Spec/code mismatch on “in-memory” vs disk scrub *as complexity* | Whether leaving DefaultPassword is a security issue (product-accepted for Smoke) |
| Empty interfaces before their tickets fill them | DMA settle correctness, splash timing, Hyper-V harness |
| Keep-flag *product code* before M1 green | Resolving wayfinder grilling tickets themselves |

---

## Sources in-repo / tracker

- [CONTEXT.md](../../CONTEXT.md) — vocabulary / purpose  
- [AGENTS.md](../../AGENTS.md) — deep modules, no guest pwsh  
- [docs/TICKETS.md](../TICKETS.md) — 01–03 done; 04–10 open  
- [docs/specs/2026-07-27-smoke.md](../specs/2026-07-27-smoke.md)  
- [docs/design/SECRETS.md](../design/SECRETS.md)  
- [docs/design/PROVISIONINGSESSION.md](../design/PROVISIONINGSESSION.md)  
- GitHub: M1 **#6–#12**; keep-flag map **#13** + decision children  
- Sessions: [ticket 02–03 / full Apply](7d900d07-5d59-404d-8e53-f354df5d33db), [BCU → keep-flag wayfinder](ede1a4da-aa21-4b19-a3ab-ee8f61d23980)  
- Implementation: `src/WinMint.Provisioning/*`, `src/WinMint.Orchestrator/*`, `servicing/RunPlan.ps1`
