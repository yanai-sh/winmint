# ADR-019: Product-owned USB install media

**Status:** Accepted · **Date:** 2026-10-26
**Supersedes:** [ADR-012](ADR-012-flash-outside-product-seam.md)

### Context

The Output ISO is optical UDF/El Torito media. A raw write can start its EFI image from USB while leaving the UDF payload, including `sources\install.wim`, unavailable to WinPE. Rufus ISO mode instead remasters the media and changes the boot path. Neither path preserves WinMint's WinPE apply contract.

The serviced `install.wim` is larger than FAT32's file limit. The successful media shape in the bare-metal investigation used a FAT32 boot partition and an NTFS payload partition. That investigation also exposed independent boot defects: a second USB boot could re-apply, and the installed image received the 2011-signed boot manager instead of the Windows UEFI CA 2023 manager. Those defects are fixed in the apply contract, but no current Output ISO is install media.

### Rejected

Returning to stock Setup/ConX to gain Rufus compatibility; naming Rufus or balenaEtcher as the product install path; raw-writing the optical Output ISO; relying on Rufus ISO-mode remastering; split-WIM as the first USB design; a byte-identical whole-disk digest as reproducibility proof; silent disk selection or destructive write.

### Decision

WinMint keeps the WinPE apply install engine and owns the USB media shape.

ImageServicing publishes USB media from the fully serviced staged-media tree, not by unpacking or raw-writing the Output ISO. The supported ARM64-first shape is a GPT disk with, in order:

- a FAT32 EFI boot partition containing the boot tree and `sources\boot.wim`;
- an NTFS payload partition containing the complete serviced media tree, including `sources\install.wim`.

The boot partition size is derived from its content plus bounded headroom. The writer refuses media that cannot hold both partitions and reserve space.

WinMint also owns one elevated write-and-verify path. It accepts an explicit removable-disk identity, shows stable disk facts before destruction, and binds destructive confirmation to those facts. Immediately before destruction it re-reads that identity and refuses a changed, non-USB, system, or boot disk. It partitions and copies the published media, then verifies a versioned content manifest. It never guesses among disks and never reports success after a failed native command.

Reproducibility means the same source identity, Profile, BuildPlan, and serviced payload produce the same versioned content manifest. Filesystem metadata, partition GUIDs, and volume serials are not required to be byte-identical.

The Output ISO remains for Hyper-V/DVD acceptance and is not the metal install artifact. Commodity flashers are outside the supported path. The current maintainer-only and unstable-media posture remains until the product-owned USB passes real Secure Boot install proof.

### Review trigger

Microsoft Setup becomes necessary for a supported Windows release, NTFS payload access stops working in supported WinPE, ARM64 firmware requires a different removable-media shape, or a portable partitioned image proves safer than partition-and-copy.
