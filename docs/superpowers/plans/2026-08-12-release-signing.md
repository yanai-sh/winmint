# Plan: SignPath release signing

**Date:** 2026-08-12  
**Spec:** [2026-08-12-release-signing-design.md](../specs/2026-08-12-release-signing-design.md)  
**Issue:** [#112](https://github.com/yanai-sh/winmint/issues/112)

Every path under **Files** was verified at the current baseline. `Add` marks a proposed path; `Modify` names an existing path unless the entry explicitly says a prior slice creates it.

Before SignPath Foundation acceptance, complete slices 1 through 3 and the documentation portion of slice 9. These are provider-independent policy, metadata, inventory, and packaging-boundary changes. Do not claim signed releases.

Slices 4 through 8, the provider tabletop in slice 9, and final acceptance are blocked until SignPath accepts the project. Before starting them, confirm the accepted artifact formats, certificate subject, timestamp verification method, artifact-configuration schema, source/build policy availability, and `windows-11-arm` origin acceptance. Every code slice retains a runnable local check; the protected tagged workflow is the final integration check.

## 1. Publish eligibility, privacy, and code-signing policy

**Files**

- Add `SECURITY.md`
- Add `PRIVACY.md`
- Add `docs/CODE_SIGNING.md`
- Modify `README.md`
- Add `docs/runbooks/release-signing-incident.md`
- Add `tests/contract/Test-ReleaseSigningPolicy.ps1`
- Modify `Justfile`

**Required content**

- Exact SignPath attribution:

  > Free code signing provided by SignPath.io, certificate by SignPath Foundation.

- Expected Windows publisher: `SignPath Foundation`; replace this expectation with the exact display confirmed from the accepted sample.
- Named repository authors/reviewers/approvers and links only where GitHub exposes a truthful public listing.
- Manual approval requirement.
- Current unsigned status, planned signed classes, and intentionally hash-only classes.
- No SmartScreen/antivirus guarantee and no “signed ISO” claim.
- Elevated mutation/destructive WinPE warning.
- Portable-toolkit removal and self-erasing Supervisor behavior.
- Network/privacy statement enumerating operator-requested GitHub, Microsoft, WinGet, Scoop, and package endpoints.
- Security report address/process and supported release policy.
- Incident runbook steps from the design.

**Red/check**

Add a documentation contract to `tests/contract/Test-ReleaseSigningPolicy.ps1` that requires the exact attribution, publisher, privacy statement, role headings, artifact classes, manual approval, revocation, and signed-ISO denial.

Run:

```powershell
pwsh -NoProfile -File tests/contract/Test-ReleaseSigningPolicy.ps1
```

Expected initially: missing-file failures.

**Green**

Write the policies and link “Code signing policy” from README's download/release section. Submit the repository to SignPath Foundation only after the policy check passes. Record the application URL/status privately if it contains account data; record acceptance publicly on #112. This slice does not configure SignPath or alter `.github/workflows/release.yml`.

**Commit:** `docs: publish release signing and privacy policy`

## 2. Make release version and PE metadata consistent

**Files**

- Modify `Directory.Build.props`
- Modify `tools/release/Compress-WinMintRelease.ps1` or replace build responsibility in slice 3
- Add `tools/release/Test-WinMintVersionMetadata.ps1`
- Add `tests/contract/Test-ReleaseVersion.ps1`
- Modify `Justfile`

**Interface**

The release command takes a required tag and derives:

```text
v1.2.3
Version=1.2.3
FileVersion=1.2.3.0
AssemblyVersion=1.2.0.0
InformationalVersion=1.2.3+0123456789abcdef0123456789abcdef01234567
```

Set in MSBuild:

```xml
<Product>WinMint</Product>
<Company>WinMint contributors</Company>
<RepositoryUrl>https://github.com/yanai-sh/winmint</RepositoryUrl>
<PublishRepositoryUrl>true</PublishRepositoryUrl>
```

Pass version properties explicitly to every `dotnet publish`. Reject non-`vMAJOR.MINOR.PATCH` tags, dirty release worktrees, and tags not pointing at `HEAD`.

`Test-WinMintVersionMetadata.ps1` reads each WinMint-owned PE's version resource and asserts ProductName, CompanyName, ProductVersion, FileVersion, and release consistency.

**Red**

```powershell
pwsh -NoProfile -File tests/contract/Test-ReleaseVersion.ps1
```

Expected: current projects do not provide the complete consistent metadata/tag contract.

**Green**

Implement metadata and tests. The contract uses a temporary local tag-shaped input and does not create/move Git tags.

Run:

```powershell
pwsh -NoProfile -File tests/contract/Test-ReleaseVersion.ps1
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj
```

**Commit:** `build: make release version metadata signable`

## 3. Separate unsigned publish from final packaging

**Files**

- Add `tools/release/Publish-WinMintRelease.ps1`
- Modify `tools/release/Compress-WinMintRelease.ps1`
- Add `tools/release/Get-WinMintReleaseInventory.ps1`
- Add `tests/contract/Test-ReleaseInventory.ps1`
- Modify `Justfile`

**Interfaces**

```powershell
Publish-WinMintRelease.ps1
  -Tag v1.2.3
  -StageRoot C:\WinMintRelease\unsigned
  -Runtime win-arm64
  -Configuration Release

Get-WinMintReleaseInventory.ps1
  -StageRoot C:\WinMintRelease\unsigned
  -Tag v1.2.3
  -Phase Unsigned|Signed
  -OutFile C:\WinMintRelease\unsigned-manifest.json

Compress-WinMintRelease.ps1
  -Tag v1.2.3
  -StageRoot C:\WinMintRelease\signed
  -OutDir C:\WinMintRelease\assets
```

Publish owns `dotnet publish` and copying toolkit files. Compress never builds, restores, or changes staged files. It creates only the final ZIP and `.sha256`.

The unsigned inventory classifies every file:

```text
winmint-pe
winmint-powershell
upstream-pe
hash-only
generated-after-signing
```

Ownership is determined by exact staging paths and assembly/script allowlists, not merely extension or signer. Unknown EXE/DLL/PS1 fails inventory.

**Red**

Contract fixtures contain WinMint PE names, upstream names, scripts, config, and one unknown executable. Tests prove:

- expected classification;
- unknown executable/script fails;
- only WinMint classes are signing candidates, with PowerShell eligibility gated on provider confirmation;
- no upstream path matches the signing allowlist;
- final compressor does not invoke `dotnet`;
- final hash format remains lowercase SHA-256 plus filename.

Run:

```powershell
pwsh -NoProfile -File tests/contract/Test-ReleaseInventory.ps1
```

Expected: missing scripts/classification failures.

**Green**

Split the script and emit `unsigned-manifest.json` with schema/tag/version/commit/workflow origin/path/class/hash/length/PE metadata.

Run:

```powershell
just release-contract
```

**Commit:** `refactor(release): separate publishing from signed packaging`

## 4. Configure SignPath Foundation project

**External prerequisite:** Start this slice only after SignPath Foundation accepts `yanai-sh/winmint`. Treat every slug below as requested until the provider creates it.

**External configuration**

Create exactly:

```text
Project slug:                 winmint
Artifact configuration slug: winmint-release
Signing policy slug:          release-signing
Trusted build system:         GitHub.com
```

Install the SignPath GitHub App for `yanai-sh/winmint` and link the project to that trusted build system.

The artifact configuration root is the ZIP produced by GitHub `upload-artifact`. Configure recursive signing for only:

```text
bin/cli/WinMint.*.exe
bin/cli/WinMint.*.dll
bin/wizard/WinMint.*.exe
bin/wizard/WinMint.*.dll
artifacts/provisioning/WinMint.Provisioning.exe
**/*.ps1
```

Treat those as staging-root-relative paths. Upload a representative artifact first and include any wrapper directory observed in the provider-generated configuration. Add PE metadata restrictions from the design. Submit a representative PE and `.ps1` sample. Record the exact certificate subject, Windows publisher display, supported timestamp type, and verification commands. If SignPath cannot sign `.ps1` in this artifact configuration, stop and update the design/issue; do not drop scripts silently.

Signing policy `release-signing`:

- SignPath Foundation certificate;
- manual approval required;
- submitter token cannot approve;
- artifact configuration fixed to `winmint-release`;
- source repository fixed to `https://github.com/yanai-sh/winmint`.

**Repository files**

- Add `.signpath/policies/winmint/release-signing.yml` only if the accepted subscription supports and validates this source/build policy
- Add `.github/CODEOWNERS` only if it reflects actual maintainers; assign `.github/workflows/release.yml`, `.signpath/`, and `tools/release/`
- Extend proposed `tests/contract/Test-ReleaseSigningPolicy.ps1` from slice 1

Conditional policy YAML:

```yaml
github-policies:
  runners:
    require_github_hosted: true
  build:
    disallow_reruns: true
```

Do not commit this file if the accepted tier does not support it. Do not add branch-review assertions that the solo repository does not enforce.

**GitHub environment**

Create `release-signing` and set:

```text
Environment variable SIGNPATH_ORGANIZATION_ID
Environment variable SIGNPATH_PROJECT_SLUG=winmint
Environment variable SIGNPATH_ARTIFACT_CONFIGURATION_SLUG=winmint-release
Environment variable SIGNPATH_SIGNING_POLICY_SLUG=release-signing
Environment secret   SIGNPATH_API_TOKEN
```

The provider-assigned organization ID and token are the only values not stored in the repository. No certificate/PFX secret is created.

**Check**

```powershell
pwsh -NoProfile -File tests/contract/Test-ReleaseSigningPolicy.ps1
```

Then submit SignPath's sample artifact from a temporary workflow and verify manual approval is required. Do not publish that artifact.

**Commit:** `build: declare SignPath trusted build policy`

## 5. Verify signed payloads fail closed

**External prerequisite:** Use the accepted sample and recorded provider contract from slice 4. Do not invent signer or timestamp fixtures before those values are known.

**Files**

- Add `tools/release/Test-WinMintSignedRelease.ps1`
- Add `tests/contract/Test-SignedReleaseVerification.ps1`
- Modify proposed `tools/release/Get-WinMintReleaseInventory.ps1` from slice 3
- Modify `Justfile`

**Interface**

```powershell
Test-WinMintSignedRelease.ps1
  -UnsignedManifest C:\WinMintRelease\unsigned-manifest.json
  -SignedStageRoot C:\WinMintRelease\signed
  -Tag v1.2.3
  -SignPathRequestId $requestId
  -SignPathRequestUrl $requestUrl
  -OutFile C:\WinMintRelease\release-manifest.json
```

The verifier:

- enumerates actual files independently of the unsigned manifest;
- rejects additions/removals/unknown executable files;
- checks required WinMint files with `Get-AuthenticodeSignature`;
- builds signer chain with online revocation;
- requires the signer subject confirmed from the accepted sample;
- locates native ARM64 Windows SDK `signtool.exe` and runs `/pa /all /v` for PE files;
- verifies timestamps with the provider-confirmed method;
- checks PE metadata;
- proves each upstream/hash-only file hash is unchanged;
- rejects any upstream file whose bytes changed after unsigned inventory;
- writes final per-file hashes/status and request identity.

Require `RuntimeInformation.OSArchitecture` and `RuntimeInformation.ProcessArchitecture` to equal `Arm64`. Record these environment values for diagnostics:

```text
PROCESSOR_ARCHITECTURE
PROCESSOR_ARCHITEW6432
RuntimeInformation.OSArchitecture
RuntimeInformation.ProcessArchitecture
```

Fail the protected release if PowerShell is not native ARM64.

**Red**

Fixture tests use:

- unsigned fake WinMint PE/script;
- wrong-publisher signed fixture;
- tampered signed fixture;
- changed upstream fixture;
- missing timestamp fixture;
- extra executable fixture.

Abstract only signature inspection/command invocation behind scriptblocks so fixtures do not need live SignPath access. Production defaults use Windows APIs and SignTool for PE verification. If `.ps1` signing is accepted, use `Get-AuthenticodeSignature`, explicit chain validation, and the provider-confirmed timestamp method; do not assume SignTool verifies scripts.

Run:

```powershell
pwsh -NoProfile -File tests/contract/Test-SignedReleaseVerification.ps1
```

Expected: missing verifier, then one focused failure per invalid fixture.

**Green**

Implement the verifier and final manifest. Enumerate version directories under `${env:ProgramFiles(x86)}\Windows Kits\10\bin`, parse valid SDK versions, select the highest version containing `arm64\signtool.exe`, and record the resolved path.

Fail if native ARM64 SignTool is absent; do not silently use x64.

**Commit:** `feat(release): verify SignPath payload signatures`

## 6. Build the protected tagged workflow

**External prerequisite:** Replace the current `release` workflow's single `pack` job only after slices 4 and 5 pass against an accepted sample.

**Files**

- Modify `.github/workflows/release.yml`
- Add `tools/release/New-WinMintReleaseManifests.ps1` only if inventory/verifier cannot remain narrow
- Extend proposed `tests/contract/Test-ReleaseSigningPolicy.ps1` from slice 1

**Jobs**

1. `build-test-unsigned`
   - GitHub-hosted Windows ARM64;
   - `contents: read`;
   - checkout tag, setup .NET, `just check`;
   - publish staging and unsigned inventory;
   - upload one immutable unsigned artifact with `actions/upload-artifact`;
   - output its artifact ID.
2. `sign`
   - same GitHub-hosted runner class;
   - `actions: read`, `contents: read`;
   - `environment: release-signing`;
   - submit exactly the prior artifact ID using SignPath's submit-signing-request action pinned to a full commit SHA;
   - `wait-for-completion: true`;
   - set `wait-for-completion-timeout-in-seconds: 2700`;
   - download signed staging through `output-artifact-directory`;
   - capture `signing-request-id` and `signing-request-web-url`;
   - run signed-release verifier.
3. `package-attest-publish`
   - download only verified signed staging;
   - compress final ZIP and compute checksum;
   - produce payload and release-assets manifests;
   - attest final ZIP using `actions/attest-build-provenance`;
   - publish all required assets in one GitHub Release operation.

Required final assets:

```text
WinMint-v1.2.3.zip
WinMint-v1.2.3.zip.sha256
WinMint-v1.2.3.unsigned-manifest.json
WinMint-v1.2.3.release-manifest.json
```

Release notes link the SignPath request and GitHub attestation.

**Action pinning**

Before editing the workflow, choose current supported releases for SignPath submission, artifact upload/download, attestation, checkout, .NET setup, and GitHub Release publishing. Resolve each selected tag through `gh api repos/{owner}/{repository}/git/ref/tags/{tag}`. If the tag is annotated, dereference its object to the commit.

Commit full SHAs with version comments. Replace the current mutable `softprops/action-gh-release@v2` reference. Never put mutable tags in the merged workflow.

**Red**

The policy contract parses workflow YAML text and asserts:

- three ordered jobs;
- least permissions;
- environment only on signing job;
- artifact ID is passed to SignPath;
- `wait-for-completion: true`;
- all actions use 40-character SHAs;
- no PFX/certificate password;
- publish depends on successful verification;
- no release upload in build/sign jobs.

Run:

```powershell
pwsh -NoProfile -File tests/contract/Test-ReleaseSigningPolicy.ps1
```

Expected: current one-job workflow fails.

**Green**

Implement the workflow. Set job/workflow timeouts to allow the 45-minute signing wait and subsequent verification/package work. Keep per-tag non-cancelling concurrency.

**Commit:** `ci: sign and attest protected releases`

## 7. Verify release trust in bootstrap

**External prerequisite:** Implement against the accepted manifest, signer, and `.ps1` policy from slices 4 through 6.

**Files**

- Modify `winmint.ps1`
- Modify `tests/contract/Test-BootstrapContract.ps1`
- Add signed/unsigned manifest fixtures under `tests/fixtures/bootstrap/` only as needed
- Modify `README.md`

**Functions**

```powershell
Test-WinMintPublisherSignature
Read-WinMintReleaseManifest
Test-WinMintExtractedRelease
```

After ZIP hash verification/extraction and before any extracted script/executable runs:

- match manifest tag/version to GitHub release;
- enumerate executable/script paths independently;
- require valid signatures from the accepted signer for every WinMint PE and each `.ps1` covered by policy;
- require listed final hashes;
- reject extra WinMint executable/script files;
- require unchanged hashes for hash-only payload;
- fail with `Integrity`, non-retryable;
- allow `-Force` to redownload, never bypass checks.

Keep helpers compatible with Windows PowerShell 5.1 syntax because bootstrap starts there before ensuring pwsh 7.6.

**Red**

Contract cases:

- valid modeled release passes;
- wrong tag, missing manifest, tampered file, wrong publisher, invalid status, missing expected file, extra `WinMint.*.dll`, extra `.ps1`, and changed hash-only file fail before launch;
- `-Force` still verifies;
- unsigned legacy release produces an explicit unsupported/unsigned failure unless the operator pins an older bootstrap version outside this implementation.

Use injected signature results in contract tests; do not weaken production verification.

Run:

```powershell
pwsh -NoProfile -File tests/contract/Test-BootstrapContract.ps1
```

Expected: new trust cases fail.

**Green**

Implement verification and update bootstrap asset selection to download the release manifest. Update the canonical README command to download the versioned signed bootstrap file, call `Get-AuthenticodeSignature`, require `Valid` plus the signer subject confirmed in slice 4, then execute with `pwsh -File`.

Keep `irm https://winmint.yanai.sh | iex` only in a clearly labeled convenience section that states the initial HTTPS/repository trust gap.

**Commit:** `feat(bootstrap): require signed WinMint release payloads`

## 8. Sign and publish the bootstrap script

**External prerequisite:** SignPath must confirm `.ps1` support. If it does not, stop and revise the bootstrap trust design before this slice.

**Files**

- Modify proposed `tools/release/Publish-WinMintRelease.ps1` from slice 3
- Modify `.github/workflows/release.yml`
- Modify proposed `tools/release/Get-WinMintReleaseInventory.ps1` from slice 3
- Modify proposed `tools/release/Test-WinMintSignedRelease.ps1` from slice 5
- Modify `README.md`

**Behavior**

- Copy repository `winmint.ps1` into unsigned staging as `bootstrap\winmint.ps1`, relative to `StageRoot`.
- Sign it through the same SignPath request.
- Verify it under the same publisher/timestamp policy.
- Publish the exact signed copy as `winmint-v1.2.3.ps1` release asset, substituting the actual tag.
- Publish `winmint-v1.2.3.ps1.sha256`, substituting the actual tag.
- Configure `winmint.yanai.sh` separately to serve/redirect to that immutable signed asset; never generate a different script at the edge.

The source-tree `winmint.ps1` remains unsigned to avoid committing generated signature blocks. Only the staged release copy is signed.

**Check**

```powershell
pwsh -NoProfile -File tests/contract/Test-ReleaseInventory.ps1
pwsh -NoProfile -File tests/contract/Test-SignedReleaseVerification.ps1
pwsh -NoProfile -File tests/contract/Test-BootstrapContract.ps1
```

Expected locally: the staged bootstrap is required, signed, and hash-published. After configuring `winmint.yanai.sh`, fetch its immutable target and record a separate byte-identity check.

**Commit:** `feat(release): publish a signed bootstrap script`

## 9. Exercise rejection and incident paths

Write the runbook content in slice 1 before acceptance. Run the tabletop steps below only after the SignPath project, environment, and draft protected workflow exist.

**Files**

- Extend proposed `docs/runbooks/release-signing-incident.md` from slice 1
- Add `tools/release/Disable-WinMintRelease.ps1` only if GitHub's normal draft/delete commands cannot express the safe operation
- Extend proposed `tests/contract/Test-ReleaseSigningPolicy.ps1` from slice 1

Prefer documented `gh` commands over a wrapper:

```powershell
$tag = 'v1.2.3'
gh release edit $tag --draft
gh release delete-asset $tag 'WinMint-v1.2.3.zip' --yes
gh secret delete SIGNPATH_API_TOKEN --env release-signing
```

The runbook covers:

- SignPath timeout/denial;
- partial GitHub release;
- wrong publisher/timestamp;
- leaked submitter token;
- compromised workflow/source release;
- SignPath suspension/revocation;
- affected-hash/request-ID inventory;
- user advisory/withdrawal;
- bootstrap denylist update;
- audited resumption.

**Tabletop check**

Against a disposable draft release:

1. force verification failure and prove no public release is created;
2. create a partial draft and follow cleanup;
3. remove environment token and prove signing fails before submission;
4. restore token and require a new workflow run (rerun remains disallowed);
5. record command output in #112 without secrets.

**Commit:** `docs: add release signing incident runbook`

## 10. Final acceptance

Run locally:

```powershell
just check
just release-contract
```

Create a release-candidate tag in the approved process. The GitHub-hosted native ARM64 workflow must prove:

- all tests/checks before signing;
- immutable artifact ID accepted by SignPath;
- manual SignPath approval;
- complete signed payload returned;
- every WinMint PE valid under the accepted signer and timestamp policy;
- every `.ps1` required by the accepted policy valid under its provider-confirmed verification method;
- every upstream/hash-only byte unchanged;
- final ZIP/hash/manifests/attestation/bootstrap assets published;
- clean-machine bootstrap verifies before launch;
- CLI and Wizard start with both operating-system and process architecture reported as `Arm64`;
- Supervisor remains valid after staging into an Output ISO;
- no release note claims signed ISO, Microsoft endorsement, warning-free behavior, or EV reputation.

After two consecutive successful signed releases, close #112 with links to:

- policy/privacy/security docs;
- SignPath project/policy;
- both GitHub workflow runs;
- signing request pages;
- release manifests and attestations;
- bootstrap contract result;
- incident tabletop record.

Do not apply `ready-for-agent` until the implementation session begins.

