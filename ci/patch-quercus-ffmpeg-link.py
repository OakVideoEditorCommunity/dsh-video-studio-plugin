#!/usr/bin/env python3
"""Patch a copy of quercus-ffmpeg-link so Linux system libraries link dynamically.

Upstream force-links non-PIC `/usr/lib/.../*.a` archives (bz2, lzma, z, asound,
stdc++, ...) into the rlib. That breaks linking the shared `libquercus_engine.so`
cdylib (`relocation R_X86_64_PC32 ... recompile with -fPIC`). The patch is applied
to a copy of the crate; example-mcp then picks it up through `[patch.crates-io]`.

Usage: patch-quercus-ffmpeg-link.py <upstream-dir> <work-dir> <repo-root>
Writes <work-dir>/crates/quercus-ffmpeg-link-patched and appends the
[patch.crates-io] section to <upstream-dir>/Cargo.toml.
"""
import glob
import os
import shutil
import subprocess
import sys

CRATE = "quercus-ffmpeg-link-0.7.0"


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    upstream, work, repo = (os.path.abspath(p) for p in sys.argv[1:4])
    candidates = sorted(glob.glob(os.path.expanduser(f"~/.cargo/registry/src/*/{CRATE}")))
    if not candidates:
        print(f"error: {CRATE} not in cargo registry (run cargo fetch first)", file=sys.stderr)
        return 1
    patched = os.path.join(work, "crates", "quercus-ffmpeg-link-patched")
    shutil.rmtree(patched, ignore_errors=True)
    os.makedirs(os.path.dirname(patched), exist_ok=True)
    shutil.copytree(candidates[0], patched)

    patch_file = os.path.join(repo, "ci", "patches", "quercus-ffmpeg-link-linux-dynamic.patch")
    result = subprocess.run(["patch", "-p1", "-i", patch_file], cwd=patched)
    if result.returncode != 0:
        print("error: applying quercus-ffmpeg-link patch failed", file=sys.stderr)
        return result.returncode

    cargo_toml = os.path.join(upstream, "Cargo.toml")
    with open(cargo_toml, encoding="utf-8") as fh:
        content = fh.read()
    if "[patch.crates-io]" not in content:
        with open(cargo_toml, "a", encoding="utf-8") as fh:
            fh.write(f"\n[patch.crates-io]\nquercus-ffmpeg-link = {{ path = {patched!r} }}\n")
    print(f"patched quercus-ffmpeg-link -> {patched}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
