# Plan: Safe warm source media

**Date:** 2026-08-12  
**Spec:** [2026-08-12-safe-warm-media-design.md](../specs/2026-08-12-safe-warm-media-design.md)  
**Issue:** [#111](https://github.com/yanai-sh/winmint/issues/111)

Implement in order. Each slice starts red, ends with its focused check green, and is a reviewable commit. Do not preserve the unsafe behavior behind a compatibility alias.

## 1. Remove caller-owned mutable reuse

**Files**

- Modify `tests/WinMint.Tests/ImageServicingApplyTests.cs`
- Modify/add focused CLI tests under `tests/WinMint.Tests/`
- Modify `src/WinMint.Orchestrator/ImageServicing.Types.cs`
- Modify `src/WinMint.Orchestrator/HostCompile.cs`
- Modify `src/WinMint.Orchestrator/ImageServicing.cs`
- Modify `src/WinMint.Orchestrator/BuildArtifacts.cs`
- Modify `src/WinMint.Cli/Program.cs`
- Modify `src/WinMint.Wizard/WizardBuild.cs`
- Modify `tools/apply/Invoke-HostApply.ps1`
- Modify `Justfile`
- Modify `servicing/Mount-InstallWim.ps1`

**Red**

- Replace the tests that expect `reuseMedia=true/false` with assertions that materialized `MountInstallWim` parameters contain no `reuseMedia`.
- Add a CLI parse/help assertion that `--reuse-media` is rejected/absent.
- Add a repository contract assertion that no current host/stage contract declares `ReuseMedia`.

Run:

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~ImageServicingApplyTests|FullyQualifiedName~Cli"
```

Expected: compilation/test failure while the option and record fields remain.

**Green**

- Delete the flag and plumbing at every listed seam.
- Delete both reuse branches from `Mount-InstallWim.ps1`.
- Make the remaining pre-cache path always require a real Source ISO and fresh media.
- Do not yet optimize the repeated extraction; this slice only eliminates unsound behavior.

Run the focused test again, then:

```powershell
rg -i "reuse[-_ ]?media" src servicing tools Justfile README.md docs/design tests
```

Expected: no active contract/help match. Historical specs/research outside those paths may remain.

**Commit:** `fix(servicing): remove unsafe mutable media reuse`

## 2. Add source identity and cache contract

**Files**

- Add `src/WinMint.Orchestrator/ImageServicing.MediaCache.cs`
- Modify `src/WinMint.Orchestrator/ImageServicing.cs`
- Modify `src/WinMint.Orchestrator/BuildArtifacts.cs`
- Add `tests/WinMint.Tests/MediaCacheIdentityTests.cs`
- Modify `tests/WinMint.Tests/ImageServicingApplyTests.cs`

**Interface**

Keep the implementation internal:

```csharp
internal readonly record struct MediaCacheIdentity(
    string SourceIsoSha256,
    long SourceIsoLength,
    int SourceIndex,
    int Schema)
{
    internal const int CurrentSchema = 1;
    internal string RelativeEntryPath =>
        Path.Combine($"v{Schema}", SourceIsoSha256, $"index-{SourceIndex}");
}
```

Use `SHA256.HashDataAsync(FileStream, ct)` and lowercase hexadecimal output. Reject non-positive source index. Resolve cache root from `Environment.SpecialFolder.CommonApplicationData`:

```text
<CommonApplicationData>\WinMint\Servicing\media-cache
```

Do not accept a caller-supplied cache root.

Add stage parameter constants:

```text
sourceIsoSha256
sourceIsoLength
sourceIndex
cacheSchema
cacheRoot
```

The host computes identity once before writing `stages.json`; the elevated stage rechecks Source ISO length/hash before using the cache.

**Red**

Tests prove:

- same bytes/different paths → same identity;
- one changed byte → different identity;
- different index/schema → different relative path;
- SHA output is lowercase 64-character hex;
- zero/negative index fails;
- materialized mount stage includes all identity fields and no reuse field.

Run:

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~MediaCacheIdentityTests|FullyQualifiedName~ImageServicingApplyTests"
```

Expected: tests fail because the identity and parameters do not exist.

**Green**

Implement the minimum internal type/hash function and materialization wiring. Keep extraction behavior unchanged until slice 3.

**Commit:** `feat(servicing): identify source media by content`

## 3. Prepare and validate transactional cache entries

**Files**

- Add `servicing/Initialize-SourceMediaCache.ps1`
- Modify `servicing/Mount-InstallWim.ps1`
- Add `tests/contract/Test-SourceMediaCache.ps1`
- Modify `Justfile` to include the contract check

**PowerShell helper contract**

`Initialize-SourceMediaCache.ps1` is dot-sourced by the mount kernel and exposes narrow functions:

```powershell
Get-WinMintMediaCacheEntry
Test-WinMintMediaCacheEntry
New-WinMintMediaCacheEntry
Move-WinMintInvalidMediaCacheEntry
```

Inputs are only source path/hash/length/index, schema, cache root, and injected command scriptblocks for contract tests. Production defaults call `Mount-DiskImage`, `Dismount-DiskImage`, `robocopy`, DISM, and existing WIM metadata helpers.

Do not create a generic command framework. Injection exists only at the OS-command boundary required by the runnable contract test.

**Red**

The contract test uses temporary fake ISO/media trees and command scriptblocks. It proves:

- final entry absent until manifest publication;
- manifest contains every required field and round-trips;
- a failed extraction/export/hash leaves no final entry;
- an existing valid winner is used without merge;
- partial, malformed, wrong-key, wrong-length, wrong-hash, and multi-index entries are rejected;
- invalid entries are renamed, not edited in place;
- a rebuild is attempted at most once;
- source hash/length are rechecked before hit/preparation;
- `install.esd` fails with the documented message.

Run:

```powershell
pwsh -NoProfile -File tests/contract/Test-SourceMediaCache.ps1
```

Expected: command fails because the helper does not exist.

**Green**

- Create same-parent `.prepare-*` staging.
- Extract the complete ISO tree.
- Export selected `install.wim` index into a separate file.
- Reuse `Get-WimMetadata.ps1` assertions and edition-config writer.
- Hash `install.wim` and `boot.wim`.
- Write manifest last, parse it back, then same-volume rename staging to final.
- On a race, validate/use the winning final entry.
- Quarantine invalid entries and rebuild once.
- Reject reparse points before writing/mounting.
- Apply Administrators/SYSTEM-write ACLs when creating the cache root.

Run the contract test twice: the second run must leave no global cache/test residue.

**Commit:** `feat(servicing): prepare transactional source media cache`

## 4. Copy fresh mutable media for every Apply

**Files**

- Extend `servicing/Initialize-SourceMediaCache.ps1`
- Modify `servicing/Mount-InstallWim.ps1`
- Extend `tests/contract/Test-SourceMediaCache.ps1`
- Modify `tests/WinMint.Tests/ImageServicingApplyTests.cs` only if stage parameter assertions change

**Red**

Add contract cases:

- cache hit does not invoke ISO mount/copy or WIM export;
- cache miss and hit both call the same fresh-run-copy function;
- existing `work\media` is moved aside and never used as source;
- failed incoming copy is not renamed to `media`;
- source and destination files have distinct file IDs on NTFS;
- changing destination `install.wim` leaves cached hash unchanged;
- mount image path under cache root is rejected;
- payload omitted from the cached source cannot survive from prior run media.

Run:

```powershell
pwsh -NoProfile -File tests/contract/Test-SourceMediaCache.ps1
```

Expected: new isolation cases fail.

**Green**

Add:

```powershell
Copy-WinMintRunMedia
Assert-WinMintMountImagePath
```

Use ordinary `robocopy /E /COPY:DAT` into `media.incoming-{guid}`, validate the single-index WIM, rename to `media`, clear read-only bits, and mount only the run WIM. Never use `/SL`, hard links, or cache paths as mount image files.

No ReFS branch in this slice.

**Commit:** `feat(servicing): isolate each run from cached media`

## 5. Serialize mount ownership and recover stale mounts

**Files**

- Add `servicing/Resolve-WinMintMount.ps1`
- Modify `servicing/Invoke-ServicingPlan.ps1`
- Modify `servicing/Mount-InstallWim.ps1`
- Modify `servicing/Export-Wim.ps1`
- Add `tests/contract/Test-WinMintMountRecovery.ps1`
- Modify `Justfile`

**Interface**

The elevated loop acquires machine-wide mutex `Global\WinMint.ImageServicing.v1` before any stage and holds it through final evidence/failure cleanup.

`Resolve-WinMintMount.ps1` owns:

```powershell
Get-WinMintMountedImages
Resolve-WinMintStaleMount
Write-WinMintMountOwner
Remove-WinMintMountOwner
```

It parses DISM mounted-image output once and refuses paths outside `%ProgramData%\WinMint\Servicing\mounts\`.

**Red**

Contract cases:

- second lock acquisition reports active servicing;
- owner file with live PID fails without discard;
- dead/missing owner plus owned mount discards and verifies;
- discard stale-state failure triggers one `Cleanup-Wim` and re-query;
- unrelated mount is never discarded;
- cache WIM path is never discarded/mounted;
- owner file is written immediately before mount;
- owner is removed only after successful unmount/discard;
- failed recovery stops before Source ISO/cache mutation.

Run:

```powershell
pwsh -NoProfile -File tests/contract/Test-WinMintMountRecovery.ps1
```

Expected: command fails because ownership/recovery helper does not exist.

**Green**

Implement the mutex and recovery rules. Update Export/unmount cleanup so owner lifecycle matches actual DISM state. Preserve owner/recovery paths and command results in failure diagnostics.

**Commit:** `fix(servicing): serialize and recover owned WIM mounts`

## 6. Emit cache provenance and phase timings

**Files**

- Modify `servicing/Invoke-ServicingPlan.ps1`
- Modify `servicing/Mount-InstallWim.ps1`
- Modify `src/WinMint.Orchestrator/ImageServicing.Types.cs`
- Modify `src/WinMint.Orchestrator/ImageServicing.cs`
- Modify `tests/WinMint.Tests/ImageServicingApplyTests.cs`
- Modify relevant evidence contract tests under `tests/contract/`

**Red**

Add assertions for every field specified by the design:

- source hash/length/index;
- cache schema/key/entry path/outcome/WIM hashes/copy mode/recovery action;
- source hash, validation, preparation, copy, mount, export, and ISO timing;
- non-negative integer milliseconds;
- completed phase values retained on failure.

Run:

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~ImageServicingApplyTests"
pwsh -NoProfile -File tests/contract/Test-SourceMediaCache.ps1
```

Expected: evidence assertions fail.

**Green**

Use `System.Diagnostics.Stopwatch` in C# and `[System.Diagnostics.Stopwatch]` in PowerShell. Write a cache-result document under the workdir for the elevated loop to merge into `evidence.json`; do not let the kernel write final evidence directly.

Extend `ImageEvidence` only for values consumed by host/Wizard. Preserve the full document for audit even when the typed host surface stays narrow.

**Commit:** `feat(servicing): record media cache provenance and timings`

## 7. Prove cross-run isolation on Windows

**Files**

- Add `tests/metal/Invoke-WarmMediaAcceptance.ps1`
- Modify `Justfile` with an explicit non-default target, for example `warm-media-acceptance`
- Add a small opposite-profile fixture only if existing fixtures cannot express the two runs

**Test flow**

1. Require elevation, native ARM64 host detection aware of `PROCESSOR_ARCHITEW6432`, native ARM64 `pwsh` 7.6+, Source ISO, and explicit destructive-test acknowledgment.
2. Remove only the expected cache key to force cold.
3. Run Profile A in a fresh workdir and save source/cache/evidence hashes.
4. Run Profile B in the same workdir with opposite removal/payload intent.
5. Assert a warm hit, fresh run-media path, unchanged cached WIM hashes, no A-only residue, and correct B intent.
6. Corrupt a copied test cache entry and assert quarantine/rebuild.
7. Run existing Test metal evidence checks on both Output ISOs.

This check is not part of default `just check` because it requires elevation, Source ISO, disk space, and minutes of host servicing.

Run:

```powershell
just warm-media-acceptance SOURCE_ISO="<official-arm64.iso>"
```

Expected before implementation: second run exposes residue or lacks cache provenance. Expected after: all assertions pass.

**Commit:** `test(servicing): prove warm media run isolation`

## 8. Add native ARM64 benchmark

**Files**

- Add `tools/bench/Measure-WarmMedia.ps1`
- Add `docs/evidence/warm-media-benchmark-template.md`
- Modify `Justfile` with `bench-warm-media`

**Behavior**

- Validate native ARM64 PowerShell using both `PROCESSOR_ARCHITECTURE` and `PROCESSOR_ARCHITEW6432`.
- Require a fixed Source ISO, index, Profile, output directory, and baseline commit/worktree path.
- Run one untimed prime plus five cold, five warm, and five pre-change baseline runs.
- Capture per-phase/total milliseconds, range, median, filesystem, storage model, cache/work disk growth, WinMint commit, Source ISO hash, and pwsh/.NET/Windows versions.
- Write machine-readable JSON and a concise Markdown record.
- Do not automatically enable ReFS cloning.

**Check**

```powershell
pwsh -NoProfile -File tools/bench/Measure-WarmMedia.ps1 -WhatIf
```

Expected: validates inputs and prints the exact matrix without mutation.

Then run the full benchmark on the native ARM64 development host and attach the completed record to #111.

**Commit:** `perf(servicing): benchmark cold and warm media paths`

## 9. Update operator and module documentation

**Files**

- Modify `docs/design/IMAGESERVICING.md`
- Modify `docs/DESIGN.md`
- Modify `README.md`
- Modify CLI/Justfile help snapshots or docs affected by option removal
- Update `docs/ARCHITECTURE.md` only if implementation changes the planned boundary

**Content**

- New `ServicingRun` interface.
- Automatic cache ownership and exact root/key.
- Immutable cache/fresh mutable workspace invariant.
- One-Apply-per-host v1 ceiling and upgrade path.
- Stale-mount behavior and operator recovery evidence.
- How to remove a cache entry safely while no Apply is active.
- Cold/warm progress labels and evidence fields.
- `--reuse-media` removal/migration note.
- ReFS cloning remains deferred pending benchmark threshold.

Run:

```powershell
rg -i "reuse[-_ ]?media" src servicing tools Justfile README.md docs/design tests
just check
```

Expected: only an intentional migration/history sentence if needed; all checks green.

**Commit:** `docs: document safe source media caching`

## Release gate

Before closing #111:

```powershell
just check
just warm-media-acceptance SOURCE_ISO="<official-arm64.iso>"
just bench-warm-media SOURCE_ISO="<official-arm64.iso>"
```

Record:

- `just check` result;
- cold/warm acceptance evidence paths and Output ISO hashes;
- benchmark JSON/Markdown;
- cache entry manifest;
- confirmation that cached WIM hashes did not change;
- Test metal result;
- Gate B result before Release claims.

Do not apply `ready-for-agent` until an implementation session actually begins.

