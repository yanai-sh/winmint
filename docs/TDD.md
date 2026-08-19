# TDD plan — WinMint

**Authority:** [DESIGN](DESIGN.md), module designs, TDD skill.  
**Rule:** Assert through module interfaces (BuildPlan / ImageServicing / ProvisioningSession / harness). Prefer existing seams below; **new coverage through those interfaces does not need a pre-registered seam id.**

## Speed rules

| | Rule |
|---|------|
| **Should** | Day-to-day = S1–S3 (`just check` + fakes); Smoke = `Test` lane + stub jobs; provisioning jobs share S3 executor; CI = `just check` plus AOT publish (no VM / no ISO); S4 fail-fast on stalls |
| **Could** | Diff VHD / digest-gated rebuild — harness-only |
| **Don’t** | Skip S4 hard evidence; invent a Hyper-V-only settle/executor path “for speed”; inject Hyper-V cmdlet adapters to unit-test Prefer-DiskBoot |

## Seams (usual homes)

| Seam | Module interface | Dependency |
|------|------------------|------------|
| **S1** | BuildPlan (`TryParseProfile`, `SerializeProfile`, `Plan`) | In-process |
| **S1b** | Host DebloatPresets + Wizard packages → Profile → Plan/Serialize | In-process |
| **S1c** | `ProfileFile.TryLoad` | Local temp dirs |
| **S1d** | HostCompile (`PlanDocument`, `ComposeAsync`, `ComposeFileAsync`, `ApplyAsync`) + WizardSession — Orchestrator entry, not a fourth product module ([DESIGN](DESIGN.md)) | Source-media probe / elevated-runner fakes |
| **S2** | ImageServicing (`Apply`) | DISM (fake when port exists) |
| **S3** | ProvisioningSession (`Run` + env adapters) | Local-substitutable OS |
| **S4** | Hyper-V Smoke acceptance | Harness + VM |
| **S5** | Host Apply acceptance (pre-wipe) | Harness on build host |

Do **not** test: private phase helpers, splash pixels (except status→presenter via `ISplashPresenter`), DISM internals, v1 scripts, evidence JSON as control plane.

**Contract (`tests/contract/`):** prove a script whose runtime host cannot exist on a dev box (WinPE, DISM transcript parse, GitHub-release helpers) or a policy sentence that must not disappear. `just check` discovers `Test-*.ps1`. Not for in-process C# module tests, S4/S5, or the deleted `--reuse-media` / marker four-way branch.

WinPE apply **host** (`WinMintApply` `Run`, cmd quoting) is in-process / `just check` — see `WinPeApplyHostTests`. Helper identity vs the work payload is `Get-WinPeApplyDefect` / `Test-DiskGuard`, not a marker bump. Smoke disk-boot / DVD / RAM policy is `Get-SmokePreferDiskBootDecision` / `Get-SmokeEjectDvdDecision` / `Get-SmokeVmStartupBytes` (VHD `FileSize` + Heartbeat). Four-line `Get-SmokePreferDiskBootDecision` / `Get-SmokeEjectDvdDecision` stay; they are not a second adapter. A fake `Set-VMFirmware` is a hypothetical seam (one adapter) and is forbidden. Contract greps stay for hosts that literally cannot run here (diskpart-in-WinPE, DISM transcripts, wait-loop firmware sequencing).

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

HostCompile is the Orchestrator entry ([DESIGN](DESIGN.md)). Assert immutable review and private approved-plan behavior through HostCompile and WizardSession. Drive Wizard navigation gates through `WizardViewModel`, and stage behavior through the Source, Account, Software, and Review binding interfaces—not private formatting helpers. A fake `ISourceMediaProbe` lists WIM indexes without hashing and supplies Source ISO identity plus selected-WIM metadata at Compose; observe materialized servicing facts through `IElevatedPlanRunner`. Cover source changes before elevation, deterministic output naming, structured document errors, relative-`passwordPath` Save relocation, dirty invalidation, out-of-order async result rejection, retry after Apply failure, and exact-handle success acknowledgement. Do not add an `IImageServicing` port.

### S2 — ImageServicing

Prefer fake elevated runner when introduced. Assert stage order, Shell stamp path, lane params — not ISO bytes. Kernels: no Profile branching. Never commit multi-edition WIM ([IMAGESERVICING](design/IMAGESERVICING.md#invariants)).
Catalog quality identity is one rule in `Test-QualityCatalog.ps1`: dialog URL, cache hit, cache write, and expand all refuse a leaf that is not the requested KB. Poisoned quality-cache is a miss plus quarantine off the hit path — not first-file. Do not invent `IQualityDownload` until a second adapter exists.
Freshness tests go through `CheckPublishedBinaryFreshness`; store-MSIX tests go through `RefuseStoreMsixPwsh`.
Do not call `ExecuteAsync` from `just check` because it crosses the UAC/process boundary.

### S3 — ProvisioningSession

See [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md). Use `ShellEnvironment` / `MachineSetupEnvironment` fakes + `TimeProvider`. Assert paint-before-settle **order**; wall-clock paint budget is S4.

### S4 — Hyper-V acceptance

One harness entry → guest evidence (`tools/vm/`). Splash before Explorer; DMA hard fields; unlock; lane marker; time-to-first-paint. Acceptance pinned remove-list digests. Not part of `just check`. External watch uses `Get-SmokeWatchVerdict` (phase, `Get-VHD` FileSize, status age) — not process lists or `vmconnect`. Invoke-Smoke throws from `Get-SmokeWatchVerdict`, not a second empty-VHD `if`. `waiterPid` is an optional `Wait-Process` handle, not a fail/kill signal; watchers must not infer death from PIDs or `Remove-VM`. After `just apply-maintainer`, the waiter must project `apply-status.txt` `stage=failed:` into `smoke-status.json` `phase=failed` even when `LASTEXITCODE` is 0. Stall/empty-VHD elapsed is Stopwatch. Disk-boot tests drive those policy functions, not a Hyper-V executor. Do not "complete" that by faking Hyper-V.

### S5 — Host Apply acceptance (pre-wipe)

One harness entry → Apply workdir evidence (`tools/apply/`). Assert `evidence.json` lane + digests; driver inventory when Profile has `drivers`. `[Trait("Category", "S5")]` excluded from `just check`. Destructive bare-metal install is **manual only** after S5 green.

## Gate commands

```powershell
just check          # S1–S3 (excludes Category=S4 and Category=S5) + contract tests; CI mirrors this plus AOT publish
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
- Calling `PwshElevatedPlanRunner.ExecuteAsync` from `just check`.
- MediatR / Generic Host / AutoMapper for testability theater (xUnit + fakes stay fine; better asserts OK when they pay rent).
