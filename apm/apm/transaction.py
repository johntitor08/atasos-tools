"""Installing and removing packages on disk."""

from __future__ import annotations

import hashlib
import os
import shutil
import tempfile

from .archive import open_tar_zst
from .models import Package
from .repo import InstalledDB


class TransactionError(Exception):
    pass


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _copy_tree(src_root: str, dst_root: str) -> list[str]:
    """Copy a staged tree, preserving symlinks as symlinks.

    This matters: copytree/copy2 follow symlinks by default and would turn
    libz.so -> libz.so.1.3.1 into a second full copy of the library, breaking
    the SONAME chain. Everything here uses follow_symlinks=False.
    """
    installed: list[str] = []
    for dirpath, dirnames, filenames in os.walk(src_root):
        rel_dir = os.path.relpath(dirpath, src_root)
        target_dir = dst_root if rel_dir == "." else os.path.join(dst_root, rel_dir)

        # A symlinked directory must be recreated as a link, not walked into.
        for name in list(dirnames):
            src = os.path.join(dirpath, name)
            if os.path.islink(src):
                dirnames.remove(name)
                rel = os.path.relpath(src, src_root)
                dst = os.path.join(dst_root, rel)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                if os.path.lexists(dst):
                    os.unlink(dst)
                os.symlink(os.readlink(src), dst)
                installed.append("/" + rel)

        os.makedirs(target_dir, exist_ok=True)

        for name in filenames:
            src = os.path.join(dirpath, name)
            rel = os.path.relpath(src, src_root)
            dst = os.path.join(dst_root, rel)
            if os.path.lexists(dst):
                os.unlink(dst)
            if os.path.islink(src):
                os.symlink(os.readlink(src), dst)
            else:
                shutil.copy2(src, dst, follow_symlinks=False)
            installed.append("/" + rel)
    return installed


class Transaction:
    def __init__(self, db: InstalledDB, root: str = "/"):
        self.db = db
        self.root = os.path.abspath(root)

    def install(self, pkg: Package, apkg_path: str) -> list[str]:
        if not os.path.exists(apkg_path):
            raise TransactionError(f"package file not found: {apkg_path}")

        if pkg.sha256:
            actual = sha256_file(apkg_path)
            if actual != pkg.sha256:
                raise TransactionError(
                    f"sha256 mismatch for {pkg.id}\n  expected {pkg.sha256}\n  got      {actual}"
                )

        with tempfile.TemporaryDirectory(prefix="apm-install-") as tmp:
            try:
                tar = open_tar_zst(apkg_path)
            except Exception as exc:
                raise TransactionError(f"cannot read {apkg_path}: {exc}") from exc
            with tar:
                for member in tar.getmembers():
                    name = os.path.normpath(member.name)
                    if name.startswith(("..", "/")):
                        raise TransactionError(f"unsafe path in archive: {member.name}")
                try:
                    tar.extractall(tmp, filter="tar")
                except TypeError:  # Python < 3.12 has no filter argument
                    tar.extractall(tmp)

            data_dir = os.path.join(tmp, "data")
            if not os.path.isdir(data_dir):
                raise TransactionError(f"{pkg.id}: archive has no data/ directory")

            os.makedirs(self.root, exist_ok=True)
            files = _copy_tree(data_dir, self.root)

        self.db.add(pkg, files)
        return files

    def remove(self, name: str, force: bool = False) -> list[str]:
        if name not in self.db.entries:
            raise TransactionError(f"not installed: {name}")

        dependents = self.db.dependents_of(name)
        if dependents and not force:
            raise TransactionError(
                f"{name} is required by: {', '.join(dependents)} (use --force to remove anyway)"
            )

        removed = []
        files = self.db.files_of(name)
        for rel in files:
            path = os.path.join(self.root, rel.lstrip("/"))
            if os.path.lexists(path):
                if os.path.islink(path) or os.path.isfile(path):
                    os.unlink(path)
                    removed.append(rel)

        # Prune directories that the package left empty.
        for rel in sorted({os.path.dirname(f) for f in files}, key=len, reverse=True):
            path = os.path.join(self.root, rel.lstrip("/"))
            while path.startswith(self.root) and path != self.root:
                try:
                    os.rmdir(path)
                except OSError:
                    break
                path = os.path.dirname(path)

        self.db.remove(name)
        return removed
