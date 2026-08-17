# Warm-media benchmark record

Fill this from `just bench-prepared-media 'C:\path\Source.iso' 'C:\path\to\baseline'` on the native ARM64 host. Do not state a speedup until the JSON record exists.

## Host

- WinMint commit: a50dd096cb28096c2c8408940a84a42abae392f7 (bench origin); this record commit includes `tools/bench/Measure-WarmMedia.ps1` harden (StrictMode-safe #94 evidence fields, incremental JSON write, `baselineCommit`)
- Windows version: Windows 11 Home 10.0.26200 ARM64
- pwsh / .NET: pwsh 7.6.4 / .NET 11.0.100-preview.6.26359.118
- Filesystem / storage: NTFS on NVMe SSD (HFS001TEJ3X108N-SKhynix), C: ~952 GB
- Source ISO SHA-256: 638aa2c88e94385b00f4f178d071e3df0b7d9e335577a83bd533b7f2eb65adf0
- Profile / WIM index: samples/smoke.profile.json / 3

## Matrix

| series | n | median ms | range ms |
| --- | ---: | ---: | ---: |
| new cold | 5 | 788238 | 765689–954835 |
| new warm | 5 | 521735 | 508514–623554 |
| #94 cold baseline | 5 | 718469 | 690188–731239 |

Prepared `install.wim` / `boot.wim` hashes unchanged: yes

Warm samples (all `hit`) share install.wim `21e965c8c0756754b943f475ae6c523ca5b644d924f6ce8d4bb1d8265ce3bcf1` and boot.wim `50f861f68052c38d4813d770d032857968ef11cb94279676c32943830f159d07`.

#94 baseline: 6aa3bc87563b191e8acea5d2943054513b2f42f0 at `C:\Users\yanai\Projects\winmint-94-baseline`. ReFS clone stays deferred.

JSON: `docs/evidence/warm-media-benchmark.json`
