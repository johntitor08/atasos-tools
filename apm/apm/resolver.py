"""Dependency resolution: a greedy resolver and a backtracking one."""

from __future__ import annotations

from dataclasses import dataclass, field

from .models import Constraint, Package, version_key


class ResolutionError(Exception):
    pass


@dataclass
class Resolution:
    """The outcome of a resolve: packages in dependency-first install order."""

    install_order: list[Package] = field(default_factory=list)

    def names(self) -> list[str]:
        return [p.name for p in self.install_order]


def _topo_order(chosen: dict[str, Package]) -> list[Package]:
    """Sort chosen packages so dependencies come before dependents."""
    order: list[Package] = []
    state: dict[str, int] = {}  # 0 = visiting, 1 = done

    def visit(name: str, trail: list[str]) -> None:
        st = state.get(name)
        if st == 1:
            return
        if st == 0:
            cycle = " -> ".join(trail + [name])
            raise ResolutionError(f"circular dependency: {cycle}")
        state[name] = 0
        pkg = chosen[name]
        for c in pkg.dep_constraints():
            if c.name in chosen:
                visit(c.name, trail + [name])
        state[name] = 1
        order.append(pkg)

    for name in list(chosen):
        visit(name, [])
    return order


def _conflicts(chosen: dict[str, Package]) -> str | None:
    """Return a message if any chosen package conflicts with another."""
    for pkg in chosen.values():
        for c in pkg.conflict_constraints():
            other = chosen.get(c.name)
            if other and other.name != pkg.name and c.satisfied_by(other.version):
                return f"{pkg.id} conflicts with {other.id}"
    return None


class Resolver:
    """Greedy resolver: always take the highest compatible version, never
    reconsider. Fast, and enough for most trees, but it gives up on the first
    dead end even when another version combination would have worked."""

    def __init__(self, index: dict[str, list[Package]], installed: dict[str, Package] | None = None):
        self.index = index
        self.installed = installed or {}

    def resolve(self, targets: list[str]) -> Resolution:
        chosen: dict[str, Package] = {}
        visiting: list[str] = []

        def visit(c: Constraint) -> None:
            inst = self.installed.get(c.name)
            if inst is not None and c.satisfied_by(inst.version):
                return
            already = chosen.get(c.name)
            if already is not None:
                if not c.satisfied_by(already.version):
                    raise ResolutionError(
                        f"version conflict for {c.name}: {already.version} chosen, {c} required"
                    )
                return
            if c.name in visiting:
                raise ResolutionError(
                    "circular dependency: " + " -> ".join(visiting + [c.name])
                )
            candidates = [p for p in self.index.get(c.name, []) if c.satisfied_by(p.version)]
            if not candidates:
                raise ResolutionError(f"unsatisfiable dependency: {c}")
            pkg = max(candidates, key=lambda p: version_key(p.version))
            chosen[c.name] = pkg
            visiting.append(c.name)
            for dep in pkg.dep_constraints():
                visit(dep)
            visiting.pop()

        for t in targets:
            visit(Constraint.parse(t))

        msg = _conflicts(chosen)
        if msg:
            raise ResolutionError(msg)
        return Resolution(_topo_order(chosen))


class BacktrackingResolver:
    """CSP-style resolver.

    Candidate versions are tried highest first, but when a choice leads to a
    dead end downstream the search returns to the previous decision point and
    tries the next candidate. This solves trees where exactly one valid
    combination exists and it is not the always-take-the-newest one.
    """

    MAX_ATTEMPTS = 20000

    def __init__(self, index: dict[str, list[Package]], installed: dict[str, Package] | None = None):
        self.index = index
        self.installed = installed or {}
        self.attempts = 0
        self._last_error: str = ""

    def resolve(self, targets: list[str]) -> Resolution:
        self.attempts = 0
        self._last_error = ""
        pending = [Constraint.parse(t) for t in targets]
        solution = self._search(pending, {})
        if solution is None:
            detail = f": {self._last_error}" if self._last_error else ""
            raise ResolutionError(f"no valid dependency combination found{detail}")
        return Resolution(_topo_order(solution))

    def _search(self, pending: list[Constraint], chosen: dict[str, Package]) -> dict[str, Package] | None:
        if not pending:
            msg = _conflicts(chosen)
            if msg:
                self._last_error = msg
                return None
            return chosen

        c, rest = pending[0], pending[1:]

        inst = self.installed.get(c.name)
        if inst is not None and c.satisfied_by(inst.version):
            return self._search(rest, chosen)

        already = chosen.get(c.name)
        if already is not None:
            if c.satisfied_by(already.version):
                return self._search(rest, chosen)
            self._last_error = f"version conflict for {c.name}: {already.version} vs {c}"
            return None

        candidates = [p for p in self.index.get(c.name, []) if c.satisfied_by(p.version)]
        if not candidates:
            self._last_error = f"unsatisfiable dependency: {c}"
            return None
        candidates.sort(key=lambda p: version_key(p.version), reverse=True)

        for pkg in candidates:
            self.attempts += 1
            if self.attempts > self.MAX_ATTEMPTS:
                raise ResolutionError(
                    f"resolution gave up after {self.MAX_ATTEMPTS} attempts (dependency graph too large)"
                )
            trial = dict(chosen)
            trial[c.name] = pkg
            if _conflicts(trial):
                continue
            result = self._search(rest + pkg.dep_constraints(), trial)
            if result is not None:
                return result
        return None
