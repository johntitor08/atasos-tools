# atasOS rebuild scripts (October–November 2026)

The v21–v28 ISOs were lost when a CachyOS installer erased the disk that held
them. These scripts rebuilt atasOS on its partition (`/dev/nvme0n1p5`, LFS 12.3 +
KDE Plasma 6) from a Kubuntu host, then produced the v29–v34 live ISOs. Only the newest
is still published (archive.org item `atasos-live`); the older ISOs were deleted.

They are kept as they were run. Paths, partition numbers and UUIDs refer to the
original laptop; read a script before running it anywhere else.

## Conventions

- Every script runs as root from the host: `sudo bash atasos-NN-*.sh`.
- They mount p5 at `/mnt/atasos`, take a shared lock (`/run/atasos-betik.lock`) so
  two scripts never run at once, and unmount on exit.
- Files they change are copied first to `/var/lib/atasos-paketler/yedek-NN-<date>/`
  (or a `.yedek-<date>` file next to the original).
- Messages are in Turkish (ASCII only, so they read correctly on any console).

## Main steps

| Scripts | What they do |
|---------|--------------|
| 6–19 | First boot to SDDM, polkit, groups, module loading, X wrapper |
| 20–29 | Firefox + Mesa iris, GTK3 chain, Wi-Fi (wpa_supplicant), GRUB gfxpayload |
| 30–39 | EFI entries, libGL, DNS (systemd-resolved), audio, panel shortcuts, base tools |
| 40–43 | KAuth with the polkit backend (brightness), transplant of groups B2 and C from the v20 ISO (Calamares, GRUB tools) |
| 44 | **v29 live ISO** builder (overlay over p5, squashfs zstd, busybox initramfs, grub-mkrescue BIOS+UEFI) |
| 45, 48 | Kernels 6.16.1-atas4 and -atas5 (HDMI audio, camera, Huawei WMI, thermal, FUSE, Intel PMC) |
| 46–47 | os-prober 1.85, libfuse 3, grub-mount (installer lists other operating systems) |
| 49–55 | Python ctypes, Firefox/cursor/login-screen scaling, single GRUB entry, menu icon and language fixes |
| 56 | Branding and desktop improvements: logo, SDDM theme with Turkish on-screen keyboard, automatic HiDPI scaling |
| 57 | **v30 live ISO** builder (v29 + Calamares removed after install, sudo for the installed user, fixes found in VM testing) |
| 58 | Kernel 6.16.1-atas6: AMD (amdgpu, radeon), NVIDIA (nouveau), VM display drivers, AMD laptop support, MediaTek/Realtek Wi-Fi, UAS, `/proc/config.gz` |
| 59 | Desktop: atasOS wallpaper (also the Plasma and look-and-feel default), Breeze Dark with the atasOS blue accent, panel logo and launchers, GRUB theme, login theme update, touchpad tap-to-click |
| 60 | **v31 live ISO** builder (v30 + atas6 + desktop theme; live system can also boot from an ISO file on a disk partition with `atasos.iso=`, installer disabled in that mode; adds a Kubuntu GRUB entry for it) |
| 61 | Write the newest ISO to a USB stick (USB disks only, typed device name + confirmation, checksum before and read-back after) |
| 62 | **v32 live ISO** builder: v31 with the Plasma Wayland session hidden on the login screen (it does not start on atasOS, and SDDM preselected it for new users) |
| 63 | Upload the newest ISO to the archive.org item `atasos-live` (resumable, `--retries 10`), verify the download URL (HTTP 200, exact size, `.sha256`), then ask one by one whether to delete older ISOs (permanently, `--no-backup`) |
| 64 | Collect the GPL source package for v32 (p5 mounted read-only): every source tarball and LFS patch used, the atas6 kernel config (and a check that the kernel tree is unpatched), version lists of all installed libraries and CMake packages, `SHA256SUMS`. Published as the GitHub release `v32-kaynak` (archive.org darkened its upload: VirusTotal flagged the unmodified upstream `libXpm-3.5.17.tar.xz`, whose test pixmaps are deliberately malformed) |
| 65 | Flatpak 1.16.1 for Steam, built from source in a chroot on p5 (`atasos-65-flatpak-derle.sh` runs inside): libseccomp, yaml, the GnuPG chain (npth, libassuan, libksba, gnupg, gpgme), libxmlb, AppStream, bubblewrap, xdg-dbus-proxy, libostree, pyparsing, flatpak. Each package is installed through a DESTDIR with a file list and an overwrite check. Then the `flatpak` system user, `XDG_DATA_DIRS` for the Plasma session and the Flathub remote (system-wide). Flatpak apps cannot be installed from a chroot (no user namespaces there), so Steam itself is installed from the running system |
| 66 | **v33 live ISO** builder: v32 + Flatpak and the Flathub remote (from 65). Checks that flatpak, bwrap, gpg, the `flatpak` user and Flathub are in the image and that no installed Flatpak app or runtime slipped into it. Tested live in a VM: unprivileged bubblewrap, Flathub GPG verification, a runtime installed system-wide from the desktop session and a command run in its sandbox |
| 67 | Claude Code on atasOS: runs Anthropic's official installer (`claude.ai/install.sh`) in a chroot on p5 as the user `eren` (installs `~/.local/bin/claude`) and adds `~/.local/bin` to `~/.bashrc`. No credentials are copied; sign-in happens on first run |
| 68 | Kubuntu GRUB: one atasOS entry. "atasOS" now boots the atas6 kernel and the separate atas6 test entry is removed; the live-ISO entry (rewritten by every ISO builder for the newest ISO) stays |
| 69 | Try the installer yourself in a VM (QEMU/KVM, UEFI, a GTK window; no root): the VM sees only the ISO and a 20 GB virtual disk under `/veri/atasos-iso/vm-kurulum/`, never the real disks. `kurulu` boots the installed virtual disk, `sifirla` empties it, `sil` removes the test folder. Fixed 1280x800 display (std VGA + EDID): with virtio-vga the GTK window passed its initial 640x480 size to the guest |
| 70 | **v34 live ISO** builder: v33 with two installer fixes found by installing v33 in a VM. Calamares accepted an empty password, and the installed system could not be logged into (PAM has no `nullok`, root stays locked): now `passwordRequirements: minLength: 1` with weak passwords not allowed (Calamares 3.3.14 ignores `nonempty: true`). The "log in automatically" checkbox did nothing because the `displaymanager` job never ran: it now runs after `shellprocess` and writes `[Autologin]` to `/etc/sddm.conf`. Both checked by the builder and tested in a VM |

## Installer disk safety

The CachyOS incident is why the ISO builders force
`initialPartitioningChoice: none` (no partitioning option is preselected) and
`prompt-install: true` (a final confirmation before anything is written), and
check both before producing an ISO.
