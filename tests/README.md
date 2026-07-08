# WinMint Tests

This folder contains contract tests, small profile fixtures, and ignored local
fixture roots for large payloads.

```text
tests/
|-- contract/
|-- integration/
|-- setup-shell/
|-- profiles/
`-- fixtures/
    |-- iso/
    |-- drivers/
    |-- setup-shell/
```

- `contract\`: PowerShell smoke and contract tests.
- `setup-shell\`: native host integration tests (`Test-WinMintSetupShell.ps1`).
- `integration\`: manual desktop integration tests (provisioning lock preview).
- `profiles\`: small checked-in `BuildProfile.json` fixtures (including Hyper-V
  acceptance profiles: `hyper-v-install-arm64.json` full gate,
  `hyper-v-smoke-arm64.json` lean gate). Smoke keeps WSL enabled in the profile but
  the agent skips WSL runtime validation when `profileName` is `Hyper-V Smoke`.
- `fixtures\iso\`: ignored local Windows ISO/WIM/ESD/SWM media.
- `fixtures\drivers\`: ignored local `.inf`, `.msi`, and driver ZIP payloads.

Hyper-V VM acceptance is local-only (requires Hyper-V + a source ISO). See
`docs/VM-Acceptance.md` for the iteration decision tree, smoke vs full profiles,
composable phases, and checkpoint/push workflows.

Do not commit Microsoft media, driver bundles, UUP conversion output, or scratch
payloads.
