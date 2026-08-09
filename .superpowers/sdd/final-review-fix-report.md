# Final review fix report

## Status

Resolved the critical and important findings for `feat/wizard-calm-oobe`.

## Fixes

- PlanDiff now places AppX removals in the venue the plan actually uses: offline removals under image build, online removals after first sign-in with the always-on AppX safety-net job.
- Winget imports now render one receipt row per package and distinguish product constants from user selections.
- FancyWM remains visible but disabled as “Coming soon”; disabled or direct chip resolution cannot emit its unverified winget identifier.
- The Account step again exposes final DMA locale, Geo ID, time zone, location-services settings, and “Use this PC region.”
- The workstation-compiler spec now documents the current always-network plan posture.

## Validation

`just check` passed on native arm64 .NET test output.
