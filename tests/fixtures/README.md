# Test Fixtures

This directory is the canonical local fixture root for tests and UI audit runs.
Each child directory keeps its own `.gitignore` so large or licensed payloads
stay local to the developer machine.

Use:

- `iso\` for Windows ISO/WIM/ESD/SWM fixture media.
- `drivers\` for driver folders, `.inf` trees, driver MSI files, and driver ZIPs.
- `uupdump\` for UUP Dump zips, recipe folders, downloaded folders, converted
  folders, and prepared ISOs.

Do not put fixture payloads under `assets\`, because `assets\` is product
payload, not test input.
