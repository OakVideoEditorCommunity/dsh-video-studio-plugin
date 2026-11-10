#!/usr/bin/env python3
"""Make the quercus-engine crate build only rlib+staticlib (drop the cdylib).

On Linux the bootstrap-built FFmpeg/OCIO static closure contains non-PIC system
archives (e.g. fontconfig), which cannot be linked into a shared cdylib
(`R_X86_64_PC32 ... recompile with -fPIC`). oak-mcp links the engine statically
anyway, so the cdylib artifact is unnecessary; removing it fixes the link.

The edit is applied IN PLACE to the crate in the cargo registry (cargo does not
re-verify extracted sources). Usage: patch-quercus-engine-static.py
"""
import glob
import os
import re
import sys

CRATE = "quercus-engine-0.7.0"


def main():
    candidates = sorted(glob.glob(os.path.expanduser(f"~/.cargo/registry/src/*/{CRATE}/Cargo.toml")))
    if not candidates:
        print(f"error: {CRATE} not in cargo registry (run cargo fetch first)", file=sys.stderr)
        return 1
    path = candidates[0]
    with open(path, encoding="utf-8") as fh:
        content = fh.read()
    # Replace the crate-type block that contains "cdylib".
    pattern = re.compile(r'crate-type\s*=\s*\[[^\]]*cdylib[^\]]*\]', re.S)
    if not pattern.search(content):
        if 'crate-type = ["rlib", "staticlib"]' in content:
            print("already patched")
            return 0
        print("error: crate-type with cdylib not found", file=sys.stderr)
        return 1
    replaced = pattern.sub('crate-type = ["rlib", "staticlib"]', content, count=1)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(replaced)
    print(f"patched {path}: cdylib removed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
