# ADR-012: Flash is outside the product seam

**Status:** Superseded by [ADR-019](ADR-019-product-owned-usb-media.md) · **Date:** 2026-08-12

### Context

Closing “ISO ready → USB” in-process looks convenient. USB write is a solved, liability-heavy commodity. Rufus **ISO mode** remasters; LaunchApply media needs a raw **DD Image** write.

### Rejected

In-process raw write, Rufus fork, “any flasher” as the named recipe, treating Flash as Primary, Authenticode on the ISO container or the USB.

### Decision

The deliverable is the **Output ISO** + digests. **Flash** is operator hygiene: Rufus **DD Image** mode, check SHA. Product copy may name that recipe. No disk enumeration, no write, no required launch of an external flasher.

### Review trigger

Documented wipe failure from wrong flash mode, or a deliberate product shift to “Profile → stick in one host app.”

The trigger fired during the 2026-10 bare-metal investigation: raw-written optical media booted without a usable payload, while ISO-mode remastering changed the boot path. ADR-019 owns the replacement decision.
