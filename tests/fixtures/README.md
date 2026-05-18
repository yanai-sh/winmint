# Test Fixtures

This directory is the canonical local fixture root for tests and UI audit runs.
Each child directory keeps its own `.gitignore` so large or licensed payloads
stay local to the developer machine.

Small reusable `BuildProfile.json` fixtures live in `tests\profiles\`; the large
payloads they reference live here and remain ignored.

Use:

- `iso\` for Windows ISO/WIM/ESD/SWM fixture media.
- `drivers\` for driver folders, `.inf` trees, driver MSI files, and driver ZIPs.
- `uupdump\` for UUP Dump conversion zips and UUP-produced ISO fixtures.

Do not put fixture payloads under `assets\`, because `assets\` is product
payload, not test input.
