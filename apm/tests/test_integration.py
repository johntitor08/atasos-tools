"""Resolver and end-to-end install/remove tests."""

import json
import os
import sys
import tarfile
import tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pytest

from apm.mkpkg import build
from apm.models import Constraint, Package, version_compare
from apm.repo import InstalledDB, RepoIndex
from apm.resolver import BacktrackingResolver, Resolver, ResolutionError
from apm.transaction import Transaction, TransactionError


def _symlinks_available() -> bool:
    """Windows refuses os.symlink without Developer Mode or admin rights
    (WinError 1314). The symlink tests are meaningless there, so skip them."""
    with tempfile.TemporaryDirectory() as probe:
        target = os.path.join(probe, "target")
        open(target, "w").close()
        try:
            os.symlink(target, os.path.join(probe, "link"))
        except (OSError, NotImplementedError, AttributeError):
            return False
    return True


requires_symlinks = pytest.mark.skipif(
    not _symlinks_available(),
    reason="creating symlinks is not permitted on this platform",
)


def _zstd_available() -> bool:
    import shutil
    try:
        import zstandard  # noqa: F401
        return True
    except ImportError:
        return shutil.which("zstd") is not None


requires_zstd = pytest.mark.skipif(
    not _zstd_available(),
    reason="needs the zstandard module or the zstd binary",
)


# --------------------------------------------------------------- models

def test_version_compare():
    assert version_compare("1.3.1", "1.3") > 0
    assert version_compare("1.10", "1.9") > 0        # numeric, not lexical
    assert version_compare("2.0", "2.0") == 0
    assert version_compare("1.0", "1.0rc1") > 0      # release beats prerelease
    assert version_compare("1.3", "1.3.0") == 0      # trailing zeros ignored
    assert version_compare("1.0", "1.0.0rc1") > 0


def test_constraint_parse_with_dashed_name():
    c = Constraint.parse("shared-lib>=1.0")
    assert (c.name, c.op, c.version) == ("shared-lib", ">=", "1.0")
    assert c.satisfied_by("1.2")
    assert not c.satisfied_by("0.9")
    assert Constraint.parse("zlib").satisfied_by("anything")
    assert Constraint.parse("zlib==1.3").satisfied_by("1.3.0")
    single = Constraint.parse("zlib=1.3")
    assert (single.name, single.op) == ("zlib", "==")


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


@requires_zstd
@requires_symlinks
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


@requires_zstd
@requires_symlinks
def test_sha256_mismatch_aborts_install():
    with tempfile.TemporaryDirectory() as tmp:
        destdir = make_staged_lib(tmp)
        apkg, _ = build(destdir, "zlib", "1.3.1", os.path.join(tmp, "pkgs"))
        pkg = Package("zlib", "1.3.1", sha256="0" * 64)
        db = InstalledDB(os.path.join(tmp, "installed.json"))
        with pytest.raises(TransactionError, match="sha256"):
            Transaction(db, os.path.join(tmp, "root")).install(pkg, apkg)


@requires_zstd
@requires_symlinks
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


# ------------------------------------------------- ownership / upgrade / rollback

def _pkg(tmp, name, version, files, mode=None):
    """Build an .apkg whose files are {relpath: content}; returns (Package, path)."""
    stage = os.path.join(tmp, f"stage-{name}-{version}")
    for rel, content in files.items():
        path = os.path.join(stage, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as fh:
            fh.write(content)
    if mode:
        for rel, m in mode.items():
            os.chmod(os.path.join(stage, rel), m)
    apkg, digest = build(stage, name, version, os.path.join(tmp, "pkgs"))
    return Package(name, version, sha256=digest), apkg


def _setup(tmp, **kw):
    db = InstalledDB(os.path.join(tmp, "installed.json"))
    root = os.path.join(tmp, "root")
    return db, root, Transaction(db, root, **kw)


@requires_zstd
def test_file_owned_by_other_package_is_a_conflict():
    with tempfile.TemporaryDirectory() as tmp:
        db, root, tx = _setup(tmp)
        tx.install(*_pkg(tmp, "a", "1", {"usr/bin/tool": "A"}))
        with pytest.raises(TransactionError, match="owned by a"):
            tx.install(*_pkg(tmp, "b", "1", {"usr/bin/tool": "B"}))
        assert open(os.path.join(root, "usr/bin/tool")).read() == "A"
        assert "b" not in db.entries


@requires_zstd
def test_force_shared_file_survives_removal_of_first_owner():
    with tempfile.TemporaryDirectory() as tmp:
        db, root, tx = _setup(tmp)
        tx.install(*_pkg(tmp, "a", "1", {"usr/bin/tool": "A"}))
        Transaction(db, root, force=True).install(*_pkg(tmp, "b", "1", {"usr/bin/tool": "B"}))
        tx.remove("a")
        assert open(os.path.join(root, "usr/bin/tool")).read() == "B"


@requires_zstd
def test_unowned_file_on_disk_needs_overwrite():
    with tempfile.TemporaryDirectory() as tmp:
        db, root, tx = _setup(tmp)
        os.makedirs(os.path.join(root, "etc"))
        with open(os.path.join(root, "etc/app.conf"), "w") as fh:
            fh.write("by hand")
        item = _pkg(tmp, "app", "1", {"etc/app.conf": "packaged"})
        with pytest.raises(TransactionError, match="not owned by any package"):
            tx.install(*item)
        Transaction(db, root, overwrite=True).install(*item)
        assert open(os.path.join(root, "etc/app.conf")).read() == "packaged"
        assert not [f for f in os.listdir(os.path.join(root, "etc")) if ".apm-bak-" in f]


@requires_zstd
def test_upgrade_removes_files_the_new_version_dropped():
    with tempfile.TemporaryDirectory() as tmp:
        db, root, tx = _setup(tmp)
        tx.install(*_pkg(tmp, "c", "1", {"usr/bin/c": "1", "usr/share/c/old": "x"}))
        tx.install(*_pkg(tmp, "c", "2", {"usr/bin/c": "2"}))
        assert open(os.path.join(root, "usr/bin/c")).read() == "2"
        assert not os.path.exists(os.path.join(root, "usr/share/c/old"))
        assert not os.path.exists(os.path.join(root, "usr/share/c")), "emptied dir pruned"
        assert db.entries["c"]["version"] == "2"
        tx.remove("c")
        assert not os.path.exists(os.path.join(root, "usr/bin/c"))


@requires_zstd
def test_failed_batch_rolls_back_everything():
    with tempfile.TemporaryDirectory() as tmp:
        db, root, tx = _setup(tmp)
        tx.install(*_pkg(tmp, "c", "1", {"usr/bin/c": "1", "usr/share/c/old": "x"}))
        good = _pkg(tmp, "c", "2", {"usr/bin/c": "2"})
        dep = _pkg(tmp, "d", "1", {"usr/bin/d": "d"})
        # failure while staging (missing archive): nothing may be applied
        with pytest.raises(TransactionError):
            tx.install_many([good, (dep[0], os.path.join(tmp, "missing.apkg"))])
        assert open(os.path.join(root, "usr/bin/c")).read() == "1"
        assert db.entries["c"]["version"] == "1"

        # failure during apply: make the second package's target unwritable
        import apm.transaction as T
        real = T.shutil.copy2
        def flaky(src, dst, **kw):
            if dst.endswith("usr/bin/d"):
                raise OSError("disk full")
            return real(src, dst, **kw)

        T.shutil.copy2 = flaky
        try:
            with pytest.raises(TransactionError, match="rolled back"):
                tx.install_many([good, dep])
        finally:
            T.shutil.copy2 = real
        assert open(os.path.join(root, "usr/bin/c")).read() == "1"
        assert os.path.exists(os.path.join(root, "usr/share/c/old"))
        assert not os.path.exists(os.path.join(root, "usr/bin/d"))
        assert db.entries["c"]["version"] == "1" and "d" not in db.entries
        leftovers = [f for d, _, fs in os.walk(root) for f in fs if ".apm-bak-" in f]
        assert not leftovers


@requires_zstd
def test_directory_modes_are_preserved():
    with tempfile.TemporaryDirectory() as tmp:
        db, root, tx = _setup(tmp)
        tx.install(*_pkg(tmp, "t", "1", {"var/tmp/x/.keep": ""}, mode={"var/tmp/x": 0o1777}))
        assert (os.stat(os.path.join(root, "var/tmp/x")).st_mode & 0o7777) == 0o1777


@requires_zstd
def test_missing_checksum_refused_when_required():
    with tempfile.TemporaryDirectory() as tmp:
        db, root, _ = _setup(tmp)
        pkg, path = _pkg(tmp, "u", "1", {"usr/bin/u": ""})
        pkg.sha256 = ""
        with pytest.raises(TransactionError, match="no sha256"):
            Transaction(db, root, require_checksum=True).install(pkg, path)


@requires_zstd
def test_setuid_bit_survives_install():
    with tempfile.TemporaryDirectory() as tmp:
        db, root, tx = _setup(tmp)
        tx.install(*_pkg(tmp, "s", "1", {"usr/bin/sudo": ""}, mode={"usr/bin/sudo": 0o4755}))
        assert (os.stat(os.path.join(root, "usr/bin/sudo")).st_mode & 0o7777) == 0o4755


@requires_zstd
@requires_symlinks
def test_archive_writing_through_symlink_is_refused():
    """data/x -> /<outside> followed by data/x/evil must not escape staging."""
    import io
    from apm.archive import write_tar_zst
    with tempfile.TemporaryDirectory() as tmp:
        outside = os.path.join(tmp, "outside")
        os.makedirs(outside)
        path = os.path.join(tmp, "evil.apkg")

        def add(tar):
            link = tarfile.TarInfo("data/x")
            link.type, link.linkname = tarfile.SYMTYPE, outside
            tar.addfile(link)
            f = tarfile.TarInfo("data/x/evil")
            f.size = 4
            tar.addfile(f, io.BytesIO(b"pwnd"))

        write_tar_zst(path, add)
        db, root, tx = _setup(tmp)
        with pytest.raises(TransactionError, match="unsafe archive"):
            tx.install(Package("evil", "1"), path)
        assert not os.listdir(outside)
