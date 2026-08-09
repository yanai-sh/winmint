# Research: Modern `%USERPROFILE%\.wslconfig` (August 2026)

**Date:** 2026-08-09  
**Question:** What should a sane, modern `%USERPROFILE%\.wslconfig` contain in August 2026 — especially for WinMint (Windows 11 ISO builder, ARM64-first, metal WSL install jobs): official key inventory, stable vs experimental vs deprecated, recommendations for a fresh Win11 Pro ARM64 laptop used primarily for WSL development, `sparseVhd` / `--allow-unsafe` caveats for new distros, Dev Drive / ReFS interaction, minimal product-owned staging vs leave-alone, and exact syntax for 256 GiB `defaultVhdSize`?  
**Method:** Primary sources only as evidence — Microsoft Learn WSL docs (`wsl-config`, `disk-space`, `networking`, Dev Drive), MicrosoftDocs/WSL Git source (`ms.date` on tip), microsoft/WSL GitHub (releases, issues, maintainer comments). Third-party inventories mentioned only to flag non-authoritative extras. Fetched 2026-08-09.

## Executive summary

Official `.wslconfig` still has **two sections only**: `[wsl2]` (main / stable-ish) and `[experimental]` (opt-in previews). There is **no newer official section** in Learn as of doc tip `ms.date: 04/15/2026`. Many networking keys that used to live under `[experimental]` are now documented under `[wsl2]` with Win11 22H2+ footnotes; `bridged` networking and `pageReporting` are deprecated/removed. Default VHD ceiling is **1 TiB** (`1099511627776` bytes); size values accept **`MB`/`GB`/`TB` unit suffixes** (binary scale matching that default).

**`sparseVhd` remains experimental and is not safe for product defaults.** Docs still describe “new VHDs become sparse when `sparseVhd=true`,” but current WSL builds **disable sparse creation** with an explicit corruption warning and require `wsl --manage <Distro> --set-sparse true --allow-unsafe` to force it — including when the setting was already enabled in `.wslconfig` / WSL Settings before install. Microsoft still treats sparse as quality-gated opt-in (open feature request through 2026-07).

**Minimal WinMint-owned file:** create-if-absent only when Profile selects any WSL distro; set **`defaultVhdSize=256GB`** only; **omit** `memory`/`processors`/`swap` (WSL already scales those to the booted machine). Leave experimental/sparse/Dev Drive alone.

**Recommended full (personal) file:** pin the **stable modern networking suite** + `defaultVhdSize=256GB`; still no RAM/CPU pins and no experimental keys (see §11-B). Many of those networking keys already default on Win11 22H2+ — setting them documents intent and survives doc/default drift.

**Experimental caveats (Aug 2026):** `sparseVhd` is quality-blocked / needs `--allow-unsafe`; `autoMemoryReclaim=gradual` has hang history with systemd/Docker; mirrored companions (`hostAddressLoopback`, `ignoredPorts`) must stay under `[experimental]` and only with `networkingMode=mirrored`. Full dive: §10; files: §11.

## Sources (primary)

| Source | As-of / notes |
| --- | --- |
| [Advanced settings configuration in WSL](https://learn.microsoft.com/en-us/windows/wsl/wsl-config) | Learn page; Git tip `WSL/wsl-config.md` **`ms.date: 04/15/2026`** ([raw](https://raw.githubusercontent.com/MicrosoftDocs/WSL/main/WSL/wsl-config.md), [blob](https://github.com/MicrosoftDocs/WSL/blob/main/WSL/wsl-config.md)) |
| [How to manage WSL disk space](https://learn.microsoft.com/en-us/windows/wsl/disk-space) | Learn; Git `ms.date: 02/05/2025`; Learn `updated_at` ~2026-06-02 |
| [Accessing network applications with WSL](https://learn.microsoft.com/en-us/windows/wsl/networking) | Learn; Git `ms.date: 07/16/2024` (mirrored / DNS tunneling / autoProxy guidance) |
| [Set up a Dev Drive on Windows 11](https://learn.microsoft.com/en-us/windows/dev-drive/) | FAQ: WSL + Dev Drive / ReFS `metadata` |
| [microsoft/WSL releases](https://github.com/microsoft/WSL/releases) | Latest sampled: **2.7.11** (2026-07-24), **2.9.4** (2026-07-13) |
| [WSL #13241](https://github.com/microsoft/WSL/issues/13241) | Sparse default proposal; Craig Loewen (MSFT) 2025-07-14; still open 2026-07-13 |
| [WSL #13075](https://github.com/microsoft/WSL/issues/13075) / [PR #13512](https://github.com/microsoft/WSL/pull/13512) | Sparse disabled; correct `--set-sparse true --allow-unsafe` prompt |
| [WSL #12103](https://github.com/microsoft/WSL/issues/12103) | Install-time sparse disable notice even with `sparseVhd=true`; reports that config is ignored on newer builds |
| [WSL #10609](https://github.com/microsoft/WSL/issues/10609) | Corruption reports associated with sparse (user/thread evidence) |
| [WSL #13261](https://github.com/microsoft/WSL/issues/13261) + MicrosoftDocs commits 2025-09-16 | `pageReporting` deprecated / removed from docs |
| Docs blog link (historical): [Automatically Configuring WSL](https://devblogs.microsoft.com/commandline/automatically-configuring-wsl/) | Introduces **`wsl.conf`**, not modern `.wslconfig` inventory |

## Findings

### 1. What `.wslconfig` is

From Learn / `wsl-config.md`:

- Path: `%UserProfile%\.wslconfig` (e.g. `C:\Users\<User>\.wslconfig`).
- **Does not exist by default**; must be created.
- Global settings for **all WSL 2** distros (WSL 1 unaffected).
- Requires Windows Build **19041+** for global `.wslconfig`.
- Malformed/missing file → WSL still launches without those settings.
- Apply changes with `wsl --shutdown` (or wait for idle stop / “8 second rule”).
- Tip: WSL Settings GUI is preferred for interactive edits; agents/products still own the file for deterministic staging.

### 2. Official inventory — `[wsl2]` (as of `ms.date: 04/15/2026`)

Authoritative table: Learn “Main WSL settings” / Git `wsl-config.md` section **Main WSL settings**.

| Key | Value type | Default | Meaning (short) | Footnotes |
| --- | --- | --- | --- | --- |
| `kernel` | path | Inbox Microsoft kernel | Custom Linux kernel (Windows path, escaped `\`) | |
| `kernelModules` | path | (custom modules VHD path) | Custom kernel modules VHD | |
| `memory` | size | **50% of Windows total memory** | WSL 2 VM RAM cap | |
| `processors` | number | **Same as Windows logical processors** | VM vCPU count | |
| `localhostForwarding` | bool | `true` | Host `localhost:port` → WSL wildcard/localhost binds; **ignored when `networkingMode=mirrored`** (example comment) | |
| `kernelCommandLine` | string | None | Extra kernel cmdline | |
| `safeMode` | bool | `false` | Recover-oriented “Safe Mode”; Win11 + WSL **0.66.2+** | |
| `swap` | size | **25% of Windows memory**, rounded up to nearest GB | Swap size; `0` = no swap | |
| `swapFile` | path | `%Temp%\swap.vhdx` | Swap VHD path | |
| `guiApplications` | bool | `true` | WSLg GUI apps | |
| `debugConsole` | bool | `false` | `dmesg` console on start | ¹ Win11 |
| `maxCrashDumpCount` | number | `10` | Retained crash dumps | |
| `nestedVirtualization` | bool | `true` | Nested VMs inside WSL 2 | ¹ Win11 |
| `vmIdleTimeout` | number | `60000` | Idle ms before VM shut down | ¹ Win11 |
| `dnsProxy` | bool | `true` | **NAT only**: DNS via NAT vs mirror Windows DNS when `false` | |
| `networkingMode` | string | `NAT` | `none` \| `nat` \| `bridged` (**deprecated** since WSL **2.4.5**) \| `mirrored` \| `virtioproxy`. Unknown/`nat` → NAT; from **2.3.25**, NAT failure falls back to VirtioProxy | ¹² Win11 22H2+ |
| `firewall` | bool | `true` | Windows Firewall + Hyper-V rules filter WSL traffic | ¹² |
| `dnsTunneling` | bool | `true` | DNS via virt path instead of network packets (VPN-friendly) | ¹² |
| `autoProxy` | bool | `true` | Use Windows HTTP proxy info in WSL | ¹ Win11 |
| `defaultVhdSize` | size | **`1099511627776` (1 TB)** | Max size of distro `ext4.vhdx` | |

**Size syntax (official):** “Entries with the `size` value default to B (bytes), and the unit is omissible. To use other units, the size unit must be appended, e.g.: `8GB` or `512MB`.” Disk-space resize docs also list forms `B/M/MB/G/GB/T/TB` (no decimals like `2.5TB`).

**Path syntax:** escaped Windows paths, e.g. `C:\\Temp\\myCustomKernel`.

¹ Windows 11 only. ² Windows 11 **22H2+**.

### 3. Official inventory — `[experimental]` (same doc)

Docs: “opt-in previews of experimental features that we aim to make default in the future.”

| Key | Value type | Default | Meaning (short) | Footnotes |
| --- | --- | --- | --- | --- |
| `autoMemoryReclaim` | string | **`dropCache`** | `disabled` \| `gradual` \| `dropCache` (unknown → dropCache). Reclaim cached memory to Windows | |
| `sparseVhd` | bool | **`false`** | When `true`, **newly created** VHDs set sparse automatically | |
| `bestEffortDnsParsing` | bool | `false` | With `dnsTunneling`: extract DNS question, ignore unknown records | ¹² |
| `dnsTunnelingIpAddress` | string | `10.255.255.254` | Nameserver written to Linux `resolv.conf` when tunneling | ¹² |
| `initialAutoProxyTimeout` | string | `1000` | ms to wait for proxy info at container start | ¹ |
| `ignoredPorts` | string | Null | Mirrored mode: comma-separated ports Linux may bind even if used on Windows | ¹² |
| `hostAddressLoopback` | bool | `false` | Mirrored: allow Host↔Container via host-assigned IPv4 (beyond `127.0.0.1`) | ¹² |

No other `.wslconfig` sections appear in the official Learn inventory. Per-distro knobs (`[boot] systemd`, automount, etc.) belong in **`/etc/wsl.conf`**, not `.wslconfig`.

**Non-authoritative extras:** community references (e.g. GreenGorych) list additional keys (`distributionInstallPath`, `crashDumpFolder`, …). Treat those as **unverified for WinMint** unless they land in MicrosoftDocs/WSL Learn.

### 4. Stable vs experimental vs deprecated (Aug 2026)

| Status | Items |
| --- | --- |
| **Documented under `[wsl2]` (ship / main)** | Memory/CPU/swap/kernel/gui/nestedVirt/idle timeout/crash dumps; networking suite (`networkingMode`, `firewall`, `dnsTunneling`, `autoProxy`, `dnsProxy`, `localhostForwarding`); `defaultVhdSize` |
| **Still `[experimental]`** | `autoMemoryReclaim`, `sparseVhd`, `bestEffortDnsParsing`, `dnsTunnelingIpAddress`, `initialAutoProxyTimeout`, `ignoredPorts`, `hostAddressLoopback` |
| **Promoted historically** | `networkingMode` / `dnsTunneling` / `firewall` / `autoProxy` were introduced under `[experimental]` in early WSL 2.0 era and are **authoritatively under `[wsl2]` now**. Put them under `[wsl2]`. Old files with those keys under `[experimental]` are stale. |
| **Deprecated** | `networkingMode=bridged` — “marked as deprecated since WSL 2.4.5” (Learn table). |
| **Removed / unknown key** | `pageReporting` / `pageReportingOrder` — removed from docs (MicrosoftDocs commits 2025-09-16; product issues e.g. [#13261](https://github.com/microsoft/WSL/issues/13261)). Including them yields `Unknown key 'wsl2.pageReporting'`. |

**Conflict note — `sparseVhd` section:** Official docs place `sparseVhd` **only under `[experimental]`** (example file ends with `[experimental]` / `sparseVhd=true`). Older blogs sometimes showed it under `[wsl2]`. **Authoritative location: `[experimental]`.**

**Conflict note — docs vs runtime for sparse:** Learn still says sparse auto-applies to new VHDs when `sparseVhd=true`. Runtime behavior on current Store WSL (user reports spanning 2.5.x–2.6.x, still relevant at research date) **refuses silent sparse create** and prints the corruption disable message — see §5.

### 5. Spotlight settings — status + recommendations

#### `defaultVhdSize`

- **Status:** Stable `[wsl2]` key.
- **Default:** `1099511627776` bytes = **1024⁴** (docs label “1 TB”). Earlier releases used 512GB / 256GB ceilings ([disk-space](https://learn.microsoft.com/en-us/windows/wsl/disk-space); changed upward by WSL **0.58.0**).
- **Applies at create time** as the VHD **maximum**; dynamic growth still applies within that ceiling.
- **Existing distros:** changing `.wslconfig` does **not** shrink/expand an already-created VHD; use `wsl --manage <Distro> --resize <size>` (WSL **2.5+**) or diskpart/`resize2fs` path in disk-space docs.
- **Laptop rec:** Cap below 1 TiB if you want a fail-earlier ceiling (e.g. 256 GiB product constant). Leaving unset is also sane on large SSDs.

#### Memory / processors / swap

- Defaults: **50% RAM**, **all logical CPUs**, **swap ≈ 25% of Windows memory**.
- **Recommendation:** leave unset in both WinMint product and portable recommended files — that *is* the device-adaptive policy. Do **not** derive values from the WinMint build host.
- A one-off personal pin (e.g. `memory=24GB` on a known 32GB box) is fine locally; it is **not** a template (see §11-D).
- `swap=0` is valid (no swap) but not a product default; avoid on tight hosts when diagnosing reclaim/thrash.

#### Networking (`networkingMode`, `dnsTunneling`, `autoProxy`, `firewall`)

- Defaults on Win11 22H2+: **`NAT`**, with **`dnsTunneling=true`**, **`autoProxy=true`**, **`firewall=true`** already — so an empty `.wslconfig` already gets modern DNS/proxy/firewall behavior.
- Learn **recommends trying mirrored** for IPv6, VPN compatibility, LAN reachability, localhost Host↔WSL ([networking](https://learn.microsoft.com/en-us/windows/wsl/networking)): set under **`[wsl2]`**:
  ```ini
  networkingMode=mirrored
  ```
- Mirrored is **not** the documented default (`NAT` is). Good **user** choice for a WSL-first laptop; optional for product staging (see §8).
- Mirrored companions still experimental: `ignoredPorts`, `hostAddressLoopback`.

#### `autoMemoryReclaim`

- Still **`[experimental]`**, but default is already **`dropCache`** (aggressive reclaim). Explicit `gradual` is a softer opt-in; `disabled` if reclaim fights a workload.
- Product-owned file: **omit** (inherit runtime default).

#### `nestedVirtualization` / `guiApplications`

- Defaults **`true`**. Leave alone unless debugging nested-virt or WSLg issues on a specific ARM64 SKU.

#### `sparseVhd` + `--allow-unsafe`

**Docs claim:** `[experimental] sparseVhd=true` → “any newly created VHD will be set to sparse automatically.”

**Runtime / product reality (Aug 2026):**

1. Microsoft still classifies sparse as **opt-in experimental with ongoing quality issues** — Craig Loewen (MSFT) on [#13241](https://github.com/microsoft/WSL/issues/13241) (2025-07-14): *“we are still seeing quality reports and issues with sparse VHDs and so have made it an opt in experimental feature.”* Thread still open **2026-07-13**.
2. Enabling via `wsl --manage <Distro> --set-sparse true` alone fails with: *“Sparse VHD support is currently disabled due to potential data corruption”* and instructs forcing with `--allow-unsafe` ([#13075](https://github.com/microsoft/WSL/issues/13075); prompt fixed in [PR #13512](https://github.com/microsoft/WSL/pull/13512) to include `true`):
   ```text
   wsl.exe --manage <DistributionName> --set-sparse true --allow-unsafe
   ```
3. **New installs with `sparseVhd=true` already set** still hit the same disable notice at install time; sparse is **not** quietly applied. Repro narrative in [#12103](https://github.com/microsoft/WSL/issues/12103) (2026-04): install prints the corruption message; commenters report `.wslconfig` / Settings sparse **ignored** on newer WSL (cited “since ~2.5.6”), requiring post-install `--allow-unsafe`.
4. Historical corruption / host NTFS damage reports exist when sparse was enabled ([#10609](https://github.com/microsoft/WSL/issues/10609) thread).

**Answer for WinMint:** Yes — as of August 2026, treating sparse as “set in `.wslconfig` before install and forget” is **incorrect**. Expect either no sparse, or an explicit **`--allow-unsafe`** convert after install. **Do not** ship `sparseVhd=true` as a product constant.

### 6. Dev Drive / ReFS vs `.wslconfig`

Primary Dev Drive FAQ ([learn.microsoft.com/windows/dev-drive](https://learn.microsoft.com/en-us/windows/dev-drive/)):

- You **can** access Dev Drive files from WSL, but WSL stores its own filesystem in a **VHD**; best performance is files **inside** the Linux VHD, not on Windows mounts.
- “WSL is out of the scope of Windows file system so you should not expect to see any performance improvement when accessing project files in Dev Drive from a Linux distribution running via WSL.”
- WSL DrvFs **`metadata`** mount option is **not supported on ReFS** (Dev Drive). Prefer NTFS or the WSL VHD for Linux permission metadata workflows.

**No `.wslconfig` key** configures Dev Drive / ReFS. Interaction is mount/`wsl.conf` / workflow, not global VHD config. WinMint “no Dev Drive ownership” matches primary docs: Dev Drive is orthogonal to staging `.wslconfig`.

### 7. Exact 256 GiB `defaultVhdSize` syntax

Given official default `1099511627776` = **1024⁴** labeled “1 TB”, WSL’s `GB`/`TB` suffixes are **1024-based** (binary), not SI decimal.

| Intent | Preferred forms |
| --- | --- |
| 256 GiB ceiling | `defaultVhdSize=256GB` |
| Same in raw bytes | `defaultVhdSize=274877906944` |
| Equivalent powers | `256G` also appears in resize string forms (`B/M/MB/G/GB/T/TB` on disk-space `--resize`) |

**Recommend for WinMint constants:** `defaultVhdSize=256GB` (readable, matches Learn examples like `memory=4GB`). Bytes form is equally valid if you want zero unit ambiguity in parsers.

**Not supported:** fractional sizes like `2.5TB` (explicitly unsupported on `--resize`; avoid in `.wslconfig` too).

### 8. Minimal product-owned `.wslconfig` for WinMint

Constraints from the question: create file only when Profile selects any WSL distro; fixed constants; create-if-absent; no Dev Drive ownership.

| Include | Omit / leave alone |
| --- | --- |
| `[wsl2]` + `defaultVhdSize=256GB` | `memory`, `processors`, `swap`, `swapFile` (**device-relative** — WSL defaults scale to the booted host; never derive from the WinMint *build* host) |
| | `networkingMode` / `dnsTunneling` / `autoProxy` / `firewall` (already good defaults on Win11 22H2+; mirrored is a user preference — OK in personal §11-B, not in product §11-A) |
| | Entire `[experimental]` block |
| | `sparseVhd` (corruption gate / `--allow-unsafe`) |
| | Custom `kernel` / debug / safeMode |
| | Any Dev Drive / install-path ownership |

**Suggested staged content (create-if-absent):**

```ini
# WinMint product defaults — created only when Profile selects WSL.
# Create-if-absent; do not overwrite user customizations.
[wsl2]
defaultVhdSize=256GB
```

**Operational notes for metal FirstLogon WSL jobs:**

- Stage the file **before** `wsl --install` / `--from-file` so the new VHD picks up the size ceiling.
- After edits, ensure WSL is shut down before install if a VM was already warm (`wsl --shutdown`).
- Do not call `--set-sparse` / `--allow-unsafe` from product code.
- Per-distro systemd etc. → guest `/etc/wsl.conf` later if needed; out of `.wslconfig` scope.

### 9. Sane “human laptop” profile (not product-owned)

See **§11-B** — explicit modern networking + WSLg/nestedVirt pins + `defaultVhdSize=256GB`. Still omit RAM/CPU/swap and all experimental keys.

## Implications for WinMint

1. **One constant is enough** for product staging: `defaultVhdSize=256GB` under `[wsl2]`.
2. **Do not set `memory`/`processors`/`swap` from WinMint** — not from the build host (wrong machine) and not via FirstLogon formulas; omission is the device-adaptive policy.
3. **Create-if-absent** avoids clobbering power-user mirrored/memory tuning.
4. **Gate on Profile WSL selection** — Smoke/stub Profiles without `packages.wsl` should not drop a `.wslconfig`.
5. **Sparse is explicitly not a WinMint product seam** until Microsoft lifts the corruption disable / `--allow-unsafe` gate and Learn + runtime agree again.
6. **Dev Drive remains out of scope** for this file; no Learn-documented `.wslconfig` coupling.
7. Keep WSL engine current on metal (`wsl --update`) so keys like `defaultVhdSize` are recognized (older engines logged `Unknown key 'wsl2.defaultVhdSize'` — [Discussion #12168](https://github.com/microsoft/WSL/discussions/12168)).

## 10. Experimental caveats (deep dive, Aug 2026)

Authoritative inventory still lives only under `[experimental]` in Learn (`ms.date` 04/15/2026). Source validation: `WslCoreConfig.cpp` rejects mirrored-only keys unless `NetworkingMode == Mirrored`, and DNS-helper keys unless DNS tunneling is on.

### `sparseVhd` — **do not enable for product or casual defaults**

| Fact | Evidence |
| --- | --- |
| Still experimental; MS wants it default someday but **quality-blocked** | Craig Loewen (MSFT) on [#13241](https://github.com/microsoft/WSL/issues/13241) (2025-07-14); thread still open **2026-07-13** |
| Runtime **disables** silent sparse create with corruption warning | [#13075](https://github.com/microsoft/WSL/issues/13075); force path `wsl --manage <Distro> --set-sparse true --allow-unsafe` ([PR #13512](https://github.com/microsoft/WSL/pull/13512)) |
| `.wslconfig sparseVhd=true` before install is **not** enough on current builds | [#12103](https://github.com/microsoft/WSL/issues/12103) — install still prints disable notice; Settings/config reported ignored since ~2.5.6 |
| Incomplete reclaim story alleged (no `FSCTL_SET_ZERO_DATA` on deallocate) | Comment on [#13241](https://github.com/microsoft/WSL/issues/13241) (2025-11) |
| Historical corruption / host NTFS damage reports | [#10609](https://github.com/microsoft/WSL/issues/10609) thread |

**Caveat summary:** setting the key is aspirational docs; product reality is opt-in + `--allow-unsafe` + backup discipline. Omit entirely unless you accept that.

### `autoMemoryReclaim` — **omit; inherit engine default, or set `disabled` if hurt**

| Fact | Evidence |
| --- | --- |
| Docs default is already **`dropCache`** (aggressive) | Learn experimental table |
| `gradual` historically required cgroup changes; broke in-distro docker daemon; Docker Desktop recommended | [Sep 2023 WSL blog](https://devblogs.microsoft.com/commandline/windows-subsystem-for-linux-september-2023-update/) |
| `gradual` + systemd: command hangs after cache drained | [#10675](https://github.com/microsoft/WSL/issues/10675) |
| `gradual` + Docker Desktop Resource Saver: disk cmds hang until Docker wakes | [#11066](https://github.com/microsoft/WSL/issues/11066) (reports into 2025) |
| Reclaim thrash / NVMe storm hypotheses on tight RAM + `swap=0` | [#40420](https://github.com/microsoft/WSL/issues/40420) (2026) — try `disabled` when diagnosing; not always root cause |

**Caveat summary:** do not *add* `gradual` to a “sane defaults” file. Leaving the key out inherits runtime default (`dropCache` per docs). If you see idle→resume stalls or Docker hangs, set `autoMemoryReclaim=disabled` explicitly and keep non-zero swap.

### `hostAddressLoopback` / `ignoredPorts` — **mirrored-only; wrong section = dead**

| Fact | Evidence |
| --- | --- |
| Only valid when `wsl2.networkingMode=mirrored` | Learn footnotes; `WslCoreConfig.cpp` validates off unless Mirrored |
| Must live under **`[experimental]`**, not `[wsl2]` | [#10965](https://github.com/microsoft/WSL/issues/10965) (`Unknown key 'wsl2.hostAddressLoopback'`); [#11102](https://github.com/microsoft/WSL/issues/11102) |
| `hostAddressLoopback`: extra host IPv4s for Host↔WSL (beyond `127.0.0.1`); IPv4 only | Learn |
| `ignoredPorts`: let Linux bind ports Windows already uses (e.g. Docker DNS 53) | Learn |

**Caveat summary:** enable only after mirrored is proven on your VPN/NIC. Default `false` / null is correct for most.

### `bestEffortDnsParsing` / `dnsTunnelingIpAddress` / `initialAutoProxyTimeout`

| Fact | Evidence |
| --- | --- |
| Only meaningful with DNS tunneling / autoProxy paths | Learn + config VALIDATE_CONFIG_OPTION when tunneling off |
| Defaults already good on Win11 22H2+ (`dnsTunneling=true`, `autoProxy=true`) | Learn main table |
| `bestEffortDnsParsing`: ignore unknown DNS record types — niche VPN/DNS breakage fix | Learn |

**Caveat summary:** omit unless debugging a specific DNS/proxy failure.

### Mirrored networking itself (stable `[wsl2]`, but not free)

Not experimental anymore, but couples to experimental helpers:

- Learn **recommends trying** mirrored (IPv6, VPN, LAN, localhost Host↔WSL) — default remains **`NAT`**.
- LAN inbound may need Hyper-V firewall allow ([networking](https://learn.microsoft.com/en-us/windows/wsl/networking)).
- `localhostForwarding` is ignored under mirrored (Learn example comment).
- File bugs on mirrored to microsoft/WSL; treat as “try on metal, keep NAT as fallback.”

## 11. Full recommended files

**Two bars:**

| Bar | Goal | How “full” |
| --- | --- | --- |
| **A — WinMint product** | Deterministic FirstLogon staging; create-if-absent; don’t clobber taste | Pin **only** what the engine won’t do for you: VHD ceiling |
| **B — Modern recommended** | WSL-primary laptop / maintainer recipe | Explicitly set **stable** modern options (even when they match defaults); still omit device-relative + experimental |

Leaving keys out is not “ignoring modern WSL.” On Win11 22H2+ the engine already defaults `dnsTunneling`, `autoProxy`, and `firewall` to `true`, and `memory`/`processors`/`swap` already scale to the host. The interesting choices are: **VHD ceiling** (must pin — default is 1 TiB), **mirrored vs NAT** (default NAT; Learn recommends trying mirrored), and **experimental** (mostly don’t).

### A) WinMint product-owned (create-if-absent when Profile has WSL)

```ini
# WinMint — only when packages.wsl is non-empty. Create-if-absent; never overwrite.
# Intentionally minimal: do not pin networking/memory (user may already have .wslconfig;
# create-if-absent means first writer wins — keep product surface tiny).
[wsl2]
defaultVhdSize=256GB
```

### B) Modern recommended (portable, explicit)

Full stable surface worth considering. Apply with `wsl --shutdown`. Smoke-test mirrored on your VPN; if it breaks, set `networkingMode=nat` (or delete that line).

```ini
# Modern recommended .wslconfig — Win11 22H2+, current Store WSL
# Portable: no memory/processors/swap pins (engine ≈ 50% RAM / all CPUs / ≈25% swap).
# Experimental keys omitted on purpose — see §10.

[wsl2]
# --- Storage (create-time ceiling; 1024-based GB) ---
defaultVhdSize=256GB

# --- Networking (stable; Learn “modern” path) ---
# Default engine mode is NAT. Mirrored is the recommended upgrade for
# IPv6, VPN compatibility, LAN reachability, localhost Host↔WSL.
networkingMode=mirrored
dnsTunneling=true          # default true on 22H2+; set explicitly
autoProxy=true             # inherit Windows HTTP proxy into WSL
firewall=true              # Hyper-V / Windows Firewall integration
# localhostForwarding=true # default true; IGNORED when networkingMode=mirrored

# --- VM / desktop (defaults are already true; pin for clarity) ---
guiApplications=true       # WSLg
nestedVirtualization=true  # nested VMs inside WSL2 (ARM64 SKU-dependent)

# --- Leave unset (device-relative) ---
# memory=
# processors=
# swap=
# swapFile=

# --- Leave unset unless diagnosing ---
# debugConsole=true
# safeMode=true
# kernel=C:\\path\\to\\customKernel
# vmIdleTimeout=60000

# --- Experimental: do NOT enable in a “recommended” baseline (§10) ---
# [experimental]
# autoMemoryReclaim=disabled   # only if dropCache/gradual causes stalls
# sparseVhd=true               # blocked / --allow-unsafe; corruption risk
# hostAddressLoopback=true     # mirrored only; must be under [experimental]
# ignoredPorts=53,3000         # mirrored only; Docker/port conflicts
# bestEffortDnsParsing=true    # niche DNS with tunneling
```

**Why this isn’t longer:** every other official `[wsl2]` key is either host-specific (`memory`, `kernel`, `swapFile`), recover/debug (`safeMode`, `debugConsole`), deprecated (`networkingMode=bridged`), or already covered above. Experimental keys are listed as comments so they’re considered — and rejected for baseline — with citations in §10.

### C) Explicit “safe experimental off” (reclaim pinned; still no RAM pin)

```ini
[wsl2]
defaultVhdSize=256GB
networkingMode=mirrored
dnsTunneling=true
autoProxy=true
firewall=true
guiApplications=true
nestedVirtualization=true

[experimental]
autoMemoryReclaim=disabled
```

### D) One-off personal override (not a template)

Only if you *know* this host and want more than the 50% RAM default — never ship from WinMint:

```ini
[wsl2]
defaultVhdSize=256GB
networkingMode=mirrored
dnsTunneling=true
autoProxy=true
firewall=true
guiApplications=true
nestedVirtualization=true
memory=24GB    # example only: 32GB host; retune or delete when moving machines
```

### What was considered and left out of B

| Option | Why not in baseline B |
| --- | --- |
| `sparseVhd=true` | Runtime corruption gate / `--allow-unsafe`; docs ≠ product behavior (§10) |
| `autoMemoryReclaim=gradual` | Hang history with systemd / Docker Resource Saver |
| `autoMemoryReclaim=dropCache` | Already docs default — pinning adds no value; use `disabled` only when hurt (C) |
| `hostAddressLoopback` / `ignoredPorts` | Mirrored companions; niche; wrong section breaks parse |
| `bestEffortDnsParsing` / custom DNS tunnel IP | Debug knobs for broken VPN DNS |
| `memory` / `processors` / `swap` | Device-relative; engine already scales |
| `networkingMode=nat` explicit | Fine as fallback; mirrored is the “modern try” Learn pushes |
| Promoting B’s networking into **A** | Product create-if-absent would freeze mirrored for users who never had a file; keep A tiny until a Profile flag exists |

## Open / watch

- Whether Microsoft re-enables silent `sparseVhd` for new VHDs without `--allow-unsafe` (track [#13241](https://github.com/microsoft/WSL/issues/13241)).
- Whether `autoMemoryReclaim` graduates out of `[experimental]` (default already `dropCache`).
- Any new official `.wslconfig` sections beyond `[wsl2]` / `[experimental]` in future Learn `ms.date` bumps.
