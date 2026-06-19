# Hyper-V VM Acceptance

This runbook is the WinMint acceptance gate **before** real hardware (see
`docs/Hardware-Acceptance.md`). It proves that a build goes end to end — build the
ISO, install it unattended in a Hyper-V VM, and let FirstLogon complete — and that
the run leaves reusable evidence behind.

It is deliberately thin. The harness sequences small, single-purpose scripts; it is
not a framework. Do not add an evidence-package schema or a phase-journal engine
until repeated real runs show concrete pain (roadmap Track B2/D4).

## One-command acceptance

```powershell
# Elevated PowerShell. Builds, boots, waits for FirstLogon, inspects, scores.
pwsh -NoProfile -File .\tools\vm\Invoke-WinMintVmAcceptance.ps1 `
    -ProfilePath .\tests\profiles\hyper-v-install-arm64.json
```

The pass requires a **Pro**, fully-unattended **Local-account** profile (the VM
invariant): PowerShell Direct must be able to sign in, so the profile needs
`identity.accountName` and `identity.password`. The guest architecture follows the
host, so run on the same architecture as the ISO.

Output: an evidence folder under `output\vm-acceptance\<VMName>-<stamp>\` containing
the pulled guest logs, the agent `state.json`, the host build artifacts, and a
single `acceptance-result.json` verdict (`pass`/`fail`). A failed pass exits 1.

## Steps and ownership

`Invoke-WinMintVmAcceptance.ps1` is the orchestrator. It runs four steps,
delegating to the existing single-purpose scripts. Pass `-SkipBuild` to attach to
an already-running VM (wait/score/collect evidence without rebuilding); the wait
step is idempotent and returns fast when FirstLogon has already completed.

| Step | Owns | Delegates to |
|------|------|--------------|
| Build + boot | Validate the profile, free host RAM, build the ISO, create + boot a Gen 2 (UEFI + Secure Boot + vTPM) VM | `Build-And-TestVm.ps1` → `Test-WinMintHyperVProfile.ps1`, `WinMint-CLI.ps1 build`, `New-WinMintTestVm.ps1` |
| Wait | Poll guest `%LOCALAPPDATA%\WinMint\state.json` over PowerShell Direct until `run.status` is terminal (`ok`/`failed`); the first reachable call confirms install + autologon | PowerShell Direct (in-script) |
| Inspect | Capture live desktop / Terminal acceptance signals (read-only, best-effort) | `Invoke-WinMintGuestAcceptance.ps1` |
| Evidence | Pull guest logs + `state.json`, copy host `BuildManifest`/`BuildDelta`/`BuildProfile`, write `acceptance-result.json`, print the verdict | PowerShell Direct (in-script) |

### Supporting scripts (not phases)

| Script | Owns |
|--------|------|
| `New-WinMintHyperVProfile.ps1` | Author a Hyper-V-valid profile (Pro, Pro generic key, unattended local account) |
| `Push-WinMintSetupScripts.ps1` | Fast-iterate `setup`/`firstlogon` code into a **running** guest over PowerShell Direct (~30s) instead of a full rebuild; pull logs back |
| `Invoke-EdgeDmaAppxRemovalVmTest.ps1` / `Test-EdgeDmaAppxRemoval.ps1` | A specific empirical experiment (Edge DMA AppX removal across reboot), not part of the standard acceptance pass |

## Verdict contract

`acceptance-result.json` is a flat record (intentionally not a formal schema yet):

- `verdict` — `pass` only when the guest was reachable **and** FirstLogon reached
  `run.status = 'ok'`. FirstLogon warning steps are a pass with a noted reason.
- `firstLogon` — `status`, `exitCode`, `completedAt`, `failedSteps`, `warningSteps`,
  `rebootPending`, mirrored from the guest agent `state.json`.
- `inspect` — the live desktop signals from the inspector (best-effort; a failure
  here is non-fatal and recorded in `reasons`).
- `reasons` — human-readable notes explaining the verdict.

## When acceptance is "green enough"

Per the roadmap, physical installs (Track B) stay deferred until this pass is
credible: a clean `pass` for the ARM64 VM profile, FirstLogon completing without
blocking failures, and an evidence folder a maintainer can read. Promote to
hardware only after that.
