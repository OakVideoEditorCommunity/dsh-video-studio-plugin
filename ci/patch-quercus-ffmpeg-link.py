#!/usr/bin/env python3
"""Patch a copy of quercus-ffmpeg-link so Linux system libraries link dynamically.

Upstream force-links non-PIC `/usr/lib/.../*.a` archives (bz2, lzma, z, asound,
stdc++, ...) into the rlib. That breaks linking the shared `libquercus_engine.so`
cdylib (`relocation R_X86_64_PC32 ... recompile with -fPIC`).

The patch is applied IN PLACE to the crate in the cargo registry: the bootstrap
crate locates its vendored FFmpeg tooling by looking at CARGO_MANIFEST_DIR of the
running build script, so an out-of-tree `[patch.crates-io]` copy would break the
`quercus-ffmpeg-bootstrap` lookup (it expects the registry sibling layout).

Usage: patch-quercus-ffmpeg-link.py <upstream-dir> <work-dir> <repo-root>
<work-dir> is unused; <upstream-dir> is unused.
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
    repo = os.path.abspath(sys.argv[3])
    candidates = sorted(glob.glob(os.path.expanduser(f"~/.cargo/registry/src/*/{CRATE}")))
    if not candidates:
        print(f"error: {CRATE} not in cargo registry (run cargo fetch first)", file=sys.stderr)
        return 1
    print(f"patching {candidates[0]} in place")
    build_rs = os.path.join(candidates[0], "build.rs")
    with open(build_rs, encoding="utf-8") as fh:
        if "static_system_lib_dir(lib)" not in fh.read():
            print("already patched")
            return 0
    patch_file = os.path.join(repo, "ci", "patches", "quercus-ffmpeg-link-linux-dynamic.patch")
    result = subprocess.run(["patch", "-p1", "-i", patch_file], cwd=candidates[0])
    if result.returncode != 0:
        print("error: applying quercus-ffmpeg-link patch failed", file=sys.stderr)
        return result.returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())
