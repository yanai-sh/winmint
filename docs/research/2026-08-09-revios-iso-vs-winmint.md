# Research: ReviOS ISO injection & tweak model vs WinMint

**Date:** 2026-08-09  
**Question:** How does ReviOS (Revision) ISO fix/tweak logic and host UX compare to WinMint — what can WinMint learn?  
**Follow-up:** Merged deeper AME/Features findings from research pass ([Compare ReviOS ISO vs WinMint](7e22ec7d-faff-4e5d-aa03-67f5708669a0)).

## Sources (primary)

| Source | Role |
|--------|------|
| [ISO Injection (Revi)](https://www.revi.cc/docs/playbook/iso) | User walkthrough: AME Beta + playbook → ISO |
| [ISO Injection (Amelabs)](https://docs.amelabs.net/iso_injection.html) | What injection *does*: embed `.apbx`, custom OOBE, apply at first boot |
| [Creating Playbooks](https://docs.amelabs.net/creating_playbooks.html) | `.apbx` = YAML/scripts package (`playbook.conf`, `!appx`, `!registryValue`, …) |
| [Running ReviOS](https://revi.cc/docs/playbook/install) | Live-system Playbook apply |
| [What is ReviOS?](https://revi.cc/docs/what-is-revi) | Playbook + AME + Revision Tool |
| [Comparison](https://revi.cc/docs/comparison) | WinSxS empty-CAB component story vs stock |
| [Features Overview](https://revi.cc/docs/features) | APPX tables, optional toggles, Untouched/Broken honesty |
| WinMint [CONTEXT.md](../../CONTEXT.md), [ARCHITECTURE.md](../ARCHITECTURE.md), [IMAGESERVICING.md](../design/IMAGESERVICING.md), ADR-004 / ADR-008 / ADR-009 / ADR-011 | WinMint contracts |

Related (host UX): [Rectify11 & ReviOS host UX](2026-08-09-rectify11-revios-host-ux.md). Rectify11 itself — in-place UI consistency; not an ISO compiler. v3 system-file patching = do-not-copy.

---

## 1. ReviOS ISO path

### User-facing steps ([revi.cc ISO](https://www.revi.cc/docs/playbook/iso))

1. Run **AME Beta** (not Revision Tool).
2. **Download ISO** inside AME (Win 11).
3. “Select a Playbook to modify ISO” → drag `ReviPB-x.y.apbx`.
4. Next → **Configure Options** (multi-select); star callout: **Include additional drivers**.
5. **ISO Credentials** — recommend `User`; password optional/blank OK.
6. Writing to USB — docs still “updated soon.”

Labeled **experimental** + known issues (log dir, VMware clipboard, classic context menu → Revision Tool, Chocolatey/Firefox hangs, Bluetooth/`DisableCAD` reg deletes).

### What actually runs ([Amelabs ISO Injection](https://docs.amelabs.net/iso_injection.html))

Injection is a **hybrid**, not a WinMint-style offline DISM plan:

- Host **embeds** the `.apbx` into the ISO and can enhance/replace setup with **Amelabs custom OOBE**.
- Bulk playbook work (APPX, registry, software/Chocolatey, many tweaks) is framed as executing **at first boot** while the user may set regional options in that custom OOBE.

So “ISO injection” ≠ “all tweaks applied offline into the WIM before ship.” Much of the “fix” is **staged for guest first-boot**.

Live path ([install](https://revi.cc/docs/playbook/install)): apply playbook to **running** stock Windows; Defender disable guided; customize; 5–30 min. Prefer clean stock; don’t run on third-party tweaked ISOs.

**Product shape:** Revision authors the playbook; **Amelabs owns AME**; Revision Tool is post-install Fluent personalization.

---

## 2. ReviOS tweak / disclosure model

| Area | Model (docs) |
|------|----------------|
| Package format | `.apbx` (7z of YAML/scripts; `playbook.conf` + `!appx` / `!registryValue` / tasks) |
| APPX | Large default remove set + **optional** table (Edge, OneDrive, Copilot, Xbox, …) — [Features](https://revi.cc/docs/features) |
| WinSxS | Empty **CAB “newer component”** so Windows uninstalls telemetry/etc.; repair via uninstall package — [Comparison](https://revi.cc/docs/comparison) |
| Privacy / security | Aggressive: policy, firewall, IFEO kills, hosts blocks; Defender/VBS often off by default (toggles) |
| Updates | Compatible but marketing includes long pause; drivers often manual |
| Honesty extras | Features page has **Untouched** and **Broken** (e.g. things broken *because* telemetry removed) |

**Honesty verdict:** Features inventory is stronger than typical debloat marketing. Gaps: Comparison hyperbole (“telemetry eliminated”); opaque `.apbx`; ISO path experimental with deferred tweaks and post-hoc reg fixes.

---

## 3. WinMint model (repo contracts)

| Piece | Behavior |
|-------|----------|
| Source | User-supplied **official Source ISO** — no product download/pin |
| Intent | **Profile** → **BuildPlan** → artifacts |
| Offline | **ImageServicing**: elevated DISM/hive/oscdimg; remove-list + Keep; product-constant policies |
| Guest | **Provisioning Supervisor** (no guest pwsh product runtime); splash → DMA → jobs → Explorer |
| Residual | Best-effort erase after green FirstLogon (ADR-008) — not a durable distro brand tool |
| Debloat | Curated remove-list / host `recommended` expand — not CAB-supersede as primary |

---

## 4. Side-by-side

| Dimension | ReviOS (+ AME) | WinMint |
|-----------|----------------|---------|
| Product shape | Playbook + third-party runner + Revision Tool | Owned compiler: Profile → BuildPlan → ImageServicing → Supervisor |
| ISO work | Embed playbook + custom OOBE; **bulk apply at first boot** | First-class **offline** DISM plan + digests |
| Base media | AME can download Win11 | User supplies Source ISO |
| Config language | YAML actions in `.apbx` | Typed Profile JSON |
| Debloat | APPX lists + WinSxS CAB supersede | Remove-list polarity + catalogs |
| Account on ISO path | Blank password OK in Revi ISO docs | Password required (autologon) |
| Security defaults | Defender/VBS teardown common | Not product identity |
| Post-install UI | Durable Revision Tool | Residual erase; evidence under ProgramData |
| ISO maturity | Experimental | Core Smoke/metal path |
| Guest control plane | AME TrustedUninstaller + scripts/ps/Chocolatey | Native AOT Supervisor; delegated winget/scoop/wsl |

---

## 5. UI/UX harvest (for Design §1)

**Steal patterns:**

1. Dense **Configure Options** → Taste (one surface, many toggles).
2. Credentials after options → You (keep password required).
3. Star **must-know** options → Included honesty (“also applied quietly…”).
4. Risk-first docs on experimental lanes.
5. Linear short wizard: media → options → credentials (maps Media → You → Taste → Included, not five bare panes).

**Do not confuse** Amelabs custom-OOBE progress theater with WinMint Supervisor splash — similar *job* (work while user waits), different stack and legal surface.

**Rectify11:** visual consistency / Control Center for a modified desktop only — not ISO compiler UX.

---

## 6. What WinMint should not copy

1. In-product Windows ISO download/bundling.  
2. AME as product shell / playbook-as-only-format.  
3. Passwordless ISO local account.  
4. Defender/SmartScreen/VBS kill as default “optimization.”  
5. WinSxS empty-CAB supersede as primary debloat without ADR.  
6. IFEO/hosts telemetry war as product default.  
7. Updates paused to far-future dates as a feature.  
8. Hardware bypass + watermark suppression as marketing.  
9. Third-party custom OOBE replacing Microsoft setup as the brand.  
10. Durable post-install branded tweaking app (vs ADR-008).  
11. Shipping experimental ISO injection with known CAD/Bluetooth breakage.  
12. Opaque encrypted playbook as the user-facing intent format.  
13. “Telemetry eliminated at core” without evidence bars.  
14. Rectify11 v3 in-place system-file patching.

---

## Verdict

**ReviOS** = curated AME **playbook** (YAML + WinSxS CAB surgery + aggressive privacy/security), applied live or via **experimental ISO Injection** that embeds the package and leans on **first-boot / custom OOBE** execution.

**WinMint** = **compiler**: Profile → offline ImageServicing → ISO, then owned C# ProvisioningSession — remove-list polarity, residual erase, no guest pwsh control plane.

Closest UX harvest: **dense configure → credentials → receipt**, plus Features-level honesty for **Included**. Do not adopt Revi’s security teardown, ISO download, or CAB-supersede debloat as defaults.
