# Keep-flag capabilities / optional features matrix — spike (2026-08-04)

Question: On **Windows 11 25H2 ARM64 English** Pro media (WinMint acceptance Source ISO), which offline DISM **capability** and **optional feature** identities are present, which are safe to treat as a **thin acceptance pin list** (prove-out only — **not** a product-default recommended set), and which Profile JSON field names should ticket **20** freeze?

Trust tiers:

- **[primary]** — Microsoft Learn DISM capability / optional-feature offline surfaces ([prior note](2026-08-03-offline-dism-remove-apis.md))
- **[inventory]** — `Get-WindowsCapability -Path` / `Get-WindowsOptionalFeature -Path` against mounted `install.wim` from this host’s acceptance media (`Win11_25H2_English_Arm64_v2.iso` → single-index Pro WIM), 2026-08-04
- **[product]** — KEEPFLAG remove-list polarity; ADR-005 / ADR-006; AppX vertical pattern (catalog ⊆ Plan ⊆ image)

## Media pin

| Field | Value |
|-------|-------|
| SKU | Windows 11 Pro |
| Arch | ARM64 |
| Language | English (en-US Language.* caps Installed) |
| Host label | `Win11_25H2_English_Arm64_v2.iso` |
| Inventory | 371 capabilities; 140 optional features |

## Offline surfaces (locked for **20**)

| Kind | Inventory | Mutate | Digests (suggested) |
|------|-----------|--------|---------------------|
| Capability | `Get-WindowsCapability -Path` / `dism /Get-Capabilities` | `Remove-WindowsCapability` / `dism /Remove-Capability` | `removed.capability.<id>=Absent` |
| Optional feature | `Get-WindowsOptionalFeature -Path` | `Disable-WindowsOptionalFeature` / `dism /Disable-Feature` | `disabled.feature.<id>=Disabled` |

Fail closed: Profile id not in shipped catalog ⇒ Plan error. Listed id not present / already Absent|Disabled ⇒ idempotent ok (match AppX reuse-media posture) **or** fail closed if product prefers assert-present — **ticket 20** should mirror AppX: already-absent ⇒ ok + digest.

## Profile wire (freeze in **20**)

```json
"debloat": {
  "removeProvisionedAppx": [ "...existing..." ],
  "removeCapabilities": [ "App.StepsRecorder~~~~0.0.1.0" ],
  "disableOptionalFeatures": [ "WorkFolders-Client" ]
}
```

- Absent / empty ⇒ no stage (Smoke-compatible).
- Catalog validate like AppX (`ProvisionedCapabilityCatalog` / `OptionalFeatureCatalog` or one combined module).
- **No** product-default recommended set. Host/Wizard presets stay out until explicitly ticketed.

## Installed capabilities (acceptance media)

Only **Installed** (not the NotPresent language pack matrix):

| Name | Notes |
|------|-------|
| `App.StepsRecorder~~~~0.0.1.0` | **Acceptance pin candidate** |
| `Browser.InternetExplorer~~~~0.0.11.0` | IE capability remnant |
| `DirectX.Configuration.Database~~~~0.0.1.0` | Keep — graphics stack |
| `Hello.Face.20134~~~~0.0.1.0` | Keep — biometric |
| `Language.Basic~~~en-US~0.0.1.0` | Keep — English media |
| `Language.Handwriting~~~en-US~0.0.1.0` | Keep |
| `Language.OCR~~~en-US~0.0.1.0` | Keep |
| `Language.Speech~~~en-US~0.0.1.0` | Keep |
| `Language.TextToSpeech~~~en-US~0.0.1.0` | Keep |
| `MathRecognizer~~~~0.0.1.0` | Optional remove later |
| `Media.WindowsMediaPlayer~~~~0.0.12.0` | Related to WMP feature |
| `Microsoft.Wallpapers.Extended~~~~0.0.1.0` | Cosmetic |
| `Microsoft.Windows.Notepad.System~~~~0.0.1.0` | Keep unless proving notepad swap |
| `Microsoft.Windows.PowerShell.ISE~~~~0.0.1.0` | Removable for prove-out |
| `Microsoft.Windows.Sense.Client~~~~` | Recall / Sense — policy-sensitive; **out of acceptance pin** |
| `OneCoreUAP.OneSync~~~~0.0.1.0` | Sync stack — careful |
| `OpenSSH.Client~~~~0.0.1.0` | Often wanted — not a pin |
| `Print.Management.Console~~~~0.0.1.0` | Optional |
| `VBSCRIPT~~~~` | Removable |
| `WMIC~~~~` | **Acceptance pin candidate** (deprecated tooling) |

Full capability dump (all states): `.scratch/smoke/caps-spike.csv` (local inventory artifact; not committed).

## Enabled optional features (acceptance media)

| FeatureName | Notes |
|-------------|-------|
| `WorkFolders-Client` | **Acceptance pin candidate** |
| `WCF-Services45` / `WCF-TCP-PortSharing45` | Framework — careful |
| `MediaPlayback` | Keep with media stack |
| `WindowsMediaPlayer` | Classic optional feature; pairs with Media.* capability |
| `SmbDirect` | RDMA — keep on server-ish images |
| `Printing-PrintToPDFServices-Features` | Keep |
| `Windows-Defender-Default-Definitions` | Keep |
| `SearchEngine-Client-Package` | Keep |
| `Microsoft-RemoteDesktopConnection` | Keep for Hyper-V lab |
| `Printing-Foundation-Features` / `…InternetPrinting-Client` | Printing |
| `MSRDC-Infrastructure` | RDP infra |
| `NetFx4-AdvSrvs` | .NET — keep |

## Thin acceptance pin list (prove-out only)

**Not** a product default. Same spirit as AppX pins (`Microsoft.BingNews`, `Microsoft.BingWeather`):

| Kind | Id |
|------|----|
| Capability | `App.StepsRecorder~~~~0.0.1.0` |
| Capability | `WMIC~~~~` |
| Optional feature | `WorkFolders-Client` |

Re-pin if a future 25H2 English ARM64 ISO drops an id (KEEPFLAG).

## Explicitly out (this spike)

- Product-default recommended remove-list
- Schema `v2`
- Leftover confidence / CDM-as-primary
- Live FirstLogon capability flips (offline ImageServicing only for **20**)
- Shipping the full 371/140 matrices as “remove everything”

## Ticket **20** implement sketch

1. Catalogs: legal ids ⊇ acceptance pins (small static sets; expand later).
2. `BuildPlan`: validate Profile lists ⊆ catalogs; emit opcodes `RemoveCapabilities` / `DisableOptionalFeatures` after mount, peer to `RemoveProvisionedAppx`.
3. Servicing kernels: param-only; digests under workdir `logs/`; ImageEvidence digest map.
4. Proof: Apply-path digests assertable without FirstLogon; full Smoke optional.
