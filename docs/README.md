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

## Session handoffs, phases A–C (`history/`)

Continuation prompts written at the end of build sessions, in order. They cover
the work before Phase D: the Plasma 6 desktop, ALSA, LLVM 22 + SPIRV and the
Mesa iris/radeonsi rebuild, kernel work, and getting Firefox 152 running.

| File | Date | Main topics |
|------|------|-------------|
| [01-2026-07-04-plasma-desktop.md](history/01-2026-07-04-plasma-desktop.md) | 2026-07-04 | First working Plasma 6 desktop, VM snapshots, Mesa/kernel plans |
| [02-2026-07-10-alsa.md](history/02-2026-07-10-alsa.md) | 2026-07-10 | alsa-lib/alsa-utils 1.2.14, `/usr/lib` vs `/usr/lib64` split |
| [03-2026-07-10-llvm-mesa.md](history/03-2026-07-10-llvm-mesa.md) | 2026-07-10 | LLVM 22, SPIRV tools, libclc, Mesa iris+radeonsi patching |
| [04-2026-07-10-llvm-mesa-kernel.md](history/04-2026-07-10-llvm-mesa-kernel.md) | 2026-07-10 | Same session, later revision with more kernel notes |
| [05-2026-07-16-firefox.md](history/05-2026-07-16-firefox.md) | 2026-07-16 | Firefox 152 working, QEMU boot command, Wi-Fi/GTK |

## Working notes (`notes/`)

Shorter summaries with the gotchas that cost the most time.

- [lfs-build-defects.md](notes/lfs-build-defects.md)
- [phase-d-live-iso.md](notes/phase-d-live-iso.md): ISO pipeline, Calamares config traps, strip/setuid hazards, VM test recipes
- [phase-e-atspkg.md](notes/phase-e-atspkg.md)
