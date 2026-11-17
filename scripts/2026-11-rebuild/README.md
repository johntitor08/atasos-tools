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
| 72 | Install v34 onto the real disk from Kubuntu, without Calamares (the developer's machine has no USB): writes only to an empty ext4 partition labelled `atasos-kurulu` (20–40 GiB, made beforehand by shrinking the data partition), checks the ISO's sha256, unpacks the squashfs, runs the same live-cleanup script as Calamares, creates the user (the password is typed into `passwd`; an empty one is refused), sudo, hostname, locale, fstab, optional autologin, and a Kubuntu GRUB entry with `root=PARTUUID=` |
| 73 | Installer test on a **virtual NVMe disk** laid out like the real one (EFI, data, empty target, Kubuntu, atasOS; same order and labels) with marker files on every partition and a fake Kubuntu `EFI/BOOT/BOOTX64.EFI` (written with mtools taken from the ISO; no root). `denetle` reports partition table changes, alignment, whether every marker survived, what landed in the EFI partition, and the installed system's fstab, GRUB `root=`, users and autologin. Used to test all four Calamares partitioning choices on v34 and v35 |
| 74 | **v35 live ISO** builder: v34 with fixes found by 73. Calamares wrote `EFI/boot/bootx64.efi` with every partitioning choice, overwriting another system's fallback loader (on the real disk, Kubuntu's shim): now `installEFIFallback: false`, and the live-cleanup script copies atasOS's GRUB there only if no fallback exists. The installed GRUB used `root=/dev/nvme0n1pN` (no initramfs, so no `UUID=`): now `GRUB_DISABLE_LINUX_PARTUUID=false` gives `root=PARTUUID=`. `/tcl-backup` is excluded. All checked by the builder; tested on the virtual NVMe with "replace a partition" (fake Kubuntu fallback kept) and "erase disk" (fallback written), both boot |
| 75 | Leaves a single atasOS entry in Kubuntu's GRUB menu (the installed system): moves the development-system and live-ISO entries to `/etc/grub.d-atasos-yedek/` (restorable) and checks `grub.cfg` afterwards. Note: the 74 builder rewrites the live-ISO entry at the end, so a later builder should drop that step |
| 76 | Reinstall onto the `atasos-kurulu` partition (v34 → **v35**): like 72, but the target may hold a previous install. It only proceeds if label, PARTUUID, start sector and size all match the expected partition, shows what is on it, optionally backs up `/home` to the data partition (file count checked), asks for `evet`, then reformats **with the same UUID** (`mkfs.ext4 -U`; partition table untouched) so the GRUB entry keeps working. `/boot/efi` is not mounted in the chroot, so the EFI partition is never touched |
| 77, 79 | Earlier v36 builder attempts (superseded by 81): 77 stopped at a yaml-cpp build error (0.8.0 does not compile with GCC 15; only its headers are needed) and a wrong patch check; 79 added the update-channel trust foundation but its insecure-download check matched a comment. Kept as they were run |
| 78 | Creates the **package-repository signing key** (ed25519, passphrase typed into gpg's own prompt, no root) in `~/.atasos-depo-imza` (never published) and exports the public key; test-signs and verifies with the public key only. Public key: [`atasos-depo-anahtari.asc`](atasos-depo-anahtari.asc), fingerprint `0D5A 09FA 2D63 998C 3936  430C AD37 7A27 2348 72E2` |
| 80 | Signs the repository index (`atspkg.index`) on archive.org: first checks every listed package's sha256 against the file on archive.org, signs (passphrase), verifies with the public key, uploads `atspkg.index.sig` only after a typed `evet` |
| 81 | **v36 live ISO** builder: v35 plus a **patched Calamares 3.3.14** compiled from the official source inside the overlay (p5 untouched; kpmcore 25.04.3 and yaml-cpp 0.8.0 headers only for the build; [`atasos-calamares-3.3.14.patch`](atasos-calamares-3.3.14.patch)): "install alongside" partitions start on a 1 MiB boundary, the size slider cannot default below the data on the partition, the final "install now?" prompt names the disk in red for "erase disk", and LUKS encryption is hidden in automatic and manual partitioning (no initramfs, an encrypted root cannot boot). Also a "Firefox'u Güncelle" menu entry (Mozilla's signed release, pinned key), [`atspkg 0.3.0`](atspkg-0.3.0) (index must be signed with the repository key, TLS always verified), and a hidden GRUB menu when the disk has no other OS. Tested on the virtual NVMe (73) |
| 82 | **Update-channel package builder**: p5 read-only + a throwaway overlay; checks every source archive against [`paketler/DOGRULANMIS.txt`](paketler/DOGRULANMIS.txt) (upstream signatures verified: OpenSSL `B146 647E…2D40`, curl `27ED EAF2…12C2`, sudo `59D1 E9CC…70FB`), builds each [recipe](paketler/tarifler/) with `atspkg derle` in a chroot, rejects packages that would overwrite configuration (`/etc/sudoers`, `/etc/ssl/openssl.cnf` …), checks setuid and RPATH leaks, then installs them into the same throwaway layer and runs a smoke test (versions, real TLS to archive.org, `visudo -c`, `ldd`). Notes: v36's OpenSSL exists twice (`/usr/lib` and `/usr/lib64`, identical), so the package updates both; sudo was built **without PAM** and must stay so |
| 83, 84, 85 | **Publishing** to archive.org `atasos-depo`: verifies the current index signature first, refuses an already published name+version+release, asks for `evet`, uploads packages (84 skips ones already present with the same sha256), checks them back from archive.org, then signs the new index with the repository key and uploads index + signature. 85 only signs and uploads the index (archive.org was slow to show new files) |

## Installer disk safety

The CachyOS incident is why the ISO builders force
`initialPartitioningChoice: none` (no partitioning option is preselected) and
`prompt-install: true` (a final confirmation before anything is written), and
check both before producing an ISO.
