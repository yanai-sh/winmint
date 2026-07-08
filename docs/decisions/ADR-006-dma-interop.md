# ADR-006: DMA interop fixed internal region

**Status:** Accepted  
**Date:** 2026-07-07

### Context

Windows 11 Setup DMA (Device Migration Assistant) interop affects default apps and promotional payloads during install. WinMint debloats via DMA-aware removal paths.

### Decision

Unless `-Dma Off` / `posture.setup.dmaInterop = false`, Setup uses **Ireland / en-IE / GeoID 68** internally. No EEA country picker. FirstLogon **restores** user-configured visible region, locale, time zone, and location posture before agent work.

### Consequences

Fixed-region setup reduces OOBE variance; restore step is mandatory ordering in FirstLogon.

### Review trigger

If Microsoft removes DMA interop or changes region requirements.
