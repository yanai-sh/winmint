# WinWS Tests

This folder is the repository home for test assets and future test suites.

Current PowerShell smoke-test entrypoints remain under `scripts\test\` so the
documented commands keep working while the repo migrates incrementally. New local
fixtures belong under `tests\fixtures\`, not under `input\`, `output\`, `assets`,
or ad hoc scratch folders.

## Fixture Layout

```text
tests/
`-- fixtures/
    |-- iso/
    |-- drivers/
    `-- uupdump/
```

- `fixtures\iso\`: local Windows ISO/WIM/ESD/SWM media used by UI and CLI tests.
- `fixtures\drivers\`: local driver fixture payloads such as `.inf` folders,
  vendor `.msi` files, or driver `.zip` archives.
- `fixtures\uupdump\`: local UUP Dump zip files, untouched recipe folders,
  downloaded folders, converted folders, and final ISO outputs used to exercise
  source-prep detection.

Fixture payloads are intentionally gitignored. Keep only small documentation or
test metadata in git.
