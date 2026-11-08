# atasOS tools

> **atasOS** — Linux From Scratch 12.3 tabanlı, KDE Plasma 6 masaüstlü Türkçe dağıtım.
>
> - **ISO indir (v32):** <https://archive.org/download/atasos-live/atasos-live-v32.iso>
>   ([sayfa](https://archive.org/details/atasos-live), [sha256](#download))
> - **Rehber (indirme, kurulum, kullanım, bilinen sorunlar):** [docs/REHBER.md](docs/REHBER.md)
> - **Kaynak kod:** <https://github.com/johntitor08/atasos-tools/releases/tag/v32-kaynak>

This repository holds the atasOS build scripts, branding, history notes and
`apm`, a prototype package manager.

## apm — atasOS Package Manager

A working prototype package manager for [atasOS](https://github.com/johntitor08),
a Linux distribution built from source. Philosophically close to XBPS/pacman:
a simple tarball package format, a real dependency resolver, and removal driven
by a recorded file list rather than guesswork.

24 tests. No Python dependencies; packages are zstd-compressed, so it needs either
the `zstd` binary or the optional `zstandard` module (`pip install .[zstd]`).

## Layout

```
apm/
  models.py       Package, Constraint, version comparison
  resolver.py     greedy + backtracking dependency resolution
  repo.py         repo index (index.json), installed DB (installed.json)
  archive.py      zstd tar handling (module, or the zstd binary as fallback)
  transaction.py  .apkg install/remove: sha256, file-ownership conflicts,
                  upgrades, all-or-nothing rollback, symlink-safe copy
  mkpkg.py        DESTDIR staging tree -> .apkg
  cli.py          apm sync / search / install / remove / list / info
tests/
  test_integration.py
```

## Package format (.apkg)

A zstd-compressed tar archive:

```
zlib-1.3.1.apkg
└── data/
    ├── usr/bin/zprog
    └── usr/lib/libz.so -> libz.so.1
```

On install, everything under `data/` is copied into the install root and the
file list is written to `installed.json`, so removal deletes exactly what the
package owns and nothing else.

## Usage

```bash
pip install .            # puts `apm` and `apm-mkpkg` on PATH
apm sync --index /path/to/index.json
apm search zlib
apm install curl --pkg-dir ./pkgs

# install into a separate root, for chroot/VM testing
apm install curl --root /tmp/test-root --pkg-dir ./pkgs

apm install foo --overwrite   # replace files on disk that no package owns
apm install foo --force       # take over files another package owns
apm install foo --allow-unverified   # index entry has no sha256

apm remove zlib          # blocked if another package depends on it
apm remove zlib --force
apm list
apm info curl
```

Building a package from an LFS-style staging directory:

```bash
make install DESTDIR=/tmp/stage
python -m apm.mkpkg --destdir /tmp/stage --name zlib --version 1.3.1 \
                    --depends "libc>=2.39" --out ./pkgs
```

## Resolvers

**`Resolver` (greedy)** takes the highest compatible version for each
constraint and never reconsiders. Fast, and enough for most trees — but it
fails when the only valid combination is not the newest-of-each one.

**`BacktrackingResolver` (default, used by the CLI)** does a CSP-style search:
candidates are tried highest first, and when a choice dead-ends downstream the
search returns to the previous decision point and tries the next candidate.
A `MAX_ATTEMPTS` circuit breaker stops pathological graphs.

The difference is covered by a test. Given:

```
app     -> libA>=1.0, libB>=1.0
libA1.0 -> shared==1.0     libA2.0 -> shared==2.0
libB1.0 -> shared==1.0     libB2.0 -> shared==3.0
```

no pairing involving a 2.0 works, so the single solution is all-1.0. Greedy
raises; backtracking finds it.

## Symlink handling

`shutil.copytree` and `copy2` follow symlinks by default, which silently turns
`libz.so -> libz.so.1.3.1` into a second full copy of the library and breaks the
SONAME chain. Every copy in `transaction.py` uses `follow_symlinks=False`, and
`test_install_preserves_symlinks_not_copies` guards against a regression.

## Transactions

`apm install` checks the whole batch before writing anything: every archive
must exist and match its sha256 (an index entry without one is refused), and
no path may collide with a file another package owns, with a file already on
disk that no package owns, or with a directory. Collisions are listed together.

Every file that gets replaced is first renamed aside (`*.apm-bak-<pid>` in the
same directory, so it is a rename, not a copy). If anything fails, every
package of the batch is rolled back: new files deleted, the originals renamed
back, created directories removed, the database restored. On success the
backups are deleted.

Installing a newer version over an installed one deletes the files the old
version owned that the new one no longer ships. `remove` never deletes a file
that another package also lists (possible after `--force`).

Archives are unpacked with tarfile's safety checks (nothing may land outside
the staging directory, also not through a symlink unpacked earlier), but file
modes are kept as packaged, so setuid binaries and sticky directories survive.

## Not implemented (on purpose)

- GPG/signature verification — only sha256 today
- Network repositories — `sync` reads a local index file
- Package scriptlets (pre/post install hooks)
- Parallel downloads

## Tests

```bash
python -m pytest tests/ -q
```

## atasOS build history

The phase info logs and session handoffs from building atasOS itself (desktop,
graphics stack, Firefox, LFS fixes, live ISO + Calamares installer, atspkg) are
in [docs/](docs/README.md).

The October–November 2026 rebuild (after the v21–v28 ISOs were lost) is in
[scripts/2026-11-rebuild/](scripts/2026-11-rebuild/README.md): the scripts that
rebuilt the system, the kernels, and the v29–v32 live ISO builders. The logo,
login theme, installer slideshow and HiDPI script are in [branding/](branding/README.md).

## Download

The current live ISO is **v32** (2026-11-08, kernel 6.16.1-atas6):
<https://archive.org/details/atasos-live>

```
sha256  f038779e36fd24f407f0d878942ee882c81de70c89068ea122049e07d57b7a08  atasos-live-v32.iso
```

Secure Boot is not supported: the ISO is unsigned, so turn Secure Boot off in
the firmware settings before booting it.

Check it with `sha256sum -c atasos-live-v32.iso.sha256`. Older ISOs (v13–v31)
are no longer published; only their builder scripts remain in this repository.

Source code for v32 (tarballs, patches, kernel config, component versions):
<https://github.com/johntitor08/atasos-tools/releases/tag/v32-kaynak>. Full Turkish guide (download,
install, use, known issues): [docs/REHBER.md](docs/REHBER.md).
