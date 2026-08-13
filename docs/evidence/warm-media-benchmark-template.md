# Warm-media benchmark record

Fill this from `just bench-warm-media SOURCE_ISO=... BASELINE=...` on the native ARM64 host. Do not state a speedup until the JSON record exists.

## Host

- WinMint commit:
- Windows version:
- pwsh / .NET:
- Filesystem / storage:
- Source ISO SHA-256:
- Profile / WIM index:

## Matrix

| series | n | median ms | range ms |
| --- | ---: | ---: | ---: |
| new cold | 5 |  |  |
| new warm | 5 |  |  |
| #94 cold baseline | 5 |  |  |

Prepared `install.wim` / `boot.wim` hashes unchanged: yes / no

JSON: `docs/evidence/warm-media-benchmark.json`
