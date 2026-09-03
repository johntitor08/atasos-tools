"""Core data types: versions, constraints, packages."""

from __future__ import annotations

import functools
import re
from dataclasses import dataclass, field
from typing import Iterable

_OPS = ("==", ">=", "<=", "!=", ">", "<")
_SEG = re.compile(r"(\d+|[a-zA-Z]+)")


def _segments(version: str):
    """Split a version into comparable segments.

    Numeric segments carry their integer value; alphabetic segments are
    tagged lower so that a numeric segment always outranks a letter one.
    """
    segs = []
    for seg in _SEG.findall(version):
        if seg.isdigit():
            segs.append((1, int(seg), ""))
        else:
            segs.append((0, 0, seg))
    return segs


def version_compare(a: str, b: str) -> int:
    """Return -1, 0 or 1.

    Unequal lengths are decided by what the longer one has next: an extra
    numeric segment means a later release (1.0.1 > 1.0), an extra alphabetic
    segment means a prerelease (1.0 > 1.0rc1).
    """
    sa, sb = _segments(a), _segments(b)
    for i in range(max(len(sa), len(sb))):
        if i >= len(sa):
            return 1 if sb[i][0] == 0 else -1
        if i >= len(sb):
            return -1 if sa[i][0] == 0 else 1
        if sa[i] != sb[i]:
            return 1 if sa[i] > sb[i] else -1
    return 0


#: Sort key for anything that orders versions (max(), sort(), ...).
version_key = functools.cmp_to_key(version_compare)


@dataclass(frozen=True)
class Constraint:
    """A dependency requirement, e.g. ``zlib>=1.3``."""

    name: str
    op: str | None = None
    version: str | None = None

    @classmethod
    def parse(cls, text: str) -> "Constraint":
        text = text.strip()
        for op in _OPS:
            idx = text.find(op)
            if idx > 0:
                return cls(text[:idx].strip(), op, text[idx + len(op):].strip())
        return cls(text)

    def satisfied_by(self, version: str) -> bool:
        if self.op is None:
            return True
        c = version_compare(version, self.version)
        return {
            "==": c == 0,
            "!=": c != 0,
            ">=": c >= 0,
            "<=": c <= 0,
            ">": c > 0,
            "<": c < 0,
        }[self.op]

    def __str__(self) -> str:
        return self.name if self.op is None else f"{self.name}{self.op}{self.version}"


@dataclass
class Package:
    name: str
    version: str
    description: str = ""
    depends: list[str] = field(default_factory=list)
    conflicts: list[str] = field(default_factory=list)
    file_url: str = ""
    sha256: str = ""

    @property
    def id(self) -> str:
        return f"{self.name}-{self.version}"

    @property
    def filename(self) -> str:
        return self.file_url or f"{self.id}.apkg"

    def dep_constraints(self) -> list[Constraint]:
        return [Constraint.parse(d) for d in self.depends]

    def conflict_constraints(self) -> list[Constraint]:
        return [Constraint.parse(c) for c in self.conflicts]

    @classmethod
    def from_dict(cls, d: dict) -> "Package":
        return cls(
            name=d["name"],
            version=str(d["version"]),
            description=d.get("description", ""),
            depends=list(d.get("depends", [])),
            conflicts=list(d.get("conflicts", [])),
            file_url=d.get("file_url", ""),
            sha256=d.get("sha256", ""),
        )

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "version": self.version,
            "description": self.description,
            "depends": self.depends,
            "conflicts": self.conflicts,
            "file_url": self.file_url,
            "sha256": self.sha256,
        }


def highest(packages: Iterable[Package]) -> Package:
    return max(packages, key=lambda p: version_key(p.version))
