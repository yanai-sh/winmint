# Cross-process contracts

**Status:** Accepted (batch-grill 2026-07-28)  
**Authority:** BuildPlan → ImageServicing → staged payload → ProvisioningSession  
**Rule:** One versioned schema family; C# DTOs are source of truth; JSON on disk is interchange.  
**Grill:** Public image-quality names **`Test` \| `Release`**. Guest durable files under `%ProgramData%\WinMint\`.

## Pipeline

```
Profile JSON
  → BuildPlan.TryParseProfile / Plan
  → BuildArtifacts (in-memory)
       ├─ (optional) plan dump for humans
       └─ ImageServicing.Apply
            → stages ISO: Supervisor.exe, SetupComplete.cmd, bundle JSON, jobs, DmaSettleTarget
                 → Machine setup / Shell: host loads ProvisioningBundle → ProvisioningSession.Run
```

## Schema versions (strings)

| Artifact | Schema id |
|----------|-----------|
| Profile document | `winmint.profile/v1` |
| Job manifest (guest) | `winmint.jobs/v1` |
| Provisioning bundle (staged) | `winmint.provisioning.bundle/v1` |
| Evidence snapshot | `winmint.provisioning.evidence/v1` |
| Checkpoint | `winmint.provisioning.checkpoint/v1` |
| Servicing stages (workdir) | `winmint.servicing.stages/v1` |
| Image evidence | `winmint.image.evidence/v1` |

Unknown schemaVersion ⇒ fail closed at parse (host or session loader).

## Ownership

| Artifact | Written by | Read by |
|----------|------------|---------|
| Profile | Human / Wizard | BuildPlan |
| BuildArtifacts | BuildPlan | ImageServicing; Cli dump |
| Staged guest bundle | ImageServicing StagePayload | ProvisioningSession host loader |
| Evidence JSON | ProvisioningSession (projection) | Smoke harness (S4) — **never** session control |
| Checkpoint | ProvisioningSession | Next Shell `Run` via bundle.Resume |

## Compatibility

- Additive optional fields OK within `v1` if readers ignore unknowns.
- Breaking change ⇒ bump version id; no silent dual-read of v1 BuildProfile.
- Guest must not require a newer host than the ISO that staged it (bundle embedded in image).

## Shared types (logical)

- `DmaSettleTarget` / `DmaContract` settle side: locale, GeoId, timeZoneId, location posture.
- `ServicingOpcode` enum owned with BuildPlan stages + ImageServicing catalog (three touch points on add — acceptable).
- `SupervisorIdentity.ExePath` must match offline Shell stamp and Machine setup verify.

## Explicit non-contracts

- `setup-shell-control.json` / `setup-shell-status.json` as control plane (v1) — **forbidden**.
- Reading evidence JSON to decide next phase — **forbidden**.
