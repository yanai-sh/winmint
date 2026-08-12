# TDD plan — WinMint

**Authority:** [DESIGN](DESIGN.md), module designs, TDD skill.  
**Rule:** Assert through module interfaces (BuildPlan / ImageServicing / ProvisioningSession / harness). Prefer existing seams below; **new coverage through those interfaces does not need a pre-registered seam id.**

## Speed rules

| | Rule |
|---|------|
| **Should** | Day-to-day = S1–S3 (`just check` + fakes); Smoke = `Test` lane + stub jobs; provisioning jobs share S3 executor; CI = scaffold only (no VM / no ISO); S4 fail-fast on stalls |
| **Could** | Diff VHD / digest-gated rebuild — harness-only |
| **Don’t** | Skip S4 hard evidence; invent a Hyper-V-only settle/executor path “for speed” |

## Seams (usual homes)

| Seam | Module interface | Dependency |
|------|------------------|------------|
| **S1** | BuildPlan (`TryParseProfile`, `SerializeProfile`, `Plan`) | In-process |
| **S1b** | Host DebloatPresets + Wizard packages → Profile → Plan/Serialize | In-process |
| **S1c** | `ProfileFile.TryLoad` | Local temp dirs |
| **S1d** | HostCompile (`PlanDocument`, `ComposeAsync`, `ComposeFileAsync`, `ApplyAsync`) + WizardSession command sequences | Source-media probe / elevated-runner fakes |
| **S2** | ImageServicing (`Apply`) | DISM (fake when port exists) |
| **S3** | ProvisioningSession (`Run` + env adapters) | Local-substitutable OS |
| **S4** | Hyper-V Smoke acceptance | Harness + VM |
| **S5** | Host Apply acceptance (pre-wipe) | Harness on build host |

Do **not** test: private phase helpers, splash pixels (except status→presenter via `ISplashPresenter`), DISM internals, v1 scripts, evidence JSON as control plane.

**S4 vs S5:** S4 = FirstLogon in Hyper-V. S5 = Apply on the build host — never a bare-metal install. Do not substitute one for the other.

## Good test criteria

- Assert **observable outcomes** through the module interface.
- Expected values from **spec literals** (Ireland GeoID `68`, password required, opcodes, lane names).
- Survive internal refactors; mock **adapters**, not private collaborators.
- Vertical slices: one failing test → minimal code → next.

## Per-seam strategy

### S1 — BuildPlan

Bad JSON → document errors. No password + Local+autoLogon → Plan failure. DMA on → Ireland `DeviceRegion` latch + settle targets. Default Plan → Test lane + opcodes (not .ps1 paths); `smoke.stub.*` only when `IncludeSmokeStubs`. Release lane → different `ExportWim` params. `passwordPath` purity → path-only parse never reads; conflict fails; serialize omits inline password when path set.

### S1c — ProfileFile

Real temporary directories only. Assert absolute + Profile-relative resolution, ambient drive/root-relative fail closed, missing files, CR/LF strip, empty → Plan `account.password.required`.

### S1d — Host composition / Living Draft

Assert immutable review and private approved-plan behavior through HostCompile and WizardSession. Drive Wizard navigation gates through `WizardShellViewModel`, and stage behavior through the Source, Account, Software, and Review binding interfaces—not private formatting helpers. A fake `ISourceMediaProbe` supplies Source ISO hash and selected-WIM metadata; observe materialized servicing facts through `IElevatedPlanRunner`. Cover source changes before elevation, deterministic output naming, structured document errors, relative-`passwordPath` Save relocation, dirty invalidation, out-of-order async result rejection, retry after Apply failure, and exact-handle success acknowledgement. Do not add an `IImageServicing` port.

### S2 — ImageServicing

Prefer fake elevated runner when introduced. Assert stage order, Shell stamp path, lane params — not ISO bytes. Kernels: no Profile branching. Never commit multi-edition WIM ([IMAGESERVICING](design/IMAGESERVICING.md#invariants)).

### S3 — ProvisioningSession

See [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md). Use `ShellEnvironment` / `MachineSetupEnvironment` fakes + `TimeProvider`. Assert paint-before-settle **order**; wall-clock paint budget is S4.

### S4 — Hyper-V acceptance

One harness entry → guest evidence (`tools/vm/`). Splash before Explorer; DMA hard fields; unlock; lane marker; time-to-first-paint. Acceptance pinned remove-list digests. Not part of `just check`.

### S5 — Host Apply acceptance (pre-wipe)

One harness entry → Apply workdir evidence (`tools/apply/`). Assert `evidence.json` lane + digests; driver inventory when Profile has `drivers`. `[Trait("Category", "S5")]` excluded from `just check`. Destructive bare-metal install is **manual only** after S5 green.

## Gate commands

```powershell
just check          # S1–S3 (excludes Category=S4 and Category=S5)
# maintainer:
just host-apply ISO=…
just host-apply-assert WORK=…
just smoke          # S4 Hyper-V
```

## Anti-patterns

- Private-method tests / InternalsVisibleTo past `Run`.
- File mailbox control-plane assertions.
- Whole-unattend snapshots without Ireland/autologon targets.
- Horizontal “write all tests then code.”
- MediatR / Generic Host / AutoMapper for testability theater (xUnit + fakes stay fine; better asserts OK when they pay rent).
