# ADR-018: Maintainer-only until portable install media is usable

**Status:** Accepted · **Date:** 2026-10-15  
**Clarifies:** [ADR-019](ADR-019-product-owned-usb-media.md) (the current Output ISO is not install media)

### Context

The current Output ISO does not install cleanly. Bare-metal boot from it is unstable. The repository still told an operator to flash that ISO and wipe a PC, and the public bootstrap read as a product other people could run.

### Rejected

Shipping the current Output ISO as install media. Treating this repository as ready for anyone other than the maintainer. Deleting the ISO compiler. Restating live-posture registry keys in markdown.

### Decision

This repository is the maintainer's working tree. It is not ready for anyone else to run.

The current operator path is **Live posture**: `post-install/` on an already-installed Windows PC.

The current **Output ISO** is unstable. Do not write it to USB. Do not boot it. Do not install from it. Wizard review, Cli, Host Apply, the primary-gate wizard, and the bootstrap say that. Gate B remains host evidence. A green Gate B does not make this ISO install media.

The goal remains portable install media that installs cleanly, with curated settings still to come. The ISO compiler stays for Hyper-V/DVD acceptance. [ADR-019](ADR-019-product-owned-usb-media.md) makes product-owned USB media the future metal install artifact.

### Review trigger

Product-owned USB media passes real Secure Boot install proof and the maintainer is confident it is ready for someone else to run.
