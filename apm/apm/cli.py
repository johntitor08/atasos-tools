"""Command line interface: apm sync/search/install/remove/list/info."""

from __future__ import annotations

import argparse
import os
import sys

from .models import Constraint
from .repo import DEFAULT_DB_PATH, DEFAULT_REPO_CACHE, InstalledDB, RepoIndex
from .resolver import BacktrackingResolver, ResolutionError
from .transaction import Transaction, TransactionError


def cmd_sync(args) -> int:
    count = RepoIndex().sync(args.index, args.cache)
    print(f"synced {count} packages -> {args.cache}")
    return 0


def cmd_search(args) -> int:
    repo = RepoIndex.load(args.cache)
    hits = repo.search(args.term)
    if not hits:
        print("no match")
        return 1
    for pkg in hits:
        print(f"{pkg.name:<20} {pkg.version:<10} {pkg.description}")
    return 0


def cmd_install(args) -> int:
    repo = RepoIndex.load(args.cache)
    db = InstalledDB(args.db)

    resolver = BacktrackingResolver(repo.packages, db.as_packages())
    try:
        resolution = resolver.resolve(args.packages)
    except ResolutionError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if not resolution.install_order:
        print("nothing to do (already installed)")
        return 0

    print("install order: " + " ".join(p.id for p in resolution.install_order))
    if args.dry_run:
        return 0

    tx = Transaction(db, args.root, overwrite=args.overwrite, force=args.force,
                     require_checksum=not args.allow_unverified)
    items = [(pkg, os.path.join(args.pkg_dir, pkg.filename)) for pkg in resolution.install_order]
    try:
        results = tx.install_many(items)
    except TransactionError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    for pkg, files in zip(resolution.install_order, results):
        print(f"installed {pkg.id} ({len(files)} files)")
    return 0


def cmd_remove(args) -> int:
    db = InstalledDB(args.db)
    tx = Transaction(db, args.root)
    try:
        removed = tx.remove(args.package, force=args.force)
    except TransactionError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(f"removed {args.package} ({len(removed)} files)")
    return 0


def cmd_list(args) -> int:
    db = InstalledDB(args.db)
    if not db.entries:
        print("no packages installed")
        return 0
    for name, entry in sorted(db.entries.items()):
        print(f"{name:<20} {entry['version']:<10} {len(entry.get('files', []))} files")
    return 0


def cmd_info(args) -> int:
    db = InstalledDB(args.db)
    entry = db.entries.get(args.package)
    if entry:
        print(f"name        {entry['name']}")
        print(f"version     {entry['version']}")
        print(f"state       installed")
        print(f"description {entry.get('description', '')}")
        print(f"depends     {', '.join(entry.get('depends', [])) or '-'}")
        print(f"files       {len(entry.get('files', []))}")
        return 0

    repo = RepoIndex.load(args.cache)
    c = Constraint.parse(args.package)
    pkg = repo.find(c.name)
    if not pkg:
        print(f"unknown package: {args.package}", file=sys.stderr)
        return 1
    print(f"name        {pkg.name}")
    print(f"version     {pkg.version}")
    print(f"state       available")
    print(f"description {pkg.description}")
    print(f"depends     {', '.join(pkg.depends) or '-'}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="apm", description="atasOS package manager")
    ap.add_argument("--cache", default=DEFAULT_REPO_CACHE, help="repo index cache path")
    ap.add_argument("--db", default=DEFAULT_DB_PATH, help="installed package database")
    sub = ap.add_subparsers(dest="command", required=True)

    p = sub.add_parser("sync", help="fetch/refresh the repository index")
    p.add_argument("--index", required=True)
    p.set_defaults(func=cmd_sync)

    p = sub.add_parser("search", help="search packages")
    p.add_argument("term")
    p.set_defaults(func=cmd_search)

    p = sub.add_parser("install", help="install packages and their dependencies")
    p.add_argument("packages", nargs="+")
    p.add_argument("--root", default="/", help="install root (for chroot/VM testing)")
    p.add_argument("--pkg-dir", default=".", help="directory holding the .apkg files")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--overwrite", action="store_true",
                   help="replace files already on disk that no package owns")
    p.add_argument("--force", action="store_true",
                   help="take over files owned by another package")
    p.add_argument("--allow-unverified", action="store_true",
                   help="install packages whose index entry has no sha256")
    p.set_defaults(func=cmd_install)

    p = sub.add_parser("remove", help="remove an installed package")
    p.add_argument("package")
    p.add_argument("--root", default="/")
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=cmd_remove)

    p = sub.add_parser("list", help="list installed packages")
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("info", help="show package details")
    p.add_argument("package")
    p.set_defaults(func=cmd_info)
    return ap


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
