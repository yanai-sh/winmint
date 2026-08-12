# Design: Host composition for Wizard Living Draft

**Date:** 2026-08-12  
**Status:** Approved for planning  
**Issue:** [#94 — WizardSession Living Draft](https://github.com/yanai-sh/winmint/issues/94)  
**Unlocks:** [#110 — Split WizardViewModel by stage](https://github.com/yanai-sh/winmint/issues/110)

## Problem

The Wizard currently has a second planning brain:

1. `WizardSession.ComposeAndPlan` creates a `Profile` and calls `BuildPlan.Plan`.
2. `WizardViewModel` parses the canonical Profile bytes it just received.
3. Build saves those bytes to disk.
4. `HostCompile.ApplyAsync` loads the file and calls `BuildPlan.Plan` again.

The reviewed plan is therefore not guaranteed to be the applied plan. The two calls already differ in how they supply image architecture. Disk persistence also acts as an accidental control plane between Review and Apply.

`CONTEXT.md` defines HostCompile as the Orchestrator entry and both Cli and Wizard as thin adapters. The design must restore that ownership without introducing a second Profile schema.

## Prerequisite

Implementation starts after [#104](https://github.com/yanai-sh/winmint/issues/104) lands. That ticket owns the final package-strictness and lane types used by HostCompile and BuildArtifacts. This design must not encode the current transitional spelling.

## Decision

Use `Profile` as the neutral typed authoring intent. Do not add a parallel `ProfileIntent`.

HostCompile owns source-media inspection, canonical Profile serialization, default resolution, and the only call to `BuildPlan.Plan`. A successful composition freezes everything the user approves before elevation:

- canonical authored Profile bytes;
- a private immutable snapshot of the approved plan;
- Source ISO path and SHA-256;
- selected WIM index, architecture, build, edition, and name;
- lane, package policy, and other BuildPlan options;
- work directory and media-reuse policy;
- Profile naming stem;
- explicit or resolved Output ISO path.

```csharp
public static Task<Result<HostComposition, HostComposeError>> ComposeAsync(
    Profile profile,
    HostComposeOptions options,
    ISourceMediaProbe? sourceMedia = null,
    TimeProvider? time = null,
    CancellationToken cancellationToken = default);

public static Task<Result<HostComposition, HostComposeError>> ComposeFileAsync(
    string profilePath,
    HostComposeOptions options,
    ISourceMediaProbe? sourceMedia = null,
    TimeProvider? time = null,
    CancellationToken cancellationToken = default);

public static Task<Result<ImageEvidence, Failure>> ApplyAsync(
    HostComposition composition,
    IElevatedPlanRunner? runner = null,
    CancellationToken cancellationToken = default);

public static Result<HostPlan, HostComposeError> PlanDocument(
    Profile profile,
    RunOptions? run = null);

public static Result<Unit, Failure> ExportPlan(
    HostPlan plan,
    string destinationDirectory);
```

`HostComposeOptions` carries all authoring-independent build choices, including Source ISO, selected WIM index, work directory, media reuse, image-quality lane, package overrides, architecture/build expectations, and optional Output ISO override. HostCompile normalizes those values once.

`HostComposition` exposes:

- `HostReview Review` — immutable authored and effective facts required by front ends;
- `byte[] GetProfileUtf8()` — a defensive copy;
- resolved output/work/source facts required for progress and guidance.

The approved `BuildArtifacts` instance remains private to HostCompile. `ApplyAsync` has no semantic or execution override object; it materializes and applies only the frozen composition. `HostPlan` is the non-build document-planning result for Cli `validate` and `plan`; it has an immutable Review and a HostCompile-owned artifact export operation, but no Apply capability.

`ISourceMediaProbe` replaces the Wizard-local WIM probe seam. Production and test adapters already justify the seam. It computes the Source ISO SHA-256 and selected-image metadata before composition succeeds.

## Ownership

### WizardSession module

WizardSession remains stateful, but it is not a planning module. It owns the Living Draft lifecycle required by issue #94:

- current authored/run revision;
- asynchronous source-media probe state;
- one approved `HostComposition`;
- Save acknowledgement;
- Apply eligibility.

Its minimal interface is:

```csharp
SessionView View { get; }
long UpdateDraft(Profile profile, HostComposeOptions options);
Task<Result<SourceMediaReview, Failure>> SettleProbeAsync(
    CancellationToken cancellationToken = default);
Task<Result<HostReview, Failure>> PlanAsync(
    CancellationToken cancellationToken = default);
Result<Unit, Failure> Save(string destinationPath);
Result<HostComposition, Failure> TryGetApplyComposition();
Result<Unit, Failure> AcknowledgeApplySuccess(
    HostComposition appliedComposition);
```

`PlanAsync` delegates to HostCompile. WizardSession never calls BuildPlan directly and never exposes a second Plan implementation.

`UpdateDraft` compares the complete typed Profile and compose options with the current draft. A change increments one monotonically increasing revision and clears the approved composition. This covers Profile fields, chips, advanced text, preset, lane, Source ISO, selected WIM, architecture/build expectations, package overrides, work/output choices, and reuse policy. Re-supplying an equal draft is a no-op.

Probe and compose operations capture the starting revision. Their result is discarded if the revision changed while awaiting. A probe result is also tagged with Source ISO identity so a late result for an older path cannot replace the current selection.

`Save` first validates destination and relative-`passwordPath` relocation, then atomically writes the current composition bytes and records the saved path only after replacement succeeds. It never writes and then asks the session to acknowledge. `TryGetApplyComposition` returns the current composition handle only when the approved revision still matches.

After HostCompile returns successful Apply evidence, the caller passes the applied handle to `AcknowledgeApplySuccess`. The session clears approval only when that handle is its current approved composition at the current revision; a stale handle returns `Failure`. Apply failure is not acknowledged and preserves approval for inspection or retry.

### Wizard adapter

Avalonia owns UI vocabulary and coercion:

- raw string parsing and field-local errors;
- selected chips and advanced-text precedence;
- preset choice and expansion to explicit authored lists;
- storage picker and presentation;
- build-recipe display.

It constructs a typed `Profile` and mutation commands for WizardSession. It does not serialize, parse, apply product posture, plan, or retain parallel `_last*` approval fields.

### HostCompile module

HostCompile owns:

- Source ISO hashing and WIM metadata inspection;
- canonical Profile serialization;
- normalization of source, image, work, output, lane, and package facts;
- the single BuildPlan invocation;
- the private approved plan snapshot;
- file-based composition for Cli;
- validation immediately before Apply;
- passing the approved snapshot to ImageServicing.

### BuildPlan module

BuildPlan remains pure and owns product posture, effective package facts and ordering, lane-derived export facts, and plan validation.

## Immutability

Reference identity is insufficient because current artifacts contain mutable arrays and collection implementations.

At composition:

- input Profile lists and run collections are copied;
- canonical bytes are privately owned;
- the approved plan is deep-snapshotted;
- byte arrays are copied;
- stage parameter dictionaries and all lists use immutable or frozen standard-library collections;
- front ends receive only immutable `HostReview` projections, never the private plan.

Composition contains managed plaintext needed to create unattend. It is session-scoped: WizardSession drops its reference on invalidation, close, and successful Apply completion. No design claims reliable managed-string zeroization. Profile, password, unattend, and canonical bytes must never enter logs, telemetry, evidence, or caches.

## Data flow

```text
UI mutation
  → WizardSession revision increments; old approval cleared
  → Wizard coercion / chip and preset expansion
  → Profile + HostComposeOptions
  → HostCompile.ComposeAsync
  → HostComposition(private Plan, immutable Review)
       ├─ Review reads HostReview
       ├─ Save exports canonical Profile bytes
       └─ Build passes the composition handle to ApplyAsync
```

Cli `validate` and `plan` do not require Source ISO or workspace choices. They load once, call `HostCompile.PlanDocument`, and inspect or export the returned `HostPlan`. Cli `build` uses `ComposeFileAsync` and immediately applies that composition. No Cli or Wizard path calls BuildPlan directly, and Cli never receives mutable BuildArtifacts.

## Source media and Apply

Composition freezes Source ISO SHA-256 and selected-image metadata. Apply rechecks the SHA-256 before elevation and fails if the file changed.

Before mutation, ImageServicing validates that staged media matches the composition's selected image metadata. `ReuseMedia=false` removes any old media and creates fresh media from the approved Source ISO.

`ReuseMedia=true` uses a minimal marker beside staged media:

```json
{
  "schemaVersion": "winmint.media-identity/v1",
  "sourceIsoSha256": "...",
  "wimIndex": 1,
  "imageName": "...",
  "architecture": "arm64",
  "build": "..."
}
```

Reuse requires an exact marker match and a probe of staged `sources/install.wim` confirming the selected-image metadata. A missing, malformed, or mismatched marker takes the cold path, recreates media, validates it, and atomically writes the marker. A Source ISO hash change after composition still fails Apply rather than silently recomposing. [#111](https://github.com/yanai-sh/winmint/issues/111) may replace this conservative marker after native ARM64 benchmarking, but #94's behavior is complete without that spike.

Supervisor freshness and path preparation are checked immediately before Apply. Apply does not recompute defaults or replace approved source, WIM, lane, architecture, output, or package facts.

## Output ISO resolution

HostCompile freezes the Profile naming stem and resolves the Output ISO path during composition:

- an explicit output override is normalized and frozen;
- otherwise `OutputIsoNaming` uses the frozen work directory, Profile stem, lane, and injected `TimeProvider`;
- Review displays that exact path;
- ImageServicing validates and uses it without renaming.

There is no apply-time `ProfilePathHint`.

## Persistence and `passwordPath`

Saving is an export, not the Apply control plane. Apply does not require Save or reread an exported file. Editing or deleting it cannot change the approved build.

Wizard-authored inline passwords save normally. For a file-loaded Profile with a relative `passwordPath`:

- HostCompile records the source Profile directory;
- overwrite in the same directory preserves the relative path;
- Save As to another directory is rejected until the user selects a new password source or explicitly converts the path to an absolute path;
- canonical bytes continue to omit the materialized password.

Tests do not claim that canonical bytes alone round-trip a materialized secret. They verify authored document equivalence and separately verify one-time secret materialization for planning.

## Errors

```csharp
public sealed record HostComposeError(
    string Code,
    string Message,
    IReadOnlyList<DocumentError>? Documents = null);
```

- Wizard coercion failures remain field-local `Failure` values such as `dma.settle.geoId`.
- `ComposeFileAsync` preserves structured `DocumentError` code, message, and path in `Documents`.
- Source hashing/probe and semantic/planning failures produce no composition.
- Apply failures are environmental, elevation, or servicing `Failure` values.
- Expected invalid input returns `Result`; exceptions indicate bugs.

## Review projections

`HostReview` contains immutable authored and effective facts required by Review and recipe/guidance copy. It must not expose secrets or mutable artifact objects.

Review must not parse canonical bytes, re-expand presets, reapply product posture, parse generated package JSON, or infer package strictness/lane behavior independently. UI wording remains Wizard-owned.

## Verification

Tests use HostCompile and WizardSession interfaces:

1. Composition freezes Source ISO hash, WIM index/metadata, architecture/build, work/output paths, reuse policy, and #104 lane/package facts.
2. Staged artifacts observed through the existing elevated-runner fake equal the composition's immutable Review facts; no new `IImageServicing` port is added.
3. Apply performs no Profile parse or BuildPlan invocation.
4. Source ISO changes after composition fail before elevation.
5. `ReuseMedia=false` cannot consume a pre-existing WIM; reused media must match frozen source/image identity.
6. Changing or deleting an exported Profile cannot alter Apply.
7. Output path and naming stem shown in Review equal ImageServicing input.
8. Mutable input collections and returned byte arrays cannot alter the private approval snapshot.
9. File composition preserves structured `DocumentError` values.
10. Relative `passwordPath` overwrite is stable; relocation is rejected; secret materialization happens once.
11. Equivalent Cli and Wizard inputs produce equivalent Review and staged artifacts.
12. Profile/chip/run edits invalidate approval.
13. Late probe and compose results for older revisions are discarded.
14. Apply failure leaves the current approval available for inspection and retry unless source identity changed.

## Deletions

Implementation deletes or collapses:

- static `WizardSession.ComposeAndPlan`, `WizardSessionInput`, and `WizardSessionResult`;
- WizardViewModel `_lastProfileUtf8`, `_lastProfile`, `_lastArtifacts`, `_lastRequiresNetwork`, and byte reparse;
- the save → reload → replan Build path;
- direct BuildPlan calls in Cli and Wizard;
- old file-reloading `HostCompileRequest`/nested `HostCompileResult` flow;
- profile-path-based `WizardBuildInput` and duplicate preflight/error remapping;
- Cli `TryLoadArtifacts`;
- duplicated Review fallbacks that derive effective posture without approval.

`FormatBuildRecipe` is deleted from WizardSession as issue #94 requires. Recipe formatting moves to a projection over frozen composition facts until #110 assigns it to the Review stage.

## Rejected alternatives

### Separate `ProfileIntent`

Rejected because it mirrors Profile and creates a second schema.

### Planning inside WizardSession

Rejected. WizardSession owns revisions and approval lifetime but delegates composition to HostCompile.

### Saved file as Apply authority

Rejected because it permits Review and Apply to diverge.

### Public mutable BuildArtifacts

Rejected because a shared reference does not make an approval immutable.

## Scope

This ticket implements WizardSession's Living Draft state and HostCompile composition ownership together because either half alone leaves duplicate planning or untestable dirty state.

It does not split WizardViewModel into stage view models; that remains #110. It does not redesign Profile v1, extract ProvisioningJobRunner, add dependencies, or implement #111's cache policy beyond refusing stale media.
