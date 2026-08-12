# Cross-process contracts

**Status:** Accepted  
**Authority:** BuildPlan → ImageServicing → staged payload → ProvisioningSession  
**Rule:** One versioned schema family; C# DTOs are source of truth; JSON on disk is interchange.  
**Lanes:** Public image-quality names **`Test` \| `Release`**. Guest durable files under `%ProgramData%\WinMint\`.

## Pipeline

```
Profile JSON
  → ProfileFile.TryLoad (host; materialize passwordPath)
  → BuildPlan.Plan
  → BuildArtifacts (in-memory)
       ├─ (optional) plan files for humans
       └─ ImageServicing.Apply
            → stages ISO: Supervisor.exe, SetupComplete.cmd, bundle JSON, jobs, DmaSettleTarget
                 → Machine setup / Shell: host loads ProvisioningBundle → ProvisioningSession.Run
```

`BuildPlan.TryParseProfile` remains the pure document parse (tests, Wizard compose round-trips). Hosts that load from disk use `ProfileFile` then `Plan`.

## Schema versions (strings)

| Artifact | Schema id |
|----------|-----------|
| Profile document | `winmint.profile/v1` |
| Job manifest (guest) | `winmint.jobs/v1` |
| Provisioning bundle (staged) | `winmint.provisioning.bundle/v1` |
| Evidence snapshot | `winmint.provisioning.evidence/v1` |
| Checkpoint | `winmint.provisioning.checkpoint/v1` |
| Smoke acceptance summary | `winmint.smoke.acceptance/v1` |
| Host Apply acceptance summary | `winmint.apply.acceptance/v1` |
| Servicing stages (workdir) | `winmint.servicing.stages/v1` |
| Image evidence | `winmint.image.evidence/v1` |
| Packages proof | `winmint.packages.proof/v1` |
| Packages check request (transient) | `winmint.packages.check.request/v1` |
| Packages check outcome (transient) | `winmint.packages.check.outcome/v1` |
| Native package audit | `winmint.native-packages/v1` |

The JSON key is `schemaVersion` and the C# constant is `SchemaVersion` — everywhere, no `schema` shorthand. Each id has **one** literal in C# (`JobsWire.SchemaVersion`, `GuestBundleWire.SchemaVersion`, …); a second spelling is a bug, not a style choice. PowerShell writers repeat the literal and are held honest by the C# reader that validates them.

Unknown schemaVersion ⇒ fail closed at parse (host or session loader).

## Ownership

| Artifact | Written by | Read by |
|----------|------------|---------|
| Profile | Human / Wizard | ProfileFile / BuildPlan; Smoke harness (guest creds only) |
| BuildArtifacts | BuildPlan | ImageServicing; Cli plan files |
| Servicing stages (`stages.json`) | ImageServicing Materialize | Elevated `Invoke-ServicingPlan.ps1`; Smoke harness (Debloat pin lists) |
| Staged guest bundle | ImageServicing StagePayload | ProvisioningSession host loader | Smoke: plaintext password until MachineSetup wipe — [SECRETS](SECRETS.md) |
| Evidence JSON | ProvisioningSession (projection) | Smoke harness (S4) — **never** session control |
| Checkpoint | ProvisioningSession (`ICheckpointStore`) | Next Shell `Run` via store (optional `bundle.Resume` inject) |
| Smoke acceptance summary | Host harness (`tools/vm/`) | Maintainer — `Assert-SmokeEvidence.ps1` |
| Host Apply acceptance summary | Host harness (`tools/apply/`) | Maintainer — `Assert-ApplyEvidence.ps1` |
| Image evidence (`evidence.json`) | Elevated `Invoke-ServicingPlan.ps1` | ImageServicing; host apply assert — **never** session control |
| Image failure (`failure.json`) | Elevated `Invoke-ServicingPlan.ps1` | ImageServicing runner; removed on successful Apply |
| Packages proof (`config/packages.proof.json`) | PackagesProof (C#) | PackagesProof.Validate; `just check` |
| Packages check request (transient) | PackagesProof (C#) | `Invoke-PackagesCheck.ps1` |
| Packages check outcome (transient) | `Invoke-PackagesCheck.ps1` | PackagesProof (C#) |

Transient packages-check files live under `.scratch/packages-check/{run}/` during `packages-check` only; C# owns request write, reconciliation, and proof replace — not durable interchange.

## Compatibility

- Additive optional fields OK within `v1` if readers ignore unknowns.
- Breaking change ⇒ bump version id; no silent dual-read of v1 BuildProfile.
- Guest must not require a newer host than the ISO that staged it (bundle embedded in image).

## Shared types (logical)

- Settle: locale, GeoId, timeZoneId, location posture. Host Profile settle is required; staged bundle settle may be nullable — map explicitly at the stage boundary (twin records OK; drift ⇒ consolidate).
- Jobs: `ProvisionJob` (domain) and `JobsFile` / `JobFile` (wire) live once in `WinMint.Contracts` (`JobsWire`), with `JobsWire.SchemaVersion` the only `winmint.jobs/v1` literal. BuildPlan projects via `ProvisionJob.ToWire()`; `BundleLoader` maps back. A new job field is one edit there plus the two mappers.
- `ServicingOpcode` and provisioning **job `Kind`** are closed sets (`ServicingOpcode` / `ProvisionJobKind`) with the same touch-point discipline. Wire JSON may use strings; parse once at the load boundary (`BundleLoader` → enum). Unknown kind ⇒ `Result` failure (`jobs.kind.unknown`).
- `ProvisioningBundle.SupervisorShellPath` (`supervisorPath`) must match offline Shell stamp and Machine setup verify.

## Interchange type naming

| Suffix | Use |
|--------|-----|
| `*Document` | Authored / parse input — a human or the Wizard wrote it |
| `*File` | Anything WinMint itself writes or reads as interchange, **including nested members** (`JobsFile` → `JobFile`) |

Two suffixes, no others: `*Dump` and `*Dto` are gone and must not come back. Emitted evidence is a `*File`, not a `*Document` — nobody authored it. A serializer is named for the type it returns (`SerializeJobsFile` → `JobsFile`).

## Status codes & evidence phases

Dotted `area.token`, **every segment camelCase** — `settle.deviceRegionOk`, not `settle.device_region_ok`. Underscores are out; a multi-word segment runs the words together (`machineSetup.secretWipeFailed`). Evidence `Phases` use the **same** strings (no parallel vocabulary). Areas: `machineSetup`, `shell`, `settle`, `jobs`, `checkpoint`, `session`, `servicing`, plus BuildPlan `account` / `document` / `dma` / `debloat`.

`StatusCodeVocabularyTests` scans the emitted codes and fails on a stray dialect — the rule is enforced, not just written down.

Cli product verb for ImageServicing is `build` only.

## Explicit non-contracts

- `setup-shell-control.json` / `setup-shell-status.json` as control plane (v1) — **forbidden**.
- Reading evidence JSON to decide next phase — **forbidden**.
