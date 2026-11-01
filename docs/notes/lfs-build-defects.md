# lfs-build-defects

> LFS disk images in ~/Belgeler/lfs have build-time defects (bad ownership, /sbin layout, fs error flag)

The Linux From Scratch 12.3 images in `/home/eren/Belgeler/lfs` have three build-time defects, discovered 2026-07-16:

1. **Ownership**: system directories (`/usr`, `/usr/bin`, `/usr/sbin`, `/usr/lib`, `/usr/libexec`, `/var`, `/usr/share`, `/usr/include`, ...) are owned by the guest user `eren` (uid/gid **1001**) instead of `root`. Files inside are root-owned; it's the directory nodes that are wrong. Writable binary dirs = local privilege escalation. Correct fix: `chown -R root:root /usr` + `find /var /etc /opt /srv -uid 1001 -exec chown root:root {} +`.
2. **`/sbin` was a real directory** instead of the merged-`/usr` symlink `/sbin -> usr/sbin`. Caused by `ln -s usr/sbin /sbin` running while `/sbin` already existed (produced a stray `/sbin/sbin` link). This caused the original `boot.log` `modprobe@*.service: Unable to locate executable '/sbin/modprobe'` failures; worked around later with manual kmod symlinks.
3. **Root fs error flag**: mounts with "running e2fsck is recommended". systemd-fsck-root is skipped because the kernel cmdline mounts root `rw` (`ConditionPathIsReadWrite=!/`). Fix: boot once with `ro` on the cmdline, or e2fsck offline.

Images: `lfs.img` (raw, secondary — **all three fixed offline via e2fsck+debugfs on 2026-07-16**), `lfs.qcow2` (the LIVE running VM disk = distro "atasOS 1.0", hostname atasos, standalone qcow2 with 5 internal snapshots; same fs UUID cf3cf64c as lfs.img), `lfs-backup-working-plasma6-20260702.img` (backup).

Status on live qcow2 — **ALL FIXED as of 2026-07-16**. Bug 2 ownership fixed from inside running guest as root (`chown -R root:root /usr /sbin /opt /srv /etc` + `find /var -xdev -uid 1001 -exec chown root:root {} +`). Bug 3 not present (live boot log mounts clean, no error flag). Bug 1 /sbin fixed offline via qemu-nbd: VM powered off, `sudo qemu-nbd --connect=/dev/nbd0 lfs.qcow2` (whole-disk ext4, no partitions), e2fsck + mount + replaced /sbin dir with symlink->usr/sbin (preserved nologin), final e2fsck clean, disconnected. qcow2 has 5 internal snapshots as rollback.

Notes: no passwordless sudo on host; `!` prefix can't do interactive sudo (no TTY); qcow2 locks while VM runs. Guest root is NOT in sudoers (doesn't need it). Inspect raw images read-only with `debugfs -R "..." lfs.img` (no mount/root needed).
