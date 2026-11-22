# ADR-020: Install file before the install engine erases a disk

**Status:** Accepted · **Date:** 2026-11-22
**Clarifies:** [ADR-018](ADR-018-maintainer-only-until-usable.md), [ADR-019](ADR-019-product-owned-usb-media.md)

### Context

On this Surface Laptop 7 the install engine's one remaining fixed disk is the internal NVMe. Primary's bar is unmet. A boot probe already shuts down before it selects a target disk. The apply window cannot ask a question: the host starts the launcher with no console, and stock Setup stays off this path.

### Rejected

Erasing that one remaining disk with no further permission. An on-screen disk pick. Treating the reinstall marker as the permission to clean. Letting this permission override a boot probe, pick between two disks, or count as Primary proof. Planting the permission from USB publish or from the probe image. Deleting the permission on use.

### Decision

The install engine erases a disk only when the maintainer has put an install file on the payload. Without it, the engine shuts down before it selects a target disk.

A boot probe still shuts down first, and does not select a disk, even if the install file is also there. Two remaining disks still stop. The reinstall marker is still only a deliberate second erase, and only when the install file is present too. The file stays until the maintainer removes it.

This is permission for this machine while Primary's bar is unmet. It does not make the Output ISO install media, and it does not meet Primary.

### Review trigger

The permission should be consumed on use, a second fixed disk should become an unattended target, or Primary's bar is met and this file is no longer the permission.
