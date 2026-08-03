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
| Staged guest bundle | ImageServicing StagePayload | ProvisioningSession host loader | Smoke: plaintext password until MachineSetup wipe — [PROVISIONINGSESSION Secrets](PROVISIONINGSESSION.md#secrets-smoke) |
| Evidence JSON | ProvisioningSession (projection) | Smoke harness (S4) — **never** session control |
| Checkpoint | ProvisioningSession | Next Shell `Run` via bundle.Resume |

## Compatibility

- Additive optional fields OK within `v1` if readers ignore unknowns.
- Breaking change ⇒ bump version id; no silent dual-read of v1 BuildProfile.
- Guest must not require a newer host than the ISO that staged it (bundle embedded in image).

## Shared types (logical)

- `DmaSettleTarget` / `DmaContract` settle side: locale, GeoId, timeZoneId, location posture.
- Orchestrator `DmaSettleTarget` (required settle fields on Profile) and Provisioning `DmaSettleTarget` (nullable settle on staged bundle) are **intentional** cross-process shapes — do not merge via a shared Contracts project.
- `ServicingOpcode` enum owned with BuildPlan stages + ImageServicing catalog (three touch points on add — acceptable).
- `SupervisorIdentity.ShellPath` (bundle JSON `supervisorPath`) must match offline Shell stamp and Machine setup verify.

## Interchange DTO naming

| Suffix | Use |
|--------|-----|
| `*Document` | Authored / parse input (e.g. Profile JSON DTOs, `ProvisioningEvidenceDocument`) |
| `*File` | Workdir or guest interchange on disk (e.g. `JobsFile`, `BundleFile`, evidence on disk) |

Do not introduce new `*Dump` / `*Dto` names. Existing Cli `*Dump` / BundleLoader `*Dto` stay until those files are touched.

## Status codes & evidence phases

Form: lowercase dotted `area.token` segments (product area first).

| Area | Examples |
|------|----------|
| `machineSetup` | `machineSetup.ok`, `machineSetup.account.forbidden`, `machineSetup.shell.verify_failed` |
| `shell` | `shell.first_paint`, `shell.evidence.required`, `shell.timeout`, `shell.stale`, `shell.cancelled` |
| `settle` | `settle.begin`, `settle.ok`, `settle.skipped`, `settle.hard_mismatch`, `settle.location_warn`, `settle.apply_failed`, `settle.read_failed`, `settle.target_incomplete`, `settle.cancelled` |
| `jobs` | `jobs.begin`, `jobs.ok`, `jobs.failed`, `jobs.spawn_failed`, `jobs.kind.unsupported` |
| `appearance` | `appearance.applied` |
| `session` | `session.mode.unknown` |
| `servicing` | `servicing.runPlan.failed`, `servicing.sourceIso.missing` |
| `account` / `document` / `dma` | BuildPlan validation (`account.mode.missing`, `document.schemaVersion.unsupported`) |

**Evidence `Phases`:** use the **same** strings as the status codes they record (e.g. `shell.first_paint`, `settle.begin`) — not a parallel short vocabulary.

Prose stays “Machine setup”; types/flags stay `MachineSetup` / `--machine-setup`. Status codes are the third surface and follow this table only.

Cli `build` and `apply` are both product verbs (same path) — intentional, not duplication to delete.

## Explicit non-contracts

- `setup-shell-control.json` / `setup-shell-status.json` as control plane (v1) — **forbidden**.
- Reading evidence JSON to decide next phase — **forbidden**.
