# Ponytail audit — WinMint over-engineering (2026-08-03)

**Kind:** one-shot complexity audit (lists findings; applies nothing)  
**Lens:** product purpose, not abstract purity  
**Scope:** `src/`, `servicing/`, `payload/`, related design docs — over-engineering and unused flexibility only  
**Out of scope:** correctness bugs, security holes, performance (route those to a normal review)

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

## Executive summary

The imaging / Winlogon core is appropriately serious. The main bloat is **shipping the full locked ProvisioningSession surface before Shell tenure exists**: empty adapter interfaces, unused policy/evidence types, and a secret-scrubber *port* for a five-line JSON redact.

**net: ~−150–200 lines, −0 dependencies possible** if deferred ports and unused Shell types are cut back to Machine-setup minimum, wipe is inlined, and a few Cli/servicing twins collapse.

Compact ranking (one line each):

1. `yagni:` Empty session ports + stub classes. Drop until ticket 04+.
2. `yagni:` Unused Shell-tenure types (`SessionPolicy`, `AppearanceOnce`, …). Defer.
3. `yagni:` `ISecretScrubber` + `FileSecretScrubber`. Inline redact (or omit field).
4. `shrink:` Cli `apply` ≡ `build`. Keep one verb.
5. `yagni:` Embedded `SetupComplete.cmd` string vs `payload/scripts/`. One source.
6. `yagni:` `ImageEvidence.Digests` with nothing hashed yet.
7. `yagni:` Hard-coded `smoke.stub.*` jobs every plan.
8. `shrink:` `DocumentErrors` list wrapper.
9. `shrink:` Hand-rolled `Result<TOk,TErr>` (optional; design-shaped).
10. `yagni:` Unused `TimeProvider` on Machine-setup env.

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

## Finding 1 — Empty adapter ports (biggest cut)

**Tag:** `yagni:`  
**Where:** [`ProvisioningSession.Types.cs`](../../src/WinMint.Provisioning/ProvisioningSession.Types.cs), [`Program.cs`](../../src/WinMint.Provisioning/Program.cs), [`MachineSetupTests.cs`](../../tests/WinMint.Tests/MachineSetupTests.cs)

`SessionEnvironment` requires:

| Member | Status today |
|--------|----------------|
| `IWinlogonRegistry` | Real (`Win32WinlogonRegistry`) + test fake — **earned** |
| `ISecretScrubber` | One file scrubber — see Finding 3 |
| `IRegionSnapshot` | Empty; comment “Ticket 05” |
| `IProcessHost` | Empty; “Ticket 06” |
| `ISplashPresenter` | Empty; “Ticket 04” |
| `ICheckpointStore` | Empty; “Ticket 08” |
| `IEvidenceSink?` | Empty; “Ticket 04” |
| `TimeProvider` | Unused by Machine setup |

Production wires four `Unsupported*` marker classes. Tests wire four `Noop*` markers. Every `Env(...)` call pays that tax for phases that do not run.

**Why it happened:** [PROVISIONINGSESSION](../design/PROVISIONINGSESSION.md) locked the full env bag at design time so tickets 03–08 share one shape. That is a valid design choice; shipping empty interfaces *now* still violates the repo’s own port rule spirit (“introduce when a second adapter / fake shares the shape” — see ARCHITECTURE / IMAGESERVICING for ImageServicing).

**Replacement:** For Machine setup, `SessionEnvironment` = Winlogon (+ optional wipe callback / path). Add Region/Splash/… in the same change that implements them.

**Cut weight:** highest — removes stub classes, shrinks every test helper, and stops pretending Shell tenure is already wired.

---

## Finding 2 — Shell-tenure types with no Machine-setup consumer

**Tag:** `yagni:`  
**Where:** [`ProvisioningSession.Types.cs`](../../src/WinMint.Provisioning/ProvisioningSession.Types.cs)

Loaded / constructed but unused by `Run(MachineSetup)`:

- `SessionPolicy` — six timeouts + `InputLockMode` (`None`/`Soft`/`Hard`); only `SmokeDefaults` is referenced when building a bundle
- `AppearanceOnce`, `CheckpointState` — optional bundle fields, never read
- `EvidenceSnapshot` / `EvidenceEmitted` — always `[]`
- `SessionOutcome.Reboot` — never returned
- Bundle `Dma` / `Jobs` — parsed or stubbed for later; Machine setup ignores them

**Replacement:** Keep the locked sketch in the design doc. Narrow the *implemented* types to what ticket 03 needs (`Account`, `Supervisor`, outcomes Complete/Failed). Grow the record when Shell tenure lands.

**Note:** This is “design ahead of code,” not accidental junk. Still over-engineering relative to *running* purpose today.

---

## Finding 3 — `FileSecretScrubber` / `ISecretScrubber` (worked example)

**Tag:** `yagni:` (abstraction) — the *hygiene step* is mildly useful; the *port* is not  
**Where:** [`FileSecretScrubber.cs`](../../src/WinMint.Provisioning/FileSecretScrubber.cs), wipe call in [`ProvisioningSession.cs`](../../src/WinMint.Provisioning/ProvisioningSession.cs)

### What the code does

After autologon stamp and Shell verify/restamp attempt, Machine setup calls `env.Secrets.Wipe(bundle)`. Production scrubber:

1. Reads `C:\Windows\WinMint\bundle.json` (path injected at construction)
2. Parses with `JsonNode`
3. If `"password"` present, sets it to `""` and writes indented JSON back
4. Logs best-effort

It does **not** clear Winlogon `DefaultPassword` (comment admits that). The `ProvisioningBundle` password string in memory is also not wiped (no `SecureString` / clear of the record field).

### What the spec says

[SECRETS.md](../design/SECRETS.md):

> Machine setup \| After successful autologon stamp, **wipe** in-memory password buffers (`ISecretScrubber`)

Also: lab-grade only; guest jobs JSON must not round-trip cleartext password; evidence must redact.

So the *named* contract is in-memory wipe. The *implementation* is disk JSON redact. Spec and code diverge; the interface name papered over that.

### Does the product need it?

| Concern | Need? |
|---------|-------|
| Leave cleartext in `bundle.json` after stamp | Mild lab hygiene — yes, worth clearing the field |
| Enterprise secret lifecycle | Explicitly **out** of Smoke |
| Clear Winlogon `DefaultPassword` | **No** — autoLogon requires it |
| Pluggable scrubber strategies | **No** — one guest, one file |
| Fail Machine setup if JSON rewrite throws | Debatable; elevates a hygiene step to a hard gate |

Password must be staged somehow for SetupComplete to stamp autologon. After stamp, leaving `""` in the bundle is fine. That is ~5 lines next to the stamp, not a sealed class + interface + recording fake.

**Replacement options (pick one):**

1. **Inline redact** after successful `SetAutoLogon` (same JSON clear).
2. **Rewrite bundle once** without password using existing `BundleLoader` / DTO path (one serializer, not JsonNode + source-gen side by side).
3. **Stronger but still simple:** after stamp, delete only the password property; keep the rest of the bundle for later Shell tenure.

**Do not:** grow scrubber into credential managers / LSA / BitLocker — SECRETS already parks that outside Smoke.

---

## Finding 4 — Cli `apply` and `build` twin

**Tag:** `shrink:`  
**Where:** [`WinMint.Cli/Program.cs`](../../src/WinMint.Cli/Program.cs)

Both commands register the same options and call `RunApply`. Ticket 02 delivered both; comment says build is the “preferred product verb.”

**Replacement:** Keep `build`. Drop `apply`, or make `apply` an alias with zero duplicated option wiring (shared option group / single command factory).

**Cut weight:** ~40 lines of duplicated System.CommandLine setup.

---

## Finding 5 — Two sources of truth for SetupComplete

**Tag:** `yagni:` / `shrink:`  
**Where:** [`ImageServicing.cs`](../../src/WinMint.Orchestrator/ImageServicing.cs) (embedded here-string), [`payload/scripts/SetupComplete.cmd`](../../payload/scripts/SetupComplete.cmd)

Materialize writes a hard-coded `@echo off` + Supervisor invoke into `payload/SetupComplete.cmd`. The repo already has the same script under `payload/scripts/`. Drift risk is real (comments already disagree slightly on ticket numbering).

**Replacement:** Copy/stage the repo file into the work payload directory (same pattern as Supervisor publish copy).

---

## Finding 6 — Empty `Digests` on image evidence

**Tag:** `yagni:`  
**Where:** [`ImageServicing.Types.cs`](../../src/WinMint.Orchestrator/ImageServicing.Types.cs), [`PwshElevatedPlanRunner.cs`](../../src/WinMint.Orchestrator/PwshElevatedPlanRunner.cs)

`ImageEvidence` carries `IReadOnlyDictionary<string, string> Digests`. Runner accepts optional digests from evidence JSON and defaults to `{}`. Nothing in the Smoke path meaningfully fills this for product decisions.

**Replacement:** Drop until a harness or acceptance bar actually requires content hashes. Schema can grow then.

---

## Finding 7 — Stub jobs baked into every plan

**Tag:** `yagni:`  
**Where:** [`BuildPlan.cs`](../../src/WinMint.Orchestrator/BuildPlan.cs)

Every successful `Plan` emits `smoke.stub.ready` and `smoke.stub.complete`. Useful as a placeholder for ticket 06 job executor shape; dead weight until jobs run. Bundleloader maps job ids to `ProvisionJob(id, "stub")` that Machine setup never executes.

**Replacement:** Empty job list (or omit jobs artifact content) until the job runner ticket; keep stub jobs only in a fixture Profile if needed for S3 tests.

---

## Finding 8 — `DocumentErrors` wrapper

**Tag:** `shrink:`  
**Where:** [`DocumentErrors.cs`](../../src/WinMint.Orchestrator/DocumentErrors.cs) (3 lines of type)

`DocumentErrors` is a record holding `IReadOnlyList<DocumentError>`. Call sites always unwrap `.Issues`.

**Replacement:** `Result<Profile, IReadOnlyList<DocumentError>>` (or `List<>`). Keep `DocumentError` itself — the structured code/path is useful for Cli reporting.

---

## Finding 9 — Hand-rolled `Result<TOk, TErr>`

**Tag:** `shrink:` (optional)  
**Where:** [`Result.cs`](../../src/WinMint.Orchestrator/Result.cs)

Used consistently by BuildPlan / ImageServicing / Cli — matches the deep-module sketches in design docs. Not accidental. Cost is ~35 lines plus ceremonial `Result.Ok`/`Fail` at every return.

**Replacement:** Keep if typed plan/apply errors are a conscious house style. Otherwise `(TOk? ok, TErr? err)` or exceptions at the Cli edge are shorter. **Do not** introduce a NuGet Result library — that would be the opposite of ponytail.

---

## Finding 10 — Unused `TimeProvider`

**Tag:** `yagni:`  
**Where:** `SessionEnvironment.Time`

Correct seam for settle deadlines and fake clocks later. Machine setup only checks `CancellationToken` and never reads `env.Time`.

**Replacement:** Add with ticket 04/05 timeout behavior.

---

## What is *not* over-engineered

These match purpose and earn their complexity:

| Piece | Why it stays |
|-------|----------------|
| `IWinlogonRegistry` + `Win32WinlogonRegistry` | Real OS boundary; fake enables S3 without Hyper-V; encodes defaultuser0 / Shell fail-closed |
| Elevated `pwsh -File` kernels + `IElevatedPlanRunner` | Port shipped *with* test fake (ticket 02 rule); DISM must stay out of unelevated Cli |
| BuildPlan Profile parse + password-required plan failure | Trust boundary for Smoke account mode |
| Opcode stage list (not script paths in Profile) | Protects Architecture invariant: no Profile `if` in kernels |
| Workdir preserved on failure | Operability for long Apply runs |
| Single Supervisor binary as Shell | Core product bet vs v1 multi-pwsh + peer Splash |

Do not “simplify” those into in-process DISM from the wizard or guest PowerShell — that would fight [AGENTS.md](../../AGENTS.md) and DESIGN locks.

---

## Tension with locked design

[PROVISIONINGSESSION](../design/PROVISIONINGSESSION.md) **accepted** the full `Run(mode, bundle, env)` bag including empty-capable adapters. This audit does **not** reopen the grill. It records:

1. Locked interface ≠ must implement every field in ticket 03.
2. Implementing empty interfaces early creates stub noise and trains callers to pass noops forever.
3. SECRETS naming `ISecretScrubber` for “wipe in-memory buffers” invited a class that does something else (disk redact).

If design is treated as frozen C# surface, Findings 1–3 become “defer narrowing until a refactor ticket.” If code is allowed to lag the sketch, cut now and expand on 04+.

---

## Suggested cut order (if acted on later)

Do not apply from this document unless a ticket asks. Suggested sequence by payoff / risk:

1. **Inline secret redact; delete `FileSecretScrubber` + `ISecretScrubber`** — small, local, clarifies SECRETS vs disk hygiene.
2. **Narrow `SessionEnvironment` to Winlogon (+ wipe)** for Machine setup — delete Unsupported/Noop stubs.
3. **Stage `payload/scripts/SetupComplete.cmd` instead of embedding** — remove drift.
4. **Collapse Cli `apply` into `build`** — user-facing cleanup.
5. **Empty stub jobs / Digests** — when touching BuildPlan / evidence next.
6. **Defer Shell-tenure records** only if willing to amend types vs design sketch (higher process cost).

Estimated payoff if 1–5 land: **~−150–200 lines, 0 deps removed** (no NuGet fat today).

---

## Boundaries reminder

| In this audit | Not in this audit |
|---------------|-------------------|
| Unused flexibility, premature ports, duplicate verbs | Whether wipe-fail should fail Machine setup |
| Spec/code mismatch on “in-memory” vs disk scrub *as complexity* | Whether leaving DefaultPassword is a security issue (product-accepted for Smoke) |
| Empty interfaces before tickets | DMA settle correctness, splash timing, Hyper-V harness |

---

## Sources in-repo

- [CONTEXT.md](../../CONTEXT.md) — vocabulary / purpose  
- [AGENTS.md](../../AGENTS.md) — hold, deep modules, no guest pwsh  
- [docs/design/SECRETS.md](../design/SECRETS.md)  
- [docs/design/PROVISIONINGSESSION.md](../design/PROVISIONINGSESSION.md)  
- [docs/TICKETS.md](../TICKETS.md) — 01–03 done; 04+ Shell tenure  
- Implementation: `src/WinMint.Provisioning/*`, `src/WinMint.Orchestrator/*`, `src/WinMint.Cli/Program.cs`
