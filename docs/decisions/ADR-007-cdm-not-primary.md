# ADR-007: CDM is not primary

**Status:** Accepted · **Date:** 2026-08-05 · **Updated:** 2026-08-11

### Context

HKCU `ContentDeliveryManager` DWORD lists are a community trick: reset-prone, not edition-guaranteed on Pro, and a different failure mode from still-provisioned AppX.

### Rejected

Per-user CDM spray as the main debloat control. Leftover-confidence *product* cleanup as a product era.

### Decision

Primary control is offline ImageServicing remove + evidence, with a narrow FirstLogon AppX safety-net when the Profile list is non-empty.

HKLM CloudContent / Store AutoDownload **policy** stamps are product-constant FU posture ([ADR-009](ADR-009-product-constant-policies.md)) — not CDM-as-primary.

Making per-user CDM primary needs a new ADR.

### Review trigger

A supported, durable, Pro-safe CDM surface appears that is worth being primary.
