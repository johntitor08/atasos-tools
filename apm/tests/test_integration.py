"""Resolver and end-to-end install/remove tests."""

import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pytest

from apm.mkpkg import build
from apm.models import Constraint, Package, version_compare
from apm.repo import InstalledDB, RepoIndex
from apm.resolver import BacktrackingResolver, Resolver, ResolutionError
from apm.transaction import Transaction, TransactionError


# --------------------------------------------------------------- models

def test_version_compare():
    assert version_compare("1.3.1", "1.3") > 0
    assert version_compare("1.10", "1.9") > 0        # numeric, not lexical
    assert version_compare("2.0", "2.0") == 0
    assert version_compare("1.0", "1.0rc1") > 0      # release beats prerelease


def test_constraint_parse_with_dashed_name():
    c = Constraint.parse("shared-lib>=1.0")
    assert (c.name, c.op, c.version) == ("shared-lib", ">=", "1.0")
    assert c.satisfied_by("1.2")
    assert not c.satisfied_by("0.9")
    assert Constraint.parse("zlib").satisfied_by("anything")


# ------------------------------------------------------------- resolver

def simple_index():
    return {
        "zlib": [Package("zlib", "1.3.1")],
        "openssl": [Package("openssl", "3.2.0", depends=["zlib>=1.3"])],
        "curl": [Package("curl", "8.6.0", depends=["openssl>=3.0", "zlib"])],
    }


def test_resolver_orders_dependencies_first():
    order = Resolver(simple_index()).resolve(["curl"]).names()
    assert order.index("zlib") < order.index("openssl") < order.index("curl")


def test_resolver_skips_satisfied_installed_packages():
    installed = {"zlib": Package("zlib", "1.3.1")}
    order = Resolver(simple_index(), installed).resolve(["curl"]).names()
    assert "zlib" not in order


def test_unsatisfiable_dependency_raises():
    index = {"app": [Package("app", "1.0", depends=["ghost>=1.0"])]}
    with pytest.raises(ResolutionError, match="unsatisfiable"):
        Resolver(index).resolve(["app"])


def test_circular_dependency_detected():
    index = {
        "a": [Package("a", "1.0", depends=["b"])],
        "b": [Package("b", "1.0", depends=["a"])],
    }
    with pytest.raises(ResolutionError, match="circular"):
        Resolver(index).resolve(["a"])


def test_explicit_conflict_detected():
    index = {
        "a": [Package("a", "1.0", depends=["b"], conflicts=["b"])],
        "b": [Package("b", "1.0")],
    }
    with pytest.raises(ResolutionError, match="conflicts"):
        Resolver(index).resolve(["a"])


def strict_backtrack_index():
    """Only ONE valid combination exists, and it is not the newest-of-each one.

    libA-2.0 needs shared-lib==2.0, libB-2.0 needs shared-lib==3.0, so no
    pairing involving a 2.0 works. The single solution is all-1.0.
    """
    return {
        "shared-lib": [Package("shared-lib", v) for v in ("1.0", "2.0", "3.0")],
        "libA": [
            Package("libA", "1.0", depends=["shared-lib==1.0"]),
            Package("libA", "2.0", depends=["shared-lib==2.0"]),
        ],
        "libB": [
            Package("libB", "1.0", depends=["shared-lib==1.0"]),
            Package("libB", "2.0", depends=["shared-lib==3.0"]),
        ],
        "app": [Package("app", "1.0", depends=["libA>=1.0", "libB>=1.0"])],
    }


def test_greedy_fails_on_strict_scenario():
    with pytest.raises(ResolutionError):
        Resolver(strict_backtrack_index()).resolve(["app"])


def test_backtracking_resolves_where_greedy_fails():
    res = BacktrackingResolver(strict_backtrack_index()).resolve(["app"])
    chosen = {p.name: p.version for p in res.install_order}
    assert chosen["libA"] == "1.0"
    assert chosen["libB"] == "1.0"
    assert chosen["shared-lib"] == "1.0"


def test_backtracking_matches_greedy_on_simple_trees():
    order = BacktrackingResolver(simple_index()).resolve(["curl"]).names()
    assert order.index("zlib") < order.index("openssl") < order.index("curl")


# ---------------------------------------------------------- end-to-end

def make_staged_lib(tmp):
    """A staging tree with a real SONAME symlink chain."""
    destdir = os.path.join(tmp, "stage")
    libdir = os.path.join(destdir, "usr", "lib")
    bindir = os.path.join(destdir, "usr", "bin")
    os.makedirs(libdir)
    os.makedirs(bindir)
    with open(os.path.join(libdir, "libz.so.1.3.1"), "wb") as fh:
        fh.write(b"ELF-ish payload")
    os.symlink("libz.so.1.3.1", os.path.join(libdir, "libz.so.1"))
    os.symlink("libz.so.1", os.path.join(libdir, "libz.so"))
    with open(os.path.join(bindir, "zprog"), "w") as fh:
        fh.write("#!/bin/sh\necho hi\n")
    return destdir


def test_install_preserves_symlinks_not_copies():
    """Regression guard: copytree/copy2 dereference symlinks by default, which
    would silently turn libz.so into a second full copy of the library."""
    with tempfile.TemporaryDirectory() as tmp:
        destdir = make_staged_lib(tmp)
        apkg, digest = build(destdir, "zlib", "1.3.1", os.path.join(tmp, "pkgs"))

        pkg = Package("zlib", "1.3.1", file_url=os.path.basename(apkg), sha256=digest)
        db = InstalledDB(os.path.join(tmp, "installed.json"))
        root = os.path.join(tmp, "root")
        files = Transaction(db, root).install(pkg, apkg)

        so = os.path.join(root, "usr/lib/libz.so")
        so1 = os.path.join(root, "usr/lib/libz.so.1")
        assert os.path.islink(so), "libz.so must stay a symlink"
        assert os.readlink(so) == "libz.so.1"
        assert os.readlink(so1) == "libz.so.1.3.1"
        assert "/usr/bin/zprog" in files


def test_sha256_mismatch_aborts_install():
    with tempfile.TemporaryDirectory() as tmp:
        destdir = make_staged_lib(tmp)
        apkg, _ = build(destdir, "zlib", "1.3.1", os.path.join(tmp, "pkgs"))
        pkg = Package("zlib", "1.3.1", sha256="0" * 64)
        db = InstalledDB(os.path.join(tmp, "installed.json"))
        with pytest.raises(TransactionError, match="sha256"):
            Transaction(db, os.path.join(tmp, "root")).install(pkg, apkg)


def test_remove_deletes_only_owned_files():
    with tempfile.TemporaryDirectory() as tmp:
        destdir = make_staged_lib(tmp)
        apkg, digest = build(destdir, "zlib", "1.3.1", os.path.join(tmp, "pkgs"))
        pkg = Package("zlib", "1.3.1", sha256=digest)

        db = InstalledDB(os.path.join(tmp, "installed.json"))
        root = os.path.join(tmp, "root")
        tx = Transaction(db, root)
        tx.install(pkg, apkg)

        os.makedirs(os.path.join(root, "etc"), exist_ok=True)
        keep = os.path.join(root, "etc", "not-ours.conf")
        with open(keep, "w") as fh:
            fh.write("untouched")

        tx.remove("zlib")
        assert not os.path.lexists(os.path.join(root, "usr/lib/libz.so"))
        assert not os.path.exists(os.path.join(root, "usr/bin/zprog"))
        assert os.path.exists(keep), "files not owned by the package must survive"
        assert "zlib" not in db.entries


def test_remove_blocked_by_dependents():
    with tempfile.TemporaryDirectory() as tmp:
        db = InstalledDB(os.path.join(tmp, "installed.json"))
        db.add(Package("zlib", "1.3.1"), [])
        db.add(Package("curl", "8.6.0", depends=["zlib>=1.3"]), [])
        tx = Transaction(db, os.path.join(tmp, "root"))
        with pytest.raises(TransactionError, match="required by"):
            tx.remove("zlib")
        tx.remove("zlib", force=True)
        assert "zlib" not in db.entries


def test_repo_index_roundtrip_and_search():
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "index.json")
        with open(src, "w") as fh:
            json.dump({"packages": [
                {"name": "zlib", "version": "1.3.1", "description": "compression library"},
                {"name": "curl", "version": "8.6.0", "depends": ["zlib>=1.3"]},
            ]}, fh)
        cache = os.path.join(tmp, "cache.json")
        assert RepoIndex().sync(src, cache) == 2
        repo = RepoIndex.load(cache)
        assert [p.name for p in repo.search("compression")] == ["zlib"]
        assert repo.find("curl").depends == ["zlib>=1.3"]
