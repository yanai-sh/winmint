# ADR-003: DMA interop fixed internal region

**Status:** Accepted  
**Date:** 2026-07-18  
**Origin:** WinMint v1 ADR-006 (same decision; renumbered for this repo)

### Context

Windows 11 Setup DMA (Digital Markets Act) interop affects default apps and promotional payloads during install. Smoke includes DMA; FirstLogon must restore the user’s visible region.

### Decision

Unless explicitly disabled in the Profile, Setup uses **Ireland / `en-IE` / GeoID `68`** internally. No EEA country picker. FirstLogon **restores** user-configured visible region, locale, time zone, and location posture **before** further live-user / agent work.

### Consequences

- Orchestrator unattend generation must latch setup locales to Ireland when DMA is on.
- Payload FirstLogon must implement restore as an ordered step under the provisioning lock.
- Smoke evidence must show restore succeeded (not only that Setup finished).

### Review trigger

Microsoft removes or changes DMA region requirements.
