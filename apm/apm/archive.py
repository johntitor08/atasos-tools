"""zstd-compressed tar handling, with a fallback to the zstd binary."""

from __future__ import annotations

import io
import shutil
import subprocess
import tarfile


def _have_module() -> bool:
    try:
        import zstandard  # noqa: F401

        return True
    except ImportError:
        return False


def compress(data: bytes, level: int = 19) -> bytes:
    if _have_module():
        import zstandard

        return zstandard.ZstdCompressor(level=level).compress(data)
    if shutil.which("zstd") is None:
        raise RuntimeError("neither the zstandard module nor the zstd binary is available")
    return subprocess.run(
        ["zstd", f"-{level}", "-c", "-q"], input=data, stdout=subprocess.PIPE, check=True
    ).stdout


def decompress(data: bytes) -> bytes:
    if _have_module():
        import zstandard

        return zstandard.ZstdDecompressor().decompress(data, max_output_size=1 << 31)
    if shutil.which("zstd") is None:
        raise RuntimeError("neither the zstandard module nor the zstd binary is available")
    return subprocess.run(
        ["zstd", "-d", "-c", "-q"], input=data, stdout=subprocess.PIPE, check=True
    ).stdout


def open_tar_zst(path: str) -> tarfile.TarFile:
    with open(path, "rb") as fh:
        raw = decompress(fh.read())
    return tarfile.open(fileobj=io.BytesIO(raw), mode="r:")


def write_tar_zst(path: str, add: callable) -> None:
    """``add`` receives a TarFile and adds members to it."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:") as tar:
        add(tar)
    with open(path, "wb") as fh:
        fh.write(compress(buf.getvalue()))
