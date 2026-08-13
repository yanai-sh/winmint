# Spec: Release signing and trust

**Date:** 2026-08-12  
**Authority:** [DESIGN](../../DESIGN.md) · [STACK](../../STACK.md) · [ARCHITECTURE](../../ARCHITECTURE.md)  
**Research:** [CTT/WinUtil lessons](../../research/2026-08-12-ctt-winutil-lessons.md)  
**Issue:** [#112](https://github.com/yanai-sh/winmint/issues/112)

Repository-relative paths in this document exist unless marked **proposed**. Provider slugs, policy capabilities, certificate details, and signing formats remain proposed until SignPath Foundation accepts the project and confirms its configuration.

## Decision

Authenticode is deferred. WinMint has no downloaders other than the maintainer. Do not apply to SignPath Foundation, install the SignPath GitHub App, or add a signing workflow until someone other than the maintainer is expected to run `WinMint.Cli.exe` or `WinMint.Wizard.exe` from a GitHub Release.

SignPath Foundation remains the preferred public code-signing route if that event happens.

If accepted, the release pipeline Authenticode-signs WinMint-owned Portable Executable (PE) files after build/test and before final packaging. PowerShell signing is required only if SignPath confirms `.ps1` support in the approved artifact configuration and identifies the timestamp and verification contract. The pipeline preserves upstream bytes and signatures. The final ZIP and Output ISO are integrity/provenance artifacts, not Authenticode-signed executables.

Until that integration succeeds, releases remain explicitly unsigned. No release is described as signed unless the pipeline verifies every artifact required by the accepted policy.

## Why SignPath Foundation

WinMint is GPLv3, public, Windows-specific, and currently maintained by an individual. If accepted, SignPath provides:

- a publicly trusted certificate without maintainer private-key custody;
- a verified GitHub Actions build-to-signing chain;
- mandatory signing approval;
- a route available to an OSS project that is not a legal entity.

The expected certificate subject and Windows publisher display are `SignPath Foundation`, not the repository owner or `WinMint`. Verify the exact subject and display from the first accepted sample before freezing checks or documentation.

SignPath Foundation acceptance is discretionary. WinMint must already be released, documented, actively maintained, fully OSI-licensed, free of proprietary maintainer components, and acceptable under SignPath's security/privacy rules. WinMint's elevated image mutation and optional policy changes require clear operator warnings; any feature interpreted as circumventing security controls may make the project ineligible.

If the application is rejected, WinMint may continue publishing explicitly **unsigned** releases with hashes/provenance through a separately named process. It does not silently substitute a self-signed certificate or market an organization-validation or extended-validation route that has not been funded and verified. A conventional publisher certificate is a separate future decision.

Other routes remain fallback decisions:

- Microsoft Artifact Signing is a paid managed-signing candidate that requires Microsoft identity validation. Evaluate current eligibility and cost only if SignPath rejects WinMint or its accepted policy cannot cover required artifacts.
- A conventional organization-validation or extended-validation certificate requires a verified legal publisher and a separate key-custody/CI design.
- A self-signed certificate does not provide the selected public publisher-trust boundary and is rejected for releases.
- None of these routes guarantees SmartScreen or antivirus outcomes. ARM64 and NativeAOT acceptance must be proved with WinMint's actual artifacts.

Sources:

- [SignPath Foundation conditions](https://signpath.org/terms.html)
- [SignPath GitHub trusted build system](https://docs.signpath.io/trusted-build-systems/github)
- [Microsoft Authenticode overview](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/authenticode)
- [Microsoft SmartScreen reputation](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)

## Trust claims

A successfully verified WinMint signature establishes:

- the content covered by the Authenticode digest has not changed since signing;
- Windows built a valid certificate chain at verification time;
- the signer subject matches the accepted SignPath Foundation certificate;
- the timestamp satisfies the provider-approved Authenticode timestamp policy.

The separately verified whole-file SHA-256, release manifest, and SignPath request record cover exact file bytes and establish the WinMint project, policy, request, source commit, and workflow origin. The file signature alone does not encode all of that context.

It does not establish:

- that the file is safe or bug-free;
- that Microsoft authored or endorsed WinMint;
- that SmartScreen will never warn;
- that Defender/other antivirus engines will never flag it;
- that an unsigned ZIP, JSON, CMD, or ISO has a native code signature;
- that a Source ISO or software installed by WinMint is authentic;
- that GitHub release access can never be compromised.

SmartScreen reputation varies by file hash, publisher certificate, prevalence, and telemetry. Extended Validation (EV) no longer provides an automatic reputation shortcut. After the accepted sample confirms the signer display, documentation may say “Authenticode-signed by SignPath Foundation,” never “warning-free.”

## Work allowed before acceptance

Do not apply to SignPath until a non-maintainer is expected to run a GitHub Release PE. These repository policy tasks may exist before that event:

1. Publish `SECURITY.md` (**proposed**), `PRIVACY.md` (**proposed**), and `docs/CODE_SIGNING.md` (**proposed**).
2. Link the code-signing policy from `README.md`.
3. Document team roles, system changes, removal, network behavior, unsigned-release status, artifact classes, and incident response.
4. Normalize WinMint-owned PE version metadata and add local inventory tests.
5. Split the current build-and-package behavior in `tools/release/Compress-WinMintRelease.ps1` without claiming signed output.

Provider configuration, SignPath credentials, signing requests, provider-specific artifact rules, signed-file verification fixtures, and the protected tagged workflow remain blocked until Authenticode is warranted and SignPath accepts the project.

## Eligibility and provider prerequisites

Before the first signing request:

1. SignPath Foundation accepts `yanai-sh/winmint`.
2. The SignPath GitHub App is installed for the repository.
3. The predefined GitHub.com trusted build system is linked to the SignPath organization/project.
4. All jobs leading to signing run on GitHub-hosted runners. The SignPath connector accepts origin metadata from the current `windows-11-arm` runner.
5. GitHub MFA and SignPath MFA are enabled.
6. Repository roles are published:
   - authors/committers and reviewers: repository collaborators with write/maintain access;
   - approvers: repository owner(s) listed in the code-signing policy.
7. Every signing request requires manual approval in SignPath.
8. The repository publishes the proposed policy paths:
   - `SECURITY.md`;
   - `PRIVACY.md`;
   - `docs/CODE_SIGNING.md`;
   - a README/release-page link headed “Code signing policy.”
9. The policy includes exactly:

   > Free code signing provided by SignPath.io, certificate by SignPath Foundation.

10. The privacy policy states that WinMint transfers no information to networked systems unless requested by the operator, then enumerates requested network operations such as GitHub release download, package resolution/install, and Microsoft/WinGet/Scoop endpoints.
11. The download/release page describes elevated Source ISO mutation, unattended install behavior, destructive WinPE disk application, and the absence of an installed WinMint service to uninstall.

“No uninstall” is truthful because the host toolkit is portable and the guest Supervisor erases itself; documentation must explain removal rather than invent an uninstaller.

## Proposed SignPath configuration

Request these names, then record the provider-assigned values:

```text
Project slug:                winmint
Artifact configuration slug: winmint-release
Signing policy slug:         release-signing
```

The provider-assigned organization ID is stored as GitHub environment variable:

```text
SIGNPATH_ORGANIZATION_ID
```

The project/artifact/policy slugs are repository environment variables:

```text
SIGNPATH_PROJECT_SLUG=winmint
SIGNPATH_ARTIFACT_CONFIGURATION_SLUG=winmint-release
SIGNPATH_SIGNING_POLICY_SLUG=release-signing
```

The submitter API token is the GitHub `release-signing` environment secret:

```text
SIGNPATH_API_TOKEN
```

The token has submitter permission for only project `winmint` and policy `release-signing`. It cannot approve requests. SignPath keeps certificate/private-key control; no PFX or certificate password exists in GitHub.

If the accepted SignPath tier supports repository source/build policy files, use the proposed path:

```text
.signpath/policies/winmint/release-signing.yml
```

Require GitHub-hosted runners and disallow reruns if SignPath enables those policy controls for the accepted subscription. Do not commit provider-specific policy syntax until the accepted schema validates it. Add branch-ruleset requirements only if the repository enforces them.

## Artifact classes

### Sign with the WinMint policy

Sign only files produced from WinMint-owned source:

- `bin\cli\WinMint.Cli.exe`
- `bin\cli\WinMint.Contracts.dll`
- `bin\cli\WinMint.Orchestrator.dll`
- `bin\wizard\WinMint.Wizard.exe`
- `bin\wizard\WinMint.Contracts.dll`
- `bin\wizard\WinMint.Orchestrator.dll`
- `artifacts\provisioning\WinMint.Provisioning.exe`
- any release rename/copy of that executable such as `Supervisor.exe`
- any WinMint-owned PE added later whose assembly name begins `WinMint.`
- every repository-owned `.ps1` copied into the release staging tree, if `.ps1` signing is confirmed
- the proposed versioned release copy of `winmint.ps1`, if `.ps1` signing is confirmed

Duplicate WinMint assemblies in separate host publish trees are all signed.

### Preserve, inspect, never re-sign

- .NET runtime files;
- `System.CommandLine`;
- Avalonia and CommunityToolkit;
- Microsoft.Windows.SDK.NET, CsWin32 outputs, WinRT.Runtime;
- any other NuGet/upstream EXE or DLL;
- Microsoft files copied from Source ISO or ADK.

The release check records upstream signature status but does not fail merely because an upstream OSS library is unsigned. It fails if any upstream byte changes between unsigned inventory and final verification.

### Hash/provenance only

- ZIP archives;
- `.sha256` files;
- Output ISO;
- CMD/batch files;
- JSON/config/Profile files;
- Justfile, docs, and samples;
- PDB, `.deps.json`, `.runtimeconfig.json`;
- `evidence.json` and logs.

Do not add catalog/MSIX signatures merely to cover these formats. The final release manifest and ZIP digest cover bytes within the accepted container gap.

## Proposed artifact-configuration enforcement

After acceptance, derive `winmint-release` from an uploaded sample of the unsigned GitHub Actions artifact. Configure the ZIP root to sign only accepted formats and paths:

```text
bin/cli/WinMint.*.exe
bin/cli/WinMint.*.dll
bin/wizard/WinMint.*.exe
bin/wizard/WinMint.*.dll
artifacts/provisioning/WinMint.Provisioning.exe
**/*.ps1
```

These are paths relative to the release staging root. If GitHub's uploaded artifact sample adds a wrapper directory, the generated SignPath configuration must include that observed directory rather than assuming its name. The `.ps1` pattern is conditional on provider confirmation. The configuration explicitly excludes non-`WinMint.*` PE files. A pre-submit allowlist generated by the repository is the first defense; SignPath artifact restrictions are the second.

Request these file-metadata restrictions for every signed PE and adjust only if SignPath's accepted schema requires a different field name:

```text
ProductName = WinMint
CompanyName = WinMint contributors
ProductVersion = release semantic version without leading v
FileVersion = four-part numeric release version
```

File descriptions may identify Cli, Wizard, Orchestrator, Contracts, and Provisioning Supervisor. All signed PEs in one request use the same ProductVersion.

PowerShell files have no equivalent version resource. Their final hashes and source-relative paths are recorded.

## Version identity

Release tags must match:

```text
vMAJOR.MINOR.PATCH
```

No floating/latest version is supplied to build metadata.

For tag `v1.2.3`:

```text
Version=1.2.3
VersionPrefix=1.2.3
FileVersion=1.2.3.0
AssemblyVersion=1.2.0.0
InformationalVersion=1.2.3+0123456789abcdef0123456789abcdef01234567
RepositoryCommit=0123456789abcdef0123456789abcdef01234567
RepositoryUrl=https://github.com/yanai-sh/winmint
Product=WinMint
Company=WinMint contributors
```

The release script rejects a tag that does not point at the checked-out commit or does not match this grammar. AssemblyVersion remains major/minor-compatible while ProductVersion/FileVersion identify the release.

## Target release ordering

The current `.github/workflows/release.yml` workflow is named `release` and has one `pack` job. It builds, packages, and publishes through `tools/release/Compress-WinMintRelease.ps1`. After acceptance, replace that path with:

```text
tag checkout
→ restore/build/test/check
→ publish unsigned staging tree
→ validate ownership + PE metadata
→ write unsigned-manifest.json
→ upload immutable GitHub Actions artifact
→ submit SignPath request
→ manual SignPath approval
→ download deep-signed staging tree
→ verify signatures, timestamps, metadata, and no upstream re-signing
→ write release-manifest.json
→ create final ZIP
→ compute final ZIP SHA-256
→ create GitHub artifact attestation for final ZIP
→ publish ZIP, SHA-256, manifests, and attestation link to GitHub Release
```

Tests run before submission so untested bytes are not signed. No build step runs after SignPath returns the staged tree. Final packaging may change only container bytes and add final manifests; it cannot modify signed files.

The unsigned manifest contains:

```text
schema, tag, version, commit, workflow repository/run/attempt,
path, ownership class, unsigned SHA-256, length, PE metadata
```

The final release manifest contains:

```text
schema, tag, version, commit, workflow run URL,
SignPath project/policy/request ID/request URL,
expected publisher, timestamp requirement,
path, ownership class, unsigned SHA-256, final SHA-256,
signature status, signer subject, timestamp status,
final ZIP SHA-256
```

Because the final ZIP hash cannot be embedded inside itself, `release-manifest.json` inside the ZIP omits `final ZIP SHA-256`; the separately published manifest adds it. The two documents share all per-file entries and have distinct `scope` values (`payload` and `release-assets`).

## GitHub workflow security

- Pin every action to a full commit SHA, including SignPath and provenance actions.
- Workflow top-level default is `contents: read`.
- Build job has only `contents: read`.
- Signing job has `actions: read`, `contents: read` and access to the `release-signing` environment.
- Publish/attestation job has only `contents: write`, `id-token: write`, and `attestations: write`.
- Never expose `SIGNPATH_API_TOKEN` to build/test scripts or pull-request workflows.
- Never sign pull-request, branch, manually supplied path, or rerun artifacts.
- Signing accepts only the artifact ID output by the same workflow's upload step.
- Set `wait-for-completion: true`; a timeout/denial fails closed.
- Concurrency remains one run per tag and does not cancel in progress.
- GitHub Release creation occurs only after all verification succeeds.

The SignPath connector verifies the artifact was produced/stored by GitHub Actions and obtains origin metadata from GitHub. For Foundation OSS, all jobs leading to signing must run on GitHub-hosted agents.

## Signature verification

Verification runs in native ARM64 PowerShell. Require both `RuntimeInformation.OSArchitecture` and `RuntimeInformation.ProcessArchitecture` to equal `Arm64`; record `PROCESSOR_ARCHITECTURE` and `PROCESSOR_ARCHITEW6432` for diagnostics. Resolve the Windows SDK ARM64 `signtool.exe` from the installed SDK root/version and reject x64 emulation.

For every required signed PE:

1. `Get-AuthenticodeSignature` status is `Valid`.
2. signer certificate subject matches the subject confirmed from the accepted sample.
3. certificate chain builds with online revocation checking.
4. timestamp verification uses the method confirmed by SignPath for the accepted signing policy.
5. `signtool verify /pa /all /v $file` succeeds.
6. PE ProductName/ProductVersion/CompanyName match policy.
7. final hash differs from unsigned hash and matches final manifest.

For every upstream PE:

1. final hash equals unsigned hash;
2. any existing valid publisher signature remains valid.

For hash/provenance-only files, final hash must equal unsigned hash unless the release manifest explicitly classifies it as generated after signing.

If `.ps1` signing is accepted, verify scripts with `Get-AuthenticodeSignature`, an explicit chain build, and the provider-confirmed timestamp method. Do not assume `signtool verify` is the script verifier.

Any missing, invalid, unexpected, wrong-publisher, wrong-version, newly added, or modified-outside-policy file fails the release. Reject multiple signatures only if the accepted artifact policy forbids them.

## Bootstrap verification

The archive SHA-256 check remains required, but it is not the publisher trust root because ZIP and `.sha256` are served by the same GitHub release.

After extraction and before launching WinMint or invoking a toolkit PowerShell helper, `winmint.ps1`:

1. loads the payload release manifest;
2. requires its tag/version to match the selected GitHub release;
3. enumerates rather than trusts the manifest's file list;
4. verifies every WinMint-owned PE and every shipped `.ps1` required by the accepted signing policy;
5. requires the accepted signer identity, valid Authenticode status, and matching final hashes;
6. rejects extra unsigned WinMint-owned PE/PowerShell files in executable locations;
7. verifies hash-only files against the payload manifest;
8. refuses launch on any discrepancy and reports a non-retryable integrity failure.

`-Force` may redownload but may not bypass signature checks. There is no insecure switch.

The `irm ... | iex` bootstrap command cannot authenticate the bootstrap script itself: piping text into `Invoke-Expression` discards Authenticode file semantics. The canonical signed-release guidance therefore downloads the versioned `winmint.ps1` to a file, verifies it against the accepted signer, then executes it with `pwsh -File`. The short web bootstrap may remain documented as HTTPS/repository trust convenience, but must disclose that weaker initial trust.

## Output ISO and guest trust

The Output ISO is never called Authenticode-signed.

Its evidence is:

- `digests.outputIso.sha256` in build evidence;
- operator verification against the built file;
- Gate B and Primary acceptance.

A future release manifest may bind the compiler/toolkit release identity to the build record. #112 does not make the ISO container signed or establish Microsoft authorship.

The signed release stages `artifacts\provisioning\WinMint.Provisioning.exe`; ImageServicing copies it into the guest as `Supervisor.exe`. Renaming does not change its bytes. Servicing must not rewrite signed PowerShell/PE bytes after signing. Generated Profile, unattend, CMD, and evidence files remain hash/provenance artifacts.

Secure Boot validates the signatures in the boot chain, including the preserved Microsoft-signed boot components. It does not authenticate WinMint's ISO container. Signing WinMint does not change that contract.

## Failure policy

- Build/test failure: no signing request.
- SignPath rejection/timeout/unavailability: no “signed” release; preserve diagnostic artifact for maintainers, do not publish it as a release.
- Manual approval denied: no release.
- Verification failure: quarantine signed artifact as workflow-only evidence, no final package/release.
- Final package/hash/attestation failure: no release.
- GitHub upload partially succeeds: mark/delete the draft release before retry; never leave a release that appears complete without all required assets.
- Timestamp service failure or absent timestamp: fail.
- SignPath certificate/policy revoked: stop new releases and execute the incident runbook.

No automatic unsigned fallback occurs in a signing-enabled tagged workflow. Maintainers may intentionally publish an unsigned release only through a separately named/manual process whose title and notes say **UNSIGNED** and whose bootstrap refuses to treat it as signed.

## Revocation and withdrawal

On suspected key/service/pipeline compromise, malicious release, or SignPath notification:

1. disable the release workflow/environment secret;
2. notify SignPath and request project/policy suspension and certificate/request revocation as advised;
3. remove affected GitHub release assets or mark releases withdrawn;
4. publish a GitHub Security Advisory when user action is warranted;
5. record affected tags, commits, SignPath request IDs, hashes, and timestamps;
6. update bootstrap denylist metadata for known affected release hashes/request IDs;
7. rotate the SignPath API token and review GitHub/SignPath audit logs;
8. correct the pipeline/source and obtain explicit approval before resuming.

Revocation cannot erase already downloaded bytes. Bootstrap checks revocation online and fails closed when chain status is unavailable during a new install; an explicit offline installation flow may use pinned release manifests only after a separate design.

## Accepted gaps

- The final ZIP is unsigned; inner executable/script signatures plus ZIP hash/provenance are the chosen model.
- JSON/CMD/ISO cannot carry the selected Authenticode policy.
- GitHub hosts ZIP, checksum, and manifest, so hashes alone do not survive total GitHub release compromise.
- The SignPath Foundation subject identifies the certificate holder, not a unique WinMint legal entity.
- SmartScreen and antivirus behavior are not controlled by the signature.
- The short `irm | iex` bootstrap has weaker initial trust than downloaded-file verification.
- SignPath availability and eligibility are external dependencies.

These gaps are disclosed, not papered over with “fully signed release” language.

## Acceptance

- SignPath accepts and configures the project/policy/artifact configuration.
- All prerequisites/policies are public and linked.
- Two consecutive tag releases pass the protected workflow.
- Every required WinMint PE verifies with the accepted SignPath Foundation identity and timestamp policy.
- Every required PowerShell file verifies under the same policy, or the design is revised before enabling signed releases if SignPath does not support it.
- No upstream binary hash changes across signing.
- Final ZIP, checksum, manifests, SignPath request link, and GitHub attestation are published.
- Bootstrap rejects tampered ZIP, manifest, PE, and PowerShell files before launch.
- Bootstrap rejects a validly signed file from a different publisher and rejects a manifest with the wrong SignPath project/request context.
- Native ARM64 release artifacts run through existing CLI/Wizard/Test checks.
- Documentation makes no warning-free, Microsoft-endorsed, signed-ISO, or EV-reputation claim.

