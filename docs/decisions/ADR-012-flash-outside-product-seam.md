# ADR-012: Flash is outside the product seam

**Status:** Accepted  
**Date:** 2026-08-12  
**Related:** [CONTEXT](../../CONTEXT.md) (Output ISO, Flash, Gate B), [DESIGN](../DESIGN.md)

### Context

WinMint could treat a bootable USB stick as the compile output and write disks itself (or shell out to Rufus/Etcher). That would close “ISO ready → stick” in one host app, but USB write is a solved, liability-heavy commodity with a Windows-specific footgun (Rufus **ISO mode** remasters; LaunchApply media needs a raw **DD Image** write).

### Decision

The delivery artifact is the **Output ISO** (`out.iso` + digests). **Flash** (writing that ISO to UEFI removable media) is **operator hygiene**, outside ImageServicing / Orchestrator / Wizard Apply — parallel to restore images, not a WinMint download or disk writer.

Product surfaces may show **guidance copy only**: Output ISO path, **Rufus** in **DD Image** mode (not ISO mode), `digests.outputIso.sha256`, boot expects WinPE LaunchApply. No disk enumeration, no raw write, no Rufus fork, no required launch of an external flasher.

### Consequences

- Gate B proves pre-wipe Output ISO evidence; Flash is still not Primary.
- Score / operator docs treat external Rufus DD as an accepted step, not a missing feature.
- Revisit only with documented Primary failure from wrong flash mode / bad media write, or a deliberate product shift to “Profile → stick in one host app” (new ADR).

### Review trigger

Documented wipe failure caused by flash/media write; or product ambition changes to non-technical one-click USB as a first-class deliverable.
