# Test Profiles

Reusable local profile contracts for backend and CLI smoke tests.

- `official-base-arm64.json` uses the official/base ARM64 ISO fixture under `tests/fixtures/iso`.
- `hyper-v-install-arm64.json` is a VM-compatible ARM64 copy of the Surface Laptop 7 UUP profile: same ARM64 source plus Developer/CopilotPlus posture, but no host driver export and a clean VM disk install flow.
- `surface-laptop-7-uupdump-arm64.json` uses the UUP-produced ARM64 ISO fixture intended for the Surface Laptop 7 install path.

The profiles are small and tracked. The ISO payloads they reference stay ignored
under `tests/fixtures/`.
