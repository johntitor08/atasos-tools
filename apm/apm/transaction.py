"""Installing and removing packages on disk.

An install runs in two phases:

1. Preflight, for every package in the batch, before anything is written:
   the archive exists, its sha256 matches, it unpacks safely, and none of its
   paths collide with a file another package owns (or, unless ``overwrite``,
   with an unowned file already on disk).
2. Apply, package by package. Every file that would be replaced is first
   renamed aside to a backup next to it, so a failure at any point rolls the
   whole batch back: new files are deleted, backups are renamed back, created
   directories are removed and the database entries are restored.

Upgrading an installed package removes the files the old version owned that
the new version no longer ships.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import stat
import tarfile
import tempfile
from dataclasses import dataclass, field

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


def _extract_filter(member: tarfile.TarInfo, dest: str) -> tarfile.TarInfo:
    """tarfile's "tar" filter refuses anything that would land outside the
    staging directory (including through a symlink extracted earlier), but it
    also strips setuid/setgid/sticky and group/other write bits. A package
    manager must keep those (sudo is 4755, /var/tmp is 1777), so the safety
    checks are kept and the original mode is put back."""
    checked = tarfile.tar_filter(member, dest)
    if checked is not None and member.mode is not None and not member.issym():
        checked = checked.replace(mode=member.mode, deep=False)
    return checked


# ------------------------------------------------------------ staged trees

@dataclass
class _Entry:
    rel: str          # "/usr/lib/libz.so"
    src: str          # absolute path inside the staging tree
    kind: str         # "file" | "link"


def _scan(src_root: str) -> tuple[list[_Entry], list[str]]:
    """List what a staged tree installs: files and symlinks (a symlinked
    directory is one link entry and is not walked into), plus the real
    directories, parents first."""
    entries: list[_Entry] = []
    dirs: list[str] = []
    for dirpath, dirnames, filenames in os.walk(src_root):
        rel_dir = os.path.relpath(dirpath, src_root)
        if rel_dir != ".":
            dirs.append("/" + rel_dir)
        for name in sorted(dirnames):
            src = os.path.join(dirpath, name)
            if os.path.islink(src):
                dirnames.remove(name)
                entries.append(_Entry("/" + os.path.relpath(src, src_root), src, "link"))
        dirnames.sort()
        for name in sorted(filenames):
            src = os.path.join(dirpath, name)
            kind = "link" if os.path.islink(src) else "file"
            entries.append(_Entry("/" + os.path.relpath(src, src_root), src, kind))
    return entries, dirs


# ------------------------------------------------------------------ journal

@dataclass
class _Journal:
    name: str
    db_before: dict | None
    created: list[str] = field(default_factory=list)          # absolute paths
    created_dirs: list[str] = field(default_factory=list)
    backups: list[tuple[str, str]] = field(default_factory=list)  # (path, backup)


@dataclass
class _Staged:
    pkg: Package
    tmp: tempfile.TemporaryDirectory
    data_dir: str
    entries: list[_Entry]
    dirs: list[str]

    @property
    def files(self) -> list[str]:
        return [e.rel for e in self.entries]


class Transaction:
    def __init__(self, db: InstalledDB, root: str = "/", *, overwrite: bool = False,
                 force: bool = False, require_checksum: bool = False):
        """``overwrite``: replace unowned files already on disk (the system was
        not installed by apm). ``force``: also take over files another package
        owns. ``require_checksum``: refuse packages whose index entry has no
        sha256."""
        self.db = db
        self.root = os.path.abspath(root)
        self.overwrite = overwrite
        self.force = force
        self.require_checksum = require_checksum

    def _abs(self, rel: str) -> str:
        return os.path.join(self.root, rel.lstrip("/"))

    # -------------------------------------------------------------- install

    def install(self, pkg: Package, apkg_path: str) -> list[str]:
        return self.install_many([(pkg, apkg_path)])[0]

    def install_many(self, items: list[tuple[Package, str]]) -> list[list[str]]:
        staged: list[_Staged] = []
        try:
            for pkg, path in items:
                staged.append(self._stage(pkg, path))
            self._check_conflicts(staged)

            journals: list[_Journal] = []
            try:
                for st in staged:
                    journals.append(_Journal(st.pkg.name, self._db_copy(st.pkg.name)))
                    self._apply(st, journals[-1])
            except Exception as exc:
                for j in reversed(journals):
                    self._rollback(j)
                if isinstance(exc, TransactionError):
                    raise TransactionError(f"{exc} (rolled back, nothing changed)") from exc
                raise TransactionError(f"install failed: {exc} (rolled back, nothing changed)") from exc

            for j in journals:
                self._commit(j)
            return [st.files for st in staged]
        finally:
            for st in staged:
                st.tmp.cleanup()

    def _db_copy(self, name: str) -> dict | None:
        entry = self.db.entries.get(name)
        return None if entry is None else dict(entry, files=list(entry.get("files", [])))

    def _stage(self, pkg: Package, apkg_path: str) -> _Staged:
        if not os.path.exists(apkg_path):
            raise TransactionError(f"package file not found: {apkg_path}")
        if pkg.sha256:
            actual = sha256_file(apkg_path)
            if actual != pkg.sha256:
                raise TransactionError(
                    f"sha256 mismatch for {pkg.id}\n  expected {pkg.sha256}\n  got      {actual}"
                )
        elif self.require_checksum:
            raise TransactionError(f"{pkg.id}: index entry has no sha256 (refusing unverified package)")

        tmp = tempfile.TemporaryDirectory(prefix="apm-install-")
        try:
            try:
                tar = open_tar_zst(apkg_path)
            except Exception as exc:
                raise TransactionError(f"cannot read {apkg_path}: {exc}") from exc
            with tar:
                for member in tar.getmembers():
                    name = os.path.normpath(member.name)
                    if name.startswith(("..", "/")):
                        raise TransactionError(f"unsafe path in archive: {member.name}")
                if not hasattr(tarfile, "tar_filter"):
                    raise TransactionError("this Python's tarfile has no extraction filters; "
                                           "use Python >= 3.9.17 / 3.10.12 / 3.11.4 / 3.12")
                try:
                    tar.extractall(tmp.name, filter=_extract_filter)
                except tarfile.FilterError as exc:
                    raise TransactionError(f"unsafe archive {apkg_path}: {exc}") from exc

            data_dir = os.path.join(tmp.name, "data")
            if not os.path.isdir(data_dir):
                raise TransactionError(f"{pkg.id}: archive has no data/ directory")
            entries, dirs = _scan(data_dir)
            return _Staged(pkg, tmp, data_dir, entries, dirs)
        except BaseException:
            tmp.cleanup()
            raise

    def _check_conflicts(self, staged: list[_Staged]) -> None:
        owners = self.db.owners()
        problems: list[str] = []
        batch: dict[str, str] = {}

        for st in staged:
            name = st.pkg.name
            for e in st.entries:
                other = batch.get(e.rel)
                if other and other != name:
                    problems.append(f"{e.rel}: in both {other} and {name}")
                batch[e.rel] = name

                dst = self._abs(e.rel)
                owner = owners.get(e.rel)
                if os.path.isdir(dst) and not os.path.islink(dst):
                    # A symlink onto an existing directory is fine only if it
                    # is the merged-/usr case: the package ships the same link.
                    problems.append(f"{e.rel}: is a directory on disk, {name} ships a {e.kind}")
                elif owner and owner != name:
                    if not self.force:
                        problems.append(f"{e.rel}: owned by {owner} ({name} wants it; --force to take over)")
                elif not owner and os.path.lexists(dst):
                    if e.kind == "link" and os.path.islink(dst) and os.readlink(dst) == os.readlink(e.src):
                        continue  # identical link already there
                    if not self.overwrite:
                        problems.append(f"{e.rel}: exists on disk, not owned by any package "
                                        f"(--overwrite to replace)")
            for d in st.dirs:
                dst = self._abs(d)
                if os.path.lexists(dst) and not os.path.isdir(dst):
                    problems.append(f"{d}: {name} needs a directory, a file is there")

        if problems:
            shown = "\n  ".join(problems[:20])
            more = f"\n  ... and {len(problems) - 20} more" if len(problems) > 20 else ""
            raise TransactionError(f"file conflicts:\n  {shown}{more}")

    def _backup(self, path: str, journal: _Journal) -> None:
        """Rename ``path`` aside (same directory, so same filesystem)."""
        base = f"{path}.apm-bak-{os.getpid()}"
        bak, n = base, 0
        while os.path.lexists(bak):
            n += 1
            bak = f"{base}.{n}"
        os.rename(path, bak)
        journal.backups.append((path, bak))

    def _mkdirs(self, rel_dir: str, src_dir: str | None, journal: _Journal) -> None:
        path = self._abs(rel_dir)
        missing = []
        p = path
        while not os.path.lexists(p) and p != self.root:
            missing.append(p)
            p = os.path.dirname(p)
        for d in reversed(missing):
            os.mkdir(d)
            journal.created_dirs.append(d)
        if missing and src_dir is not None:
            os.chmod(path, stat.S_IMODE(os.lstat(src_dir).st_mode))  # e.g. 1777, 0700

    def _apply(self, st: _Staged, journal: _Journal) -> None:
        os.makedirs(self.root, exist_ok=True)
        for d in st.dirs:
            self._mkdirs(d, os.path.join(st.data_dir, d.lstrip("/")), journal)

        for e in st.entries:
            dst = self._abs(e.rel)
            self._mkdirs(os.path.dirname(e.rel), None, journal)
            if os.path.lexists(dst):
                if (e.kind == "link" and os.path.islink(dst)
                        and os.readlink(dst) == os.readlink(e.src)):
                    continue
                self._backup(dst, journal)
            if e.kind == "link":
                os.symlink(os.readlink(e.src), dst)
            else:
                shutil.copy2(e.src, dst, follow_symlinks=False)
            journal.created.append(dst)

        # Upgrade/reinstall: drop what the old version owned and the new one
        # does not ship (unless another package claims it).
        if journal.db_before is not None:
            new = set(st.files)
            owners = self.db.owners()
            for rel in journal.db_before.get("files", []):
                if rel in new or owners.get(rel, st.pkg.name) != st.pkg.name:
                    continue
                path = self._abs(rel)
                if os.path.islink(path) or os.path.isfile(path):
                    self._backup(path, journal)

        self.db.add(st.pkg, st.files)

    def _rollback(self, journal: _Journal) -> None:
        for path in reversed(journal.created):
            if os.path.lexists(path):
                os.unlink(path)
        for path, bak in reversed(journal.backups):
            if os.path.lexists(bak):
                os.rename(bak, path)
        for d in reversed(journal.created_dirs):
            try:
                os.rmdir(d)
            except OSError:
                pass
        if journal.db_before is None:
            if journal.name in self.db.entries:
                self.db.remove(journal.name)
        else:
            self.db.entries[journal.name] = journal.db_before
            self.db.save()

    def _commit(self, journal: _Journal) -> None:
        dirs = set()
        for path, bak in journal.backups:
            if os.path.lexists(bak):
                os.unlink(bak)
            if not os.path.lexists(path):          # an obsolete upgrade file
                dirs.add(os.path.dirname(path))
        self._prune(dirs)

    # --------------------------------------------------------------- remove

    def _prune(self, dirs) -> None:
        """Remove directories left empty, deepest first, never the root."""
        prefix = self.root.rstrip(os.sep) + os.sep
        for path in sorted(dirs, key=len, reverse=True):
            while path.startswith(prefix) and path != self.root:
                if os.path.islink(path):
                    break
                try:
                    os.rmdir(path)
                except OSError:
                    break
                path = os.path.dirname(path)

    def remove(self, name: str, force: bool = False) -> list[str]:
        if name not in self.db.entries:
            raise TransactionError(f"not installed: {name}")

        dependents = self.db.dependents_of(name)
        if dependents and not force:
            raise TransactionError(
                f"{name} is required by: {', '.join(dependents)} (use --force to remove anyway)"
            )

        owners = self.db.owners(exclude=name)
        removed = []
        files = self.db.files_of(name)
        for rel in files:
            if rel in owners:          # shared with another package (--force install)
                continue
            path = self._abs(rel)
            if os.path.islink(path) or os.path.isfile(path):
                os.unlink(path)
                removed.append(rel)

        self._prune({os.path.dirname(self._abs(f)) for f in files})
        self.db.remove(name)
        return removed
