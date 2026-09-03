"""Turn a `make install DESTDIR=...` staging directory into an .apkg."""

from __future__ import annotations

import argparse
import json
import os
import sys

from .archive import write_tar_zst
from .transaction import sha256_file


def build(destdir: str, name: str, version: str, outdir: str = ".",
          description: str = "", depends: list[str] | None = None,
          conflicts: list[str] | None = None) -> tuple[str, str]:
    destdir = os.path.abspath(destdir)
    if not os.path.isdir(destdir):
        raise SystemExit(f"staging directory not found: {destdir}")

    os.makedirs(outdir, exist_ok=True)
    out = os.path.join(outdir, f"{name}-{version}.apkg")

    def add(tar):
        # arcname data/ keeps the payload namespaced inside the archive.
        # recursive=True preserves symlinks because tarfile does not follow them.
        tar.add(destdir, arcname="data", recursive=True)

    write_tar_zst(out, add)
    digest = sha256_file(out)

    meta = {
        "name": name,
        "version": version,
        "description": description,
        "depends": depends or [],
        "conflicts": conflicts or [],
        "file_url": os.path.basename(out),
        "sha256": digest,
    }
    with open(out + ".json", "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2)
    return out, digest


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="mkpkg", description="build an .apkg from a DESTDIR tree")
    ap.add_argument("--destdir", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--out", default=".")
    ap.add_argument("--description", default="")
    ap.add_argument("--depends", nargs="*", default=[])
    ap.add_argument("--conflicts", nargs="*", default=[])
    args = ap.parse_args(argv)

    path, digest = build(args.destdir, args.name, args.version, args.out,
                         args.description, args.depends, args.conflicts)
    print(f"built {path}")
    print(f"sha256 {digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
