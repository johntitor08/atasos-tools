# apm — atasOS Package Manager

A working prototype package manager for [atasOS](https://github.com/johntitor08),
a Linux distribution built from source. Philosophically close to XBPS/pacman:
a simple tarball package format, a real dependency resolver, and removal driven
by a recorded file list rather than guesswork.

15 tests, no third-party runtime dependencies.

## Layout

```
apm/
  models.py       Package, Constraint, version comparison
  resolver.py     greedy + backtracking dependency resolution
  repo.py         repo index (index.json), installed DB (installed.json)
  archive.py      zstd tar handling (module, or the zstd binary as fallback)
  transaction.py  .apkg install/remove, sha256 verification, symlink-safe copy
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
apm sync --index /path/to/index.json
apm search zlib
apm install curl --pkg-dir ./pkgs

# install into a separate root, for chroot/VM testing
apm install curl --root /tmp/test-root --pkg-dir ./pkgs

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

## Not implemented (on purpose)

- GPG/signature verification — only sha256 today
- Network repositories — `sync` reads a local index file
- Package scriptlets (pre/post install hooks)
- Parallel downloads

## Tests

```bash
python -m pytest tests/ -q
```
