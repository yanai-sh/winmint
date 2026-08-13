# Spec: Safe warm source media

**Date:** 2026-08-12  
**Status:** Implementing — living terms are **Prepared media** and **staged media** ([CONTEXT](../../../CONTEXT.md)). Do not say cache / run media / reuse in operator docs.  
**Authority:** [DESIGN](../../DESIGN.md) · [IMAGESERVICING](../../design/IMAGESERVICING.md) · [BUILDPLAN](../../design/BUILDPLAN.md)  
**Research:** [CTT/WinUtil lessons](../../research/2026-08-12-ctt-winutil-lessons.md)  
**Issue:** [#111](https://github.com/yanai-sh/winmint/issues/111)

Repository-relative paths in this document exist at the post-#94 baseline unless marked **proposed**. Host paths marked **proposed** are created by #111.

## Decision

ImageServicing automatically prepares and uses an immutable, content-addressed Source ISO cache. Callers no longer choose whether prior mutable build media is safe to reuse.

The cache stores a source-derived, single-index base. Every Apply copies that base into a fresh mutable run workspace before any WIM is mounted or any Profile-derived mutation occurs.

Ordinary copy is the correctness baseline. ReFS block cloning may be added only as a measured, behavior-preserving optimization.

## Problem

#94 established a conservative baseline. `HostCompile` freezes the Source ISO SHA-256 and selected `SelectedWim`, rehashes the ISO before Apply, and materializes those values into the `MountInstallWim` stage. `ReuseMedia=false` always recreates staged media. `ReuseMedia=true` accepts existing media only when `.winmint-media-identity.json` has schema `winmint.media-identity/v1` and the single-image WIM still matches the selected Name, Architecture, Edition, and Build. Missing, malformed, or mismatched identity falls back to cold recreation.

The marker and staged-WIM check prove source and selected-image identity, not pristine state. A matching tree may already contain destructive and accumulating mutations:

- provisioned AppX removals;
- capability and optional-feature removals;
- policies, drivers, payload, unattend, and shell stamps;
- boot WIM patching;
- Release `ResetBase` and WIM export.

The marker does not bind the tree to pristine install/boot WIM digests, Profile-derived mutations, or a completed cache transaction. Explicit reuse can therefore produce an Output ISO that cannot be explained by the current Profile. `Justfile` enables reuse from marker existence alone, and `tools/apply/Invoke-HostApply.ps1` still checks an obsolete single-index marker path.

This design preserves #94's source and selected-image checks, removes caller-owned reuse, and makes only pristine source preparation reusable.

## Goals

- No Apply can inherit a prior Apply's mutations.
- An unchanged Source ISO/index avoids repeated ISO extraction and multi-index export.
- Cache identity and provenance are explicit and evidence-backed.
- Interrupted or competing cache preparation cannot publish a partial entry.
- Stale DISM mounts are detected and recovered conservatively.
- Cold and warm performance is measured on native ARM64.
- The existing DISM/oscdimg-supported servicing path remains authoritative.

## Non-goals

- Persisting mounted WIMs between builds.
- Caching a Profile-specific intermediate or final WIM.
- Replacing DISM, Mount-DiskImage, robocopy, or oscdimg.
- Making Output ISO bytes reproducible across different tool/source versions.
- Deduplicating arbitrary workdirs.
- Sharing a cache over SMB or between hosts.
- Adding a Profile field or policy knob for caching.

## Interface

Remove `ReuseMedia` from caller-facing and stage contracts:

```csharp
public sealed record ServicingRun(
    string SourceIsoPath,
    string WorkDirectory,
    string? OutputIsoPath = null,
    string? ProfilePath = null,
    int? WimIndex = null,
    string? SourceIsoSha256 = null,
    SelectedWim? SelectedImage = null);
```

Remove:

- CLI `--reuse-media`;
- `HostComposeOptions.ReuseMedia`;
- `HostReview.ReuseMedia`;
- `HostComposition.ReuseMedia`;
- `StageParams.ReuseMedia`;
- `reuseMedia` in `MountInstallWim` parameters;
- Justfile/apply-script marker heuristics.

`HostCompile` already computes the Source ISO SHA-256 during composition and verifies it again before Apply. Preserve that frozen value and `SelectedWim` through `ServicingRun`. For direct `ImageServicing.ApplyAsync` callers that omit either value, use one `SourceMediaProbe` result for both the hash and selected-image metadata before materialization. It then materializes these `MountInstallWim` parameters:

```text
sourceIso
sourceIsoSha256
sourceIsoLength
wimIndex
imageName
architecture
imageEdition
imageBuild
cacheSchema
cacheRoot
mountDir
mediaDir
workDirectory
```

`wimIndex` is the effective, required source index after applying `ImageServicing.DefaultProWimIndex`. Cache behavior remains an ImageServicing implementation detail; BuildPlan does not gain cache opcodes or policy. Do not add another host-side hash beyond the existing composition hash and pre-Apply recheck. The elevated cache stage still rehashes immediately before hit validation or preparation.

## Cache identity and layout

Proposed host root:

```text
%ProgramData%\WinMint\Servicing\media-cache\v1\
```

Entry:

```text
{sourceIsoSha256}\index-{sourceIndex}\
  manifest.json
  media\
    files copied from Source ISO
    sources\
      install.wim
```

The complete cache key is:

```text
cacheSchema = 1
sourceIsoSha256 = lowercase 64-character SHA-256
sourceIndex = positive decimal integer
```

The schema version is both in the root path and manifest. Any change to extraction semantics, single-index export semantics, required manifest fields, or cache validation increments it.

The cache does not key on:

- Source ISO path, filename, timestamp, or volume;
- Profile or BuildPlan digest;
- lane;
- WinMint version;
- output path.

Those values do not alter pristine source bytes. A schema bump handles intentional preparation changes.

## Manifest

`manifest.json` is the publication marker and contains:

```json
{
  "schema": 1,
  "sourceIsoSha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "sourceIsoLength": 5872025600,
  "sourceIndex": 3,
  "preparedUtc": "2026-08-12T00:00:00Z",
  "installWimSha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "installWimLength": 4294967296,
  "bootWimSha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  "bootWimLength": 536870912,
  "image": {
    "name": "Windows 11 Pro",
    "architecture": "ARM64",
    "edition": "Professional",
    "build": "26200",
    "indexCount": 1
  }
}
```

If the Source ISO has no `boot.wim`, preparation fails. The cache stores no host path and no mutable access time. `manifest.json` is written only after all fields have been computed and validated.

## Entry validation

A hit requires all of:

1. final entry directory exists;
2. `manifest.json` parses;
3. schema, source hash, source length, and source index match the request;
4. `media\sources\install.wim` and `media\sources\boot.wim` exist;
5. recorded WIM lengths match;
6. DISM reports exactly one install image at index 1;
7. image Name/Architecture/Edition/Build are present and match the manifest and approved `SelectedWim`;
8. install/boot WIM hashes match the manifest.

Hashing both WIMs on every hit is intentionally conservative for v1. If measurement shows that validation erases the warm-path benefit, a later schema may replace it with a protected immutable-entry mechanism; it must not silently weaken v1.

A missing, partial, malformed, mismatched, or corrupt entry is a miss. It is quarantined by atomic rename to:

```text
{entry}.invalid-{yyyyMMddTHHmmssZ}-{guid}
```

Failure to quarantine an invalid entry fails Apply rather than deleting or overwriting uncertain data.

## Transactional preparation

On a miss, under the cache/mount lock:

1. Create a same-parent staging directory named `.prepare-{sha256}-index-{index}-{guid}`.
2. Mount the Source ISO.
3. Copy the complete ISO tree to `staging\media`.
4. Always dismount the ISO in `finally`.
5. Clear read-only attributes in staging.
6. Validate `install.wim` exists; fail explicitly on `install.esd`.
7. Read selected-index metadata.
8. Export only the selected index to a separate `install.single.wim` with DISM.
9. Verify index count and metadata stability.
10. Replace staging's original `install.wim` with the single-index WIM.
11. Write `ei.cfg` and remove stale `PID.txt`.
12. Hash/measure install and boot WIMs.
13. Write and parse-back `manifest.json`.
14. Move the staging directory to the final entry path on the same volume.

If the final path appears before publication, another preparer won. Validate that entry, then delete this staging directory. Never merge directories.

Any failure removes only the uniquely named staging directory after confirming no WIM beneath it is mounted. If cleanup itself fails, preserve the staging directory and include its path in failure evidence.

## Fresh run media

At Apply start:

1. If `{workDirectory}\media` exists from an earlier run, move it to `media.previous-{timestamp}-{guid}`; fail if that cannot be done.
2. Copy `entry\media` to a newly created sibling `media.incoming-{guid}`.
3. Copy all files as independent file records. Do not use hard links.
4. Clear read-only attributes in the incoming tree.
5. Validate its single-index WIM metadata.
6. Atomically rename it to `{workDirectory}\media`.
7. Before elevation, C# Materialize removes and recreates `{workDirectory}\payload`, then writes the current bundle.
8. Only then mount `{workDirectory}\media\sources\install.wim` read/write.
9. After Apply completes, remove only the `media.previous-*` directory created by this run. Preserve it on failure.

The cached WIM path is never passed to `/Mount-Image`. A path containment assertion rejects any mount image file under the cache root.

On NTFS and unsupported filesystems, ordinary file copy is required. On same-volume ReFS, a future implementation may clone extents into independent destination files using documented block-cloning APIs. The resulting files must pass the same validation and mutation-isolation tests. Clone support is not part of v1 acceptance.

## Locking and mount ownership

V1 serializes cache preparation, run-media copy, stale-mount recovery, WIM mount, servicing, and unmount under one machine-wide exclusive lock:

```text
Global\WinMint.ImageServicing.v1
```

This intentionally permits one ImageServicing Apply per host. Parallelism can be narrowed later only with evidence that DISM and mount directories are isolated safely.

The elevated loop records ownership in the proposed directory:

```text
%ProgramData%\WinMint\Servicing\mount-owners\
  install.json
  boot.json
```

Each record contains:

```text
schema, runId, processId, mountKind, workDirectory,
mountDirectory, imageFile, startedUtc, sourceIsoSha256, sourceIndex
```

The install record covers the existing `%ProgramData%\WinMint\Servicing\mount` directory. The boot record covers the existing `%ProgramData%\WinMint\Servicing\boot-mount` directory and is updated for each boot-WIM index. Create a record immediately before each DISM mount. Delete it only after successful unmount or verified discard. A record is diagnostic state, not proof that a mount exists.

## Stale-mount recovery

Before preparing/copying/mounting:

1. Query DISM mounted-WIM state.
2. If no WinMint mount exists, remove a stale owner file after recording it.
3. If a WinMint mount exists and its owner PID is alive, fail as “servicing already active.”
4. If the owner is absent/dead, call `DISM /Unmount-Image /Discard` for that WinMint mount.
5. Verify it is no longer mounted.
6. Run `DISM /Cleanup-Wim` only if discard reports stale/corrupt mount state, then query again.
7. Never discard a mount outside the exact current install and boot mount directories.
8. Never delete a cache entry or work media while its WIM appears in mounted-WIM state.

Recovery actions and DISM results are written to the run log and final evidence. A recovery failure stops Apply.

## Evidence and timings

`evidence.json` gains:

```text
source.isoSha256
source.isoLength
source.index
mediaCache.schema
mediaCache.key
mediaCache.entryPath
mediaCache.outcome        hit | miss-prepared | miss-rebuilt
mediaCache.installWimSha256
mediaCache.bootWimSha256
mediaCache.copyMode       copy | refs-block-clone
mediaCache.recoveryAction none | owner-cleanup | discard | cleanup-wim
timings.sourceHashMs
timings.cacheValidateMs
timings.cachePrepareMs
timings.runMediaCopyMs
timings.mountMs
timings.exportMs
timings.buildIsoMs
```

Paths use absolute host paths consistently with current evidence. Durations are non-negative integer milliseconds measured with a monotonic clock. Failure evidence records all completed phases and the active phase.

Console/GUI progress distinguishes:

- `Hashing Source ISO`
- `Validating source-media cache`
- `Preparing source-media cache`
- `Copying fresh run media`
- `Mounting install image`

No user-facing “reuse” switch remains.

## Failure policy

- Source hash mismatch between host materialization and elevated preparation: fail.
- Missing/unreadable Source ISO, even if a cache key was previously seen: fail. Apply always proves the requested source bytes.
- Invalid cache entry: quarantine and rebuild once.
- Rebuilt entry fails validation: fail; do not retry.
- Cache root unavailable: fail. V1 does not silently switch to the unsafe old path.
- Work-media copy incomplete or validation mismatch: preserve incoming path in failure evidence and fail.
- Cancellation: unmount/discard owned mounts, preserve logs, and never publish staging.
- Low disk space: allow copy/preparation to fail with phase/path context; a later implementation may add advisory preflight.

## Security and trust boundary

The Source ISO is user-supplied and untrusted input.

- Validate SHA-256 syntax and numeric index before constructing paths.
- Construct entry paths from normalized values only.
- Reject reparse points anywhere between cache root and an entry before writing or mounting.
- ACL cache and mount roots for Administrators/SYSTEM write; standard users receive no write access.
- Do not execute content from Source ISO during preparation.
- Do not follow links from a pre-existing invalid entry.

The cache digest establishes content identity, not Microsoft authenticity. Existing Source ISO provenance guidance remains required.

## Performance acceptance

Use the primary native ARM64 development host, native ARM64 `pwsh` 7.6+, one fixed official ARM64 Source ISO, one source index, and one Profile.

Record five successful runs for each condition after one untimed priming run:

- new cold: cache entry absent;
- new warm: valid entry present;
- #94 cold baseline: fixed pre-#111 commit, `ReuseMedia=false`, fresh workdir;
- #94 marker-reuse diagnostic: same fixed commit and matching marker, labeled unsafe and excluded from acceptance.

Record the exact baseline commit. Capture median and range for source hashing, preparation, copy, mount, total Apply, and peak cache/work disk usage. Record filesystem and storage model. Do not publish speed claims until these runs complete.

The feature ships for correctness even if warm time is not faster. Pursue ReFS cloning only if ordinary copying is at least 20% of median warm Apply time and cloning reduces median run-media-copy time by at least 30% without changing Output ISO acceptance.

## Acceptance tests

### Contract/unit

- `ServicingRun`, CLI, Wizard, host request, and stage JSON expose no reuse flag.
- `HostComposeOptions`, `HostReview`, `HostComposition`, and `WizardSession` expose or compare no reuse flag.
- HostCompile preserves the frozen Source ISO hash and `SelectedWim` through Apply.
- Same bytes at two Source ISO paths produce the same key.
- One-byte Source ISO change produces a different key.
- Different source index or schema produces a different key.
- Invalid hash/index cannot escape cache root.
- Cache manifest round-trips and rejects missing/mismatched fields.
- Cache WIM paths are rejected by mount-path containment guard.

### PowerShell integration with mocked DISM/media commands

- A miss prepares staging and publishes manifest last.
- Failure before publication leaves no final entry.
- Competing publisher uses the valid winner; no directory merge occurs.
- Partial/malformed/hash-mismatched entry is quarantined and rebuilt once.
- Cache hit copies to fresh media and never invokes Source ISO extraction/export.
- Existing work media is not reused in place.
- Copy creates independent files; mutating run `install.wim` leaves cache hash unchanged.
- Stale owned mount is discarded; active owner fails; unrelated mount is untouched.
- Cancellation never publishes staging.

### Elevated Windows integration

- Cold and warm Apply both begin servicing from identical single-index WIM and boot WIM hashes.
- Two opposite Profiles run warm in the same workdir without cross-profile residue.
- Removing a component in run A does not remove it from run B when B does not request removal.
- Removing optional payload from run B leaves no run-A payload.
- Corrupting cached `install.wim` causes quarantine/rebuild, not mount.
- Each cold/warm Output ISO passes the existing Hyper-V Smoke path in `tools/vm/Invoke-Smoke.ps1`.
- Release path still passes Gate B; Primary remains the destructive truth.

### Repository

- `rg -i "reuse[-_ ]?media" src servicing tools Justfile README.md docs/design tests` finds only historical research/migration notes.
- `just check` passes.

## Rejected alternatives

- **Keep `--reuse-media` with warnings:** callers cannot prove mutable-tree safety.
- **Delete work media only on explicit cold mode:** still couples correctness to a performance switch.
- **Mount the cache WIM read/write and restore afterward:** a crash can poison the shared base.
- **Persistent mounted base WIM:** unsupported concurrency/recovery complexity and mutable global state.
- **Hard-link cache to workdir:** WIM mutation changes the same file record.
- **Cache Profile-specific final media:** high-cardinality state with difficult invalidation and weak explanatory value.
- **Use path/mtime as key:** does not identify bytes.
- **Custom WIM/ISO implementation:** abandons supported tooling without measured need or equivalent acceptance evidence.
- **ReFS-only design:** excludes the normal NTFS host and makes correctness depend on an optimization.

## Living-document updates

Implementation updates:

- `docs/design/IMAGESERVICING.md` interface, invariants, recovery, and evidence;
- `docs/DESIGN.md` default for automatic source-media caching;
- `docs/ARCHITECTURE.md` only if the module boundary changes (not expected);
- CLI/README/Justfile help affected by `--reuse-media` removal;
- the #94 media-identity helper and contract, which the cache manifest supersedes.

No ADR is required: the decision deepens the existing ImageServicing module and removes an unsafe implementation option without changing product intent.

