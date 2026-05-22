# WinMint Tests

This folder contains contract tests, small profile fixtures, and ignored local
fixture roots for large payloads.

```text
tests/
|-- contract/
|-- profiles/
`-- fixtures/
    |-- iso/
    |-- drivers/
    `-- uupdump/
```

- `contract\`: PowerShell smoke and contract tests.
- `profiles\`: small checked-in `BuildProfile.json` fixtures.
- `fixtures\iso\`: ignored local Windows ISO/WIM/ESD/SWM media.
- `fixtures\drivers\`: ignored local `.inf`, `.msi`, and driver ZIP payloads.
- `fixtures\uupdump\`: ignored local UUP Dump zips and UUP-produced ISO fixtures.

Do not commit Microsoft media, driver bundles, UUP conversion output, or scratch
payloads.
