# Research: Rectify11 & ReviOS host UX (for WinMint wizard)

**Date:** 2026-08-09  
**Question:** What host UI/IA patterns do Rectify11 and ReviOS/Revision/AME use, and what should WinMint steal or reject for the Profile → ISO builder wizard?  
**Companion:** [ReviOS ISO vs WinMint](2026-08-09-revios-iso-vs-winmint.md) (mutation model, don’t-copy security/CAB).  
**Pass:** [Research Rectify11 ReviOS UX](b01bbfdd-3f20-4d31-b2e5-df5a5b536370).

## Evidence quality

Marketing pages describe products more than wizard chrome. Strongest IA evidence is **source** (Rectify11 `frmWizard.cs`, Revision Tool routes) and **docs** (Revi + AME). Public Fluent chrome screenshots are thin—treat chrome claims as inferred unless mocked.

---

## 1. Product shapes

| Product | Host surface | Mutation target |
|---------|--------------|-----------------|
| **Rectify11** | Standalone WinForms install wizard → Control Center | Live Win11 themes/icons/extras ([rectify11.net](https://rectify11.net/), [Installer](https://github.com/Rectify11/Installer)) |
| **ReviOS** | AME Wizard/Beta applies `.apbx`; **Revision Tool** post-apply | Live OS **or** ISO inject ([what-is-revi](https://revi.cc/docs/what-is-revi)) |
| **AME** | Dark UI; sidebar drag `.apbx` / `.iso`; prerequisites → apply | Playbook runner + ISO download/write ([getting started](https://docs.amelabs.net/getting_started.html)) |

WinMint: host **builds** ISO from Profile; guest **Provisioning Supervisor** finishes setup—must not look like a live shell patcher.

---

## 2. Host flows (compressed)

### Rectify11 Installer

`FrmWizard`: Welcome → Defender gate → EULA → **InstallOptnsPage** (tree: icons / themes / extras) → optional Theme / CMenu → **InstallConfirmation** → Progress. Side image swaps with selected extra. Post: Control Center.

### Revi + AME

**Live:** Update → drag playbook → guided **disable Defender** → customize → run 5–30 min.  
**ISO:** Download ISO → drag playbook → Configure Options → Credentials → USB (docs stubbed).  
**Revision Tool** (Fluent/`fluent_ui`, ReviOS-only): Home · Tweaks (Security / Performance / Personalization / Utilities / Updates) · MS Store · Settings — deliberately W11 Settings-like (nav pane, cards, breadcrumbs).

---

## 3. Steal for WinMint Design §1

| Pattern | WinMint mapping |
|---------|-----------------|
| Explicit product shape (“Playbook + tool,” not fake distro ISO) | Say: host builds ISO/intent; guest finishes—not a live-patcher |
| Default vs optional removal tables ([features](https://revi.cc/docs/features)) | Taste density + Included honesty; keep chips optional |
| Prerequisite unlock before Next | Elevate, Source ISO, arch, disk—**without** teaching AV off |
| Confirm before mutate | Included receipt before Build |
| Progress + time honesty | Phase labels + ETA on host build |
| Side preview for consequential picks | Taste / Included consequence preview where cheap |
| Conditional short wizard | Skip Taste → Included; don’t parade empty panes |
| Cinematic wizard vs Settings companion | Host OOBE moodboard ≠ dense tweak catalog; ADR-008 → no durable branded post-tool as product identity |
| Drag-drop intent artifact | Profile JSON / Source ISO drop |
| Risk copy up front | Experimental lanes, clean Source ISO contract |
| Integrity (SHA256) | Source / plan digests where already in architecture |

---

## 4. Do not copy

| Anti-pattern | Why |
|--------------|-----|
| In-place system-file / `.mun` patching (Rectify11 v3) | Offline ImageServicing only |
| Live Windows as primary builder path | Host builds ISO; live guest ≠ builder UX |
| Disable Defender / Tamper / SAC to unlock Next | Elevate Servicing only |
| DLL / icon TreeView of everything | Curated remove-list + recommended expand |
| Killable mid-Servicing (Alt+F4 folklore) | Fail-closed / block close during mutate |
| AV exclusion paths as UX | Don’t normalize fighting the OS |
| “Safer than others” while deep-removing WinSxS/Defender | Disclose method; don’t oversell |
| Companion tool that only runs on “our” OS brand without refuse | If any companion exists, detect identity / refuse wrong image |
| Experimental ISO as peer path without same QA bar | Smoke/metal bar for the product path |
| Cinematic Fluent for power-user tweak grids | Guided composition for wizard; Settings shell only if a real maintenance surface ships (vs residual erase) |

---

## 5. Comparison (UX only)

| | Rectify11 | Revi / AME / Revision | WinMint |
|--|-----------|------------------------|---------|
| Wizard job | Live customize | Apply playbook / inject ISO | Compile Profile → ISO |
| Selection UI | Hierarchical tree | Configure Options + docs tables | Taste + keep chips; Included disclosure |
| Honesty | Site vs README tension on file mods | Strong Playbook+AME + risk + method | BuildPlan → Servicing → Supervisor |
| Security in UX | Defender page / AV guidance | Hard gate: disable security | Elevate only |
| After install | Control Center | Revision Tool (Settings IA) | Residual erase (ADR-008) |

---

## Verdict

Steal **disclosure**, **default/optional density**, **conditional short wizards**, **confirm + timed progress**, **drag-drop intent**, and (only if a companion ever exists) **Settings-like IA**—not cinematic forever. Reject **live patching**, **Defender-disable gates**, **DLL trees**, and marketing that outruns the mutation model.

Chrome screenshots are thin; prefer Rectify11 navigation source + Revi/AME prose + Revision Tool routes as primary UX evidence.
