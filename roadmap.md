# WinMint Roadmap

## Current Phase

WinMint is in backend/product proof before GUI work resumes.

The next work is to prove the PowerShell-owned build, setup, FirstLogon, and
bootstrap behavior on real hardware. GPUI/Rust remains a frontend-only layer for
intent, preview, validation messages, and invoking the headless engine; it should
not drive backend behavior.

Both ARM64/aarch64 and amd64/x86-64 remain first-class support targets.

## Hardware Reality

- Primary development and acceptance machine: Surface Laptop 7 ARM64/aarch64,
  Snapdragon X Elite, Copilot+ PC.
- Available x64/amd64 machines: Alienware Aurora desktop and ThinkPad work
  laptop.
- Neither x64 machine is Copilot+. Copilot-key hardware validation belongs only
  on the Surface Laptop 7.
- The ThinkPad is temporary and will be returned around June 30, 2026. It is a
  time-boxed destructive x64 acceptance target.
- The Alienware is the longer-lived x64 regression/build machine. It is used
  primarily for gaming, so destructive testing there stays deliberate.

## Tracked Acceptance Profiles

- `config/build-profiles/yanai-sl7-microsoft-oobe.json`: ARM64 Surface
  dev/Copilot+ acceptance profile with YASB, thide, and Raycast. Windhawk is
  intentionally deferred.
- `config/build-profiles/yanai-thinkpad-return-amd64.json`: work PC return
  profile with a minimal, familiar Windows surface. Keeps Edge, installs no
  extra browsers/editors/launcher or shell layers, installs WSL Ubuntu, and uses
  `AutoWipeDisk0`.
- `config/build-profiles/yanai-alienware-aurora-amd64.json`: amd64 gaming
  desktop profile with Helium, Zen, Neovim, Zed, and Nilesoft. It has no
  launcher, still removes Xbox apps, and uses manual disk mode.

## Priority Order

1. Prove ARM64 Surface live install acceptance first.
2. Verify the release/bootstrap path.
3. Use live install audit output as the feedback loop for product fixes, run
   explicitly after acceptance installs or through an audit-enabled acceptance
   run/profile. The tracked profiles do not imply audit is enabled by default.
4. Stabilize x64 after ARM64 is stable, using the ThinkPad before return and the
   Alienware as the long-term x64 regression/build host.
5. Resume GUI work only after backend behavior is proven.

## Surface Acceptance Items

- FirstLogon completes and resumes correctly after interruption.
- YASB, thide, and Raycast install, configure, and start at first logon.
- Raycast Copilot-key app policy is applied, and the physical Copilot key works
  on the Surface Laptop 7.
- Everything uses the pinned ARM64 direct-download backend and quiet config.
- ViVeTool virtual desktop flyout suppression works for the YASB+thide baseline
  without Windhawk.
- Windhawk remains deferred until baseline ARM64 performance is known.

## GUI Return Criteria

GUI work resumes after the backend path has evidence from live installs:

- Profile-backed build and validation behavior is stable.
- FirstLogon and setup payloads behave idempotently on real hardware.
- Release/bootstrap can install the current product without local repo state.
- ARM64 acceptance is complete, with x64 stabilization underway or clearly
  bounded by tracked follow-up work.
