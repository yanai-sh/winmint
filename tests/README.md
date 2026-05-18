# WinMint Tests

This folder is the repository home for test assets and future test suites.

Current PowerShell smoke-test entrypoints remain under `tests\contract\` so the
documented commands keep working while the repo migrates incrementally. New local
fixtures belong under `tests\fixtures\`, not under `input\`, `output\`, `assets`,
or ad hoc scratch folders.

## Fixture Layout

```text
tests/
|-- profiles/
`-- fixtures/
    |-- iso/
    |-- drivers/
    `-- uupdump/
```

- `profiles\`: small checked-in `BuildProfile.json` fixtures that reference local
  fixture payload paths.
- `fixtures\iso\`: local Windows ISO/WIM/ESD/SWM media used by UI and CLI tests.
- `fixtures\drivers\`: local driver fixture payloads such as `.inf` folders,
  vendor `.msi` files, or driver `.zip` archives.
- `fixtures\uupdump\`: local UUP Dump conversion zip files and final ISO outputs
  produced by UUP Dump. Converted folders are intentionally not a WinMint input;
  use the generated ISO with `-SourceIso`.

Fixture payloads are intentionally gitignored. Keep only small documentation or
test metadata in git.
