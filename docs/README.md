# atasOS build history

Records from building atasOS (Linux From Scratch 12.3 + KDE Plasma 6, systemd,
kernel 6.16.1) in July 2026. They are kept as they were written at the time:
paths such as `~/Belgeler/lfs` and VM snapshot numbers refer to the original
build host.

## Phase info logs (`phases/`)

The full narrative for each phase: goal, steps, defects and fixes.

| File | Phase | Date |
|------|-------|------|
| [phase-0-lfs-fixes-info-log.txt](phases/phase-0-lfs-fixes-info-log.txt) | Fixes to the LFS base image: ownership, `/sbin` layout, filesystem error flag | 2026-07-16 |
| [phase-d-live-iso-info-log.txt](phases/phase-d-live-iso-info-log.txt) | D: installability. Live ISO (squashfs + overlay, BIOS+UEFI) and the Calamares installer | 2026-07-17/18 |
| [phase-e-atspkg-info-log.txt](phases/phase-e-atspkg-info-log.txt) | E: the atspkg package manager, the v14 ISO, and the archive.org package repository | 2026-07-19 |

## Working notes (`notes/`)

Shorter summaries with the gotchas that cost the most time.

- [lfs-build-defects.md](notes/lfs-build-defects.md)
- [phase-d-live-iso.md](notes/phase-d-live-iso.md): ISO pipeline, Calamares config traps, strip/setuid hazards, VM test recipes
- [phase-e-atspkg.md](notes/phase-e-atspkg.md)
