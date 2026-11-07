"""Repository index and the installed-package database."""

from __future__ import annotations

import json
import os
import tempfile

from .models import Package

DEFAULT_DB_PATH = "/var/lib/apm/installed.json"
DEFAULT_REPO_CACHE = "/var/cache/apm/index.json"


def atomic_write_json(path: str, data) -> None:
    """Write JSON via a temp file + rename, so a crash never leaves a
    half-written database behind."""
    directory = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".apm-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2, ensure_ascii=False)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


class RepoIndex:
    """All packages known to the repository, keyed by name."""

    def __init__(self, packages: dict[str, list[Package]] | None = None):
        self.packages: dict[str, list[Package]] = packages or {}

    @classmethod
    def load(cls, path: str = DEFAULT_REPO_CACHE) -> "RepoIndex":
        if not os.path.exists(path):
            raise FileNotFoundError(f"repo index not found: {path} (run 'apm sync' first)")
        with open(path, encoding="utf-8") as fh:
            raw = json.load(fh)
        index: dict[str, list[Package]] = {}
        for entry in raw.get("packages", []):
            pkg = Package.from_dict(entry)
            index.setdefault(pkg.name, []).append(pkg)
        return cls(index)

    def sync(self, source: str, cache: str = DEFAULT_REPO_CACHE) -> int:
        with open(source, encoding="utf-8") as fh:
            raw = json.load(fh)
        atomic_write_json(cache, raw)
        return len(raw.get("packages", []))

    def search(self, term: str) -> list[Package]:
        term = term.lower()
        hits = []
        for versions in self.packages.values():
            for pkg in versions:
                if term in pkg.name.lower() or term in pkg.description.lower():
                    hits.append(pkg)
        return sorted(hits, key=lambda p: p.name)

    def find(self, name: str, version: str | None = None) -> Package | None:
        for pkg in self.packages.get(name, []):
            if version is None or pkg.version == version:
                return pkg
        return None


class InstalledDB:
    """What is currently installed, and which files each package owns."""

    def __init__(self, path: str = DEFAULT_DB_PATH):
        self.path = path
        self.entries: dict[str, dict] = {}
        self.load()

    def load(self) -> None:
        if os.path.exists(self.path):
            with open(self.path, encoding="utf-8") as fh:
                self.entries = json.load(fh)
        else:
            self.entries = {}

    def save(self) -> None:
        atomic_write_json(self.path, self.entries)

    def add(self, pkg: Package, files: list[str]) -> None:
        entry = pkg.to_dict()
        entry["files"] = files
        self.entries[pkg.name] = entry
        self.save()

    def remove(self, name: str) -> None:
        self.entries.pop(name, None)
        self.save()

    def files_of(self, name: str) -> list[str]:
        return self.entries.get(name, {}).get("files", [])

    def owners(self, exclude: str | None = None) -> dict[str, str]:
        """Map every owned path to the package that owns it."""
        out: dict[str, str] = {}
        for name, entry in self.entries.items():
            if name == exclude:
                continue
            for rel in entry.get("files", []):
                out.setdefault(rel, name)
        return out

    def as_packages(self) -> dict[str, Package]:
        return {name: Package.from_dict(e) for name, e in self.entries.items()}

    def dependents_of(self, name: str) -> list[str]:
        """Which installed packages still depend on this one."""
        from .models import Constraint

        out = []
        for other, entry in self.entries.items():
            if other == name:
                continue
            for dep in entry.get("depends", []):
                if Constraint.parse(dep).name == name:
                    out.append(other)
                    break
        return out
