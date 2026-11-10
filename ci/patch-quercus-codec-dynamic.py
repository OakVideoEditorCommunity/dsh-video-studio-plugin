#!/usr/bin/env python3
"""Link FFmpeg dynamically instead of statically in the Windows build.

`quercus-codec` requests `quercus-ffmpeg-next` with the `static` feature, which
makes `ffmpeg-sys-next` emit `cargo:rustc-link-lib=static=...` directives. The
pinned BtbN FFmpeg prefix ships DLL import libraries (`avcodec.lib`, ...) and
no static archives, so the feature must be removed; the crate then links
against the BtbN import libraries and the DLLs ride along next to the exe.

The edit is applied IN PLACE to the crate in the cargo registry (cargo does not
re-verify extracted sources). Run `cargo fetch` first.

Usage: patch-quercus-codec-dynamic.py
"""
import glob
import os
import re
import sys

CRATE = "quercus-codec-0.7.0"
FEATURE_BLOCK = re.compile(
    r'(\[dependencies\.quercus-ffmpeg-next\]\nversion = "0\.7\.0")\nfeatures = \["static"\]'
)


def main():
    candidates = sorted(
        glob.glob(os.path.expanduser("~/.cargo/registry/src/*/%s/Cargo.toml" % CRATE))
    )
    if not candidates:
        print(
            "error: %s not in cargo registry (run `cargo fetch` first)" % CRATE,
            file=sys.stderr,
        )
        return 1
    for path in candidates:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        new_text, count = FEATURE_BLOCK.subn(r"\1", text, count=1)
        if count == 0:
            if '[dependencies.quercus-ffmpeg-next]\nversion = "0.7.0"' in text:
                print("already patched: %s" % path)
                continue
            print(
                "error: quercus-ffmpeg-next dependency block not found in %s" % path,
                file=sys.stderr,
            )
            return 1
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(new_text)
        print("patched %s: ffmpeg-next static feature removed" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
