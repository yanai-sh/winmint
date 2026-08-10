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
       ├─ (optional) plan dump for humans
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
| Servicing stages (workdir) | `winmint.servicing.stages/v1` |
| Image evidence | `winmint.image.evidence/v1` |

Unknown schemaVersion ⇒ fail closed at parse (host or session loader).

## Ownership

| Artifact | Written by | Read by |
|----------|------------|---------|
| Profile | Human / Wizard | ProfileFile / BuildPlan; Smoke harness (guest creds only) |
| BuildArtifacts | BuildPlan | ImageServicing; Cli dump |
| Servicing stages (`stages.json`) | ImageServicing Materialize | Elevated `RunPlan.ps1`; Smoke harness (Debloat pin lists) |
| Staged guest bundle | ImageServicing StagePayload | ProvisioningSession host loader | Smoke: plaintext password until MachineSetup wipe — [SECRETS](SECRETS.md) |
| Evidence JSON | ProvisioningSession (projection) | Smoke harness (S4) — **never** session control |
| Checkpoint | ProvisioningSession (`ICheckpointStore`) | Next Shell `Run` via store (optional `bundle.Resume` inject) |
| Smoke acceptance summary | Host harness (`tools/vm/`) | Maintainer — `Assert-SmokeEvidence.ps1` |

## Compatibility

- Additive optional fields OK within `v1` if readers ignore unknowns.
- Breaking change ⇒ bump version id; no silent dual-read of v1 BuildProfile.
- Guest must not require a newer host than the ISO that staged it (bundle embedded in image).

## Shared types (logical)

- Settle: locale, GeoId, timeZoneId, location posture. Host Profile settle is required; staged bundle settle may be nullable — map explicitly at the stage boundary (twin records OK; drift ⇒ consolidate).
- `ServicingOpcode` and provisioning **job `Kind`** are closed sets (enum or equivalent) with the same touch-point discipline as opcodes. Wire JSON may use strings; parse once at the load boundary.
- `ProvisioningBundle.SupervisorShellPath` (`supervisorPath`) must match offline Shell stamp and Machine setup verify.

## Interchange DTO naming

| Suffix | Use |
|--------|-----|
| `*Document` | Authored / parse input |
| `*File` | Workdir or guest interchange on disk |

Prefer `*File` over new `*Dump` / `*Dto` when touching those types.

## Status codes & evidence phases

Lowercase dotted `area.token`. Evidence `Phases` use the **same** strings (no parallel vocabulary). Areas: `machineSetup`, `shell`, `settle`, `jobs`, `checkpoint`, `session`, `servicing`, plus BuildPlan `account` / `document` / `dma` / `debloat`.

Cli product verb for ImageServicing is `build` only.

## Explicit non-contracts

- `setup-shell-control.json` / `setup-shell-status.json` as control plane (v1) — **forbidden**.
- Reading evidence JSON to decide next phase — **forbidden**.
