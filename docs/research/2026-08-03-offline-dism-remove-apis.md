# Offline DISM remove APIs (Win11 ARM64) — research (2026-08-03)

Question: what are the supported offline (`/Image`) ways to remove provisioned AppX packages, capabilities, and optional features on Windows 11 ARM64 — exact DISM/cmdlet surfaces, parameters, common failure modes, and what evidence WinMint should record after a successful remove?

WinMint framing (from product docs, not Microsoft sources): Offline **ImageServicing** mutates a mounted WIM via elevated host pwsh + DISM `/Image`; debloat / keep-flag matrix is a **deferred** vertical ([TICKETS.md](../TICKETS.md), [IMAGESERVICING.md](../design/IMAGESERVICING.md)). This note catalogs the Microsoft-supported remove surfaces only — not a keep-list policy.

Trust tiers used throughout:

- **[primary]** — Microsoft Learn DISM CLI / Dism-module cmdlet docs (`view=windows-11` or current `windowsserver2025-ps` help), inspected 2026-08-03.
- **[product]** — WinMint design (`ImageEvidence`, servicing invariants).
- **[inference]** — mapping primary facts onto WinMint seams; labeled as such.

## Scope boundaries

| In scope (offline image) | Out of scope for this ticket |
|--------------------------|------------------------------|
| Provisioned AppX (`.appx` / `.appxbundle`) | Live per-user `Remove-AppxPackage` / `PackageManager` |
| Features On Demand **capabilities** | Building a keep-flag matrix / catalog of what to remove |
| Optional Windows **features** (`/Disable-Feature`) | Cab/MSU package uninstall as a general “debloat” path |
| `/Image` vs `/Online` (or `-Path` vs `-Online`) | Siloed provisioning packages (ADK-only; not mounted-WIM) |

## `/Image` vs `/Online` (and `-Path` vs `-Online`)

Every DISM servicing family below requires **exactly one** target mode:

| Surface | Offline | Online |
|---------|---------|--------|
| DISM.exe | `/Image:<path_to_mounted_image_root>` | `/Online` |
| Dism PowerShell module | `-Path <mounted root>` | `-Online` |

([primary — AppX servicing syntax](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-app-package--appx-or-appxbundle--servicing-command-line-options?view=windows-11); [capabilities note](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-capabilities-package-servicing-command-line-options?view=windows-11); [optional-feature howto](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/enable-or-disable-windows-features-using-dism?view=windows-11))

**Prerequisite:** the WIM/VHD must already be mounted; `/Image` / `-Path` point at the **mount directory** (image root containing `Windows\`), not at the `.wim` file path ([primary — enable/disable features howto, mount step](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/enable-or-disable-windows-features-using-dism?view=windows-11)).

**WinMint implication [inference]:** ImageServicing already mounts under elevation; remove kernels should reuse that mount path and must not call `/Online` against the build host.

Cmdlet ↔ DISM.exe mapping for these removes ([primary — Use DISM in Windows PowerShell](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/use-dism-in-windows-powershell-s14?view=windows-11)):

| DISM.exe | Cmdlet |
|----------|--------|
| `/Remove-ProvisionedAppxPackage` | `Remove-AppxProvisionedPackage` |
| `/Get-ProvisionedAppxPackages` | `Get-AppxProvisionedPackage` |
| `/Remove-Capability` | `Remove-WindowsCapability` |
| `/Get-Capabilities` | `Get-WindowsCapability` |
| `/Disable-Feature` | `Disable-WindowsOptionalFeature` |
| `/Get-Features` / `/Get-FeatureInfo` | `Get-WindowsOptionalFeature` |

Either surface is supported; WinMint’s elevated `pwsh` path can prefer cmdlets for structured objects, or `Dism.exe` for log parity with existing kernels — product choice, not a Microsoft restriction.

---

## 1. Provisioned AppX packages

### Supported offline surfaces

**DISM.exe** ([primary — AppX servicing CLI](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-app-package--appx-or-appxbundle--servicing-command-line-options?view=windows-11)):

```cmd
DISM.exe /Image:<path_to_image_directory> /Get-ProvisionedAppxPackages
DISM.exe /Image:<path_to_image_directory> /Remove-ProvisionedAppxPackage /PackageName:<PackageName>
```

Example from docs:

```cmd
Dism /Image:C:\test\offline /Remove-ProvisionedAppxPackage /PackageName:microsoft.devx.appx.app1_1.0.0.0_neutral_ac4zc6fex2zjp
```

**Cmdlet** ([primary — Remove-AppxProvisionedPackage](https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage?view=windowsserver2025-ps)):

```powershell
Get-AppxProvisionedPackage -Path <mount>
Remove-AppxProvisionedPackage -Path <mount> -PackageName <PackageName>
```

Mandatory offline parameters: `-Path`, `-PackageName`. Shared optional: `-WindowsDirectory`, `-SystemDrive`, `-LogPath`, `-ScratchDirectory`, `-LogLevel`.

Discover the exact `PackageName` via `Get-AppxProvisionedPackage` / `/Get-ProvisionedAppxPackages` before remove ([primary — Preinstall Apps Using DISM](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/preinstall-apps-using-dism?view=windows-11)).

### Semantics (critical)

- Removes **provisioning**: the package will **not** be installed for **new** user accounts ([primary — Remove-AppxProvisionedPackage description](https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage?view=windowsserver2025-ps); [CLI /Remove-ProvisionedAppxPackage](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-app-package--appx-or-appxbundle--servicing-command-line-options?view=windows-11)).
- Does **not** remove packages already registered to existing user profiles. For those, Microsoft documents using live `Remove-AppxPackage` **after** removing provisioning ([primary — same CLI Important note](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-app-package--appx-or-appxbundle--servicing-command-line-options?view=windows-11)).
- On a generalized / never-booted consumer `install.wim` (WinMint’s normal path), no user profiles exist → remove clears provisioning **and** the package from the image ([primary — Preinstall Apps “Update or remove packages”](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/preinstall-apps-using-dism?view=windows-11)).
- Online-only `-AllUsers` exists on `Remove-AppxProvisionedPackage` (Online parameter set); **not** part of the Offline `-Path` set ([primary — cmdlet syntax](https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage?view=windowsserver2025-ps)).

**Do not confuse with** `Remove-AppxPackage` (Appx module) — that is per-user / live, not offline provisioned servicing.

### ARM64 notes

Microsoft’s AppX dependency table for **add** (architecture-specific dependencies) lists:

| Computer architecture | Dependencies to install |
|-----------------------|-------------------------|
| x64 | x64 and x86 |
| x86 | x86 |
| Arm | Arm only |

Non-applicable architectures are ignored on add (e.g. Arm deps ignored on x64 targets) ([primary — /Add-ProvisionedAppxPackage dependency section](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-app-package--appx-or-appxbundle--servicing-command-line-options?view=windows-11)).

**Remove** uses the same `/PackageName` / `-PackageName` surface on Arm as on other arches — no ARM64-specific remove switch is documented. Inventory on an ARM64 image will show ARM64 (and neutral) package full names; use those exact names.

Siloed provisioning packages are a separate ADK path and are **not** supported against a mounted offline image ([primary — Siloed provisioning packages](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/siloed-provisioning-packages?view=windows-11)) — irrelevant to WinMint’s mount-and-commit kernels.

---

## 2. Capabilities (Features On Demand)

### Supported offline surfaces

**DISM.exe** ([primary — Capabilities Package Servicing CLI](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-capabilities-package-servicing-command-line-options?view=windows-11)):

```cmd
DISM.exe /Image:<path> /Get-Capabilities
DISM.exe /Image:<path> /Get-CapabilityInfo /CapabilityName:<name>
DISM.exe /Image:<path> /Remove-Capability /CapabilityName:<name>
```

Multiple `/CapabilityName` values may be passed on one remove command. Offline example from docs:

```cmd
Dism /Image:C:\test\offline /Remove-Capability /CapabilityName:Language.Basic~~~en-US~0.0.1.0
```

**Cmdlet** ([primary — Remove-WindowsCapability](https://learn.microsoft.com/en-us/powershell/module/dism/remove-windowscapability?view=windowsserver2025-ps)):

```powershell
Get-WindowsCapability -Path <mount> [-Name <filter>]
Remove-WindowsCapability -Path <mount> -Name <CapabilityName>
```

Mandatory offline: `-Path`, `-Name`. Capability identity strings look like `Language.TextToSpeech~~~fr-FR~0.0.1.0` / `Language.Basic~~~en-US~0.0.1.0` (docs examples).

Desktop editions note on the capabilities CLI page: Windows 10/11 Home, Pro, Enterprise, Education ([primary — capabilities CLI intro](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-capabilities-package-servicing-command-line-options?view=windows-11)).

### Dependency failure mode

**You cannot remove a capability that other packages depend on.** Example from FOD docs: with French handwriting + basic installed, removing basic fails ([primary — Features On Demand, /Remove-Capability note](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-v2--capabilities?view=windows-11)).

Best practice for FOD **add** is `/Add-Capability` (not deprecated `/Add-Package`); remove symmetrically uses `/Remove-Capability` ([primary — same FOD page](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-v2--capabilities?view=windows-11)).

### ARM64 notes

No ARM64-specific `/Remove-Capability` parameters. Satellite FODs install only packages that apply to the image architecture ([primary — FOD types](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-v2--capabilities?view=windows-11)); inventory via `/Get-Capabilities` on the mounted ARM64 image is the source of truth for names present to remove.

---

## 3. Optional features

### Supported offline surfaces

**DISM.exe** ([primary — OS package servicing CLI](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-operating-system-package-servicing-command-line-options?view=windows-11); [howto](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/enable-or-disable-windows-features-using-dism?view=windows-11)):

```cmd
DISM.exe /Image:<path> /Get-Features
DISM.exe /Image:<path> /Get-FeatureInfo /FeatureName:<name>
DISM.exe /Image:<path> /Disable-Feature /FeatureName:<name> [/PackageName:<pkg>] [/Remove]
```

**Cmdlet** ([primary — Disable-WindowsOptionalFeature](https://learn.microsoft.com/en-us/powershell/module/dism/disable-windowsoptionalfeature?view=windowsserver2025-ps)):

```powershell
Get-WindowsOptionalFeature -Path <mount> [-FeatureName <name>]
Disable-WindowsOptionalFeature -Path <mount> -FeatureName <name> [-PackageName <pkg>] [-Remove] [-NoRestart]
```

Notes:

- `-FeatureName` is mandatory; multiple features in the same parent package can be listed.
- `-PackageName` optional when the feature is in the Windows Foundation package; required otherwise ([primary — Disable-WindowsOptionalFeature](https://learn.microsoft.com/en-us/powershell/module/dism/disable-windowsoptionalfeature?view=windowsserver2025-ps); [CLI /Disable-Feature](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-operating-system-package-servicing-command-line-options?view=windows-11)).
- `-Remove` / `/Remove`: removes feature **files** but keeps the **manifest**; feature shows as removed / restorable via `/Enable-Feature` + `/Source` (Features on Demand style) ([primary — Disable-WindowsOptionalFeature -Remove](https://learn.microsoft.com/en-us/powershell/module/dism/disable-windowsoptionalfeature?view=windowsserver2025-ps)).

### Client payload caveat (Win10+)

Starting with Windows 10, **`/Remove` does not remove the payload from Windows client editions** (supports Push-button reset); payload **is** removed on Windows Server ([primary — enable/disable howto “remove for on-demand”; Disable-WindowsOptionalFeature -Remove note](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/enable-or-disable-windows-features-using-dism?view=windows-11)).

**Inference for WinMint:** on Win11 client ARM64 ISO work, expect disable to change **state**, not necessarily shrink the image when using `/Remove`.

### Pending states

After disable, `/Get-FeatureInfo` may report **DisablePending** — the image must be booted for the disable to complete ([primary — howto “To disable Windows features”](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/enable-or-disable-windows-features-using-dism?view=windows-11)). Offline ISO customization commonly still commits the pending state into the WIM; first boot finishes it. Record state from post-op `/Get-FeatureInfo`, including pending.

Unattend can enable/disable Foundation features offline, but **cannot** restore/remove Features on Demand via answer file ([primary — howto unattend section](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/enable-or-disable-windows-features-using-dism?view=windows-11)).

---

## Common failure modes (cross-cutting)

| Failure | Applies to | Primary guidance |
|---------|------------|------------------|
| Wrong / stale identity string | All | Always inventory first (`Get-*` / `/Get-*`); PackageName / CapabilityName / FeatureName must match the image |
| Target is `.wim` path instead of mount dir | All | Mount first; `/Image` is the mount root |
| Host `/Online` instead of image `/Image` | All | Mutates the build machine, not the ISO |
| AppX still present for existing profiles | AppX | Provisioning-only remove; need live `Remove-AppxPackage` if profiles exist ([primary — AppX CLI Important](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-app-package--appx-or-appxbundle--servicing-command-line-options?view=windows-11)) |
| Capability still required by dependents | Capabilities | Remove dependents first ([primary — FOD remove note](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-v2--capabilities?view=windows-11)) |
| Expecting client image shrink from `/Remove` | Optional features | Client editions keep payload for PBR ([primary — howto](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/enable-or-disable-windows-features-using-dism?view=windows-11)) |
| Pending online actions block later ops | Packages / features | Documented for package add with pending state; use awareness + logs ([primary — OS package limitations](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-operating-system-package-servicing-command-line-options?view=windows-11)) |
| Non-zero DISM without commit discipline | All | WinMint invariant: first kernel failure → preserve workdir / `failure.json`; never silent partial success ([product — IMAGESERVICING](../design/IMAGESERVICING.md)) |
| Multi-edition `install.wim` commit | All mounts | WinMint locked: single-index before commit ([product — IMAGESERVICING invariant 7](../design/IMAGESERVICING.md)) |

Elevation: DISM image servicing requires an elevated session — already true for WinMint’s `RunPlan.ps1` path.

---

## Recommended evidence after a successful remove

### Existing `ImageEvidence` shape ([product](../design/IMAGESERVICING.md))

```csharp
public sealed record ImageEvidence(
    string OutputIsoPath,
    ImageQualityLane Lane,
    string ShellStampTargetPath,
    IReadOnlyDictionary<string, string> Digests);
```

Contract id: `winmint.image.evidence/v1` ([product — CONTRACTS / TICKETS](../design/CONTRACTS.md)). Digests today are sparsely used ([product — ponytail audit note](./2026-08-03-ponytail-audit.md)); they are the natural bag for remove fingerprints without expanding the sealed record prematurely.

### What to prove (Microsoft-aligned postconditions)

For each remove class, success means a **post-inventory** that no longer lists the target (or shows the expected disabled/removed state), plus DISM log path for forensics.

| Class | Success check (primary) | Suggested digests / side artifacts |
|-------|-------------------------|-------------------------------------|
| Provisioned AppX | Target `PackageName` **absent** from `Get-AppxProvisionedPackage -Path` / `/Get-ProvisionedAppxPackages` | `removed.appx.<PackageName>=absent`; optional hash of full provisioned list dump under workdir `logs/` |
| Capability | Target `Name` **not Installed** (or absent from installed set) per `Get-WindowsCapability` / `/Get-CapabilityInfo` | `removed.capability.<Name>=<State>` |
| Optional feature | `Get-FeatureInfo` / `Get-WindowsOptionalFeature` shows **Disabled**, **DisabledWithPayloadRemoved**, or **DisablePending** as expected | `feature.<FeatureName>=<State>`; if `-Remove` requested on client, do **not** claim payload bytes gone |

### Practical WinMint recording recipe [inference]

1. **Before** each remove batch: write inventory snapshots to workdir `logs/` (provisioned AppX list, capabilities, optional features of interest).
2. **Invoke** remove via elevated kernel (`Dism.exe` or Dism cmdlets) with explicit `-LogPath` / `/LogPath` under `logs/`.
3. **After** each remove (or batch): re-inventory; fail the kernel if any requested identity is still provisioned / still Installed / still Enabled.
4. On full `Apply` success: fold compact keys into `ImageEvidence.Digests` (identity → final state) and keep full lists as workdir logs (evidence projection stays write-only / non-control-plane per TDD).
5. Do **not** treat ISO byte size alone as proof of AppX/capability remove — especially with client `/Remove` payload retention.

Defer inventing a new evidence schema until the debloat vertical lands; Digests + `logs/` cover smoke-grade prove-out without expanding `ImageEvidence` fields.

---

## Synthesis — WinMint

| Goal | Use |
|------|-----|
| Strip inbox Store apps from golden ISO | Offline `Remove-AppxProvisionedPackage` / `/Remove-ProvisionedAppxPackage` on mounted single-index WIM |
| Strip FODs / language capabilities | Offline `Remove-WindowsCapability` / `/Remove-Capability` (respect dependency order) |
| Turn off optional OS features | Offline `Disable-WindowsOptionalFeature` / `/Disable-Feature`; add `/Remove` only with eyes open on client payload retention |
| Live leftover AppX after OOBE | **Not** this API — FirstLogon / `Remove-AppxPackage` if Profile ever requires it |
| ARM64 | Same APIs; inventory on the ARM64 image; Arm-only deps on add; no special remove switch |

### Prefer

- Inventory → remove → re-inventory as the kernel contract.
- `-Path` / `/Image` exclusively in Servicing (never host `/Online` for ISO mutation).
- Exact Microsoft identity strings from Get-* on **that** mount.

### Avoid

- Treating BCU-style live uninstall or `Remove-AppxPackage` as the offline path ([related research](./2026-08-03-bulk-crap-uninstaller.md)).
- Assuming `/Remove` shrinks Win11 client images.
- Committing multi-edition WIMs or ignoring DisablePending in evidence.

## Bottom line

Microsoft’s supported offline remove trio for Win11 (including ARM64) is: **`Remove-AppxProvisionedPackage`**, **`Remove-WindowsCapability`**, and **`Disable-WindowsOptionalFeature`** (DISM `/Remove-ProvisionedAppxPackage`, `/Remove-Capability`, `/Disable-Feature`), all against a **mounted** image via `/Image` or `-Path`. Prove success with post-op Get-* absence/state plus DISM logs; stash compact results in `ImageEvidence.Digests` when the deferred debloat vertical lands.
