#!/usr/bin/env python3
"""Accept a shared FFmpeg prefix in quercus-ffmpeg-bootstrap's validator.

`valid_prefix()` requires `lib/libavcodec.a` on non-Windows targets. The pinned
BtbN Linux build ships only shared libraries, so allow `libavcodec.so` as well;
`FFMPEG_DIR` then short-circuits the source build.

The edit is applied IN PLACE to the crate in the cargo registry (cargo does not
re-verify extracted sources). Run `cargo fetch` first.
"""
import glob
import os
import sys

CRATE = "quercus-ffmpeg-bootstrap-0.7.0"
OLD = "&& library.is_file()"
NEW = '&& (library.is_file() || dir.join("lib").join("libavcodec.so").is_file())'


def main():
    candidates = sorted(
        glob.glob(os.path.expanduser("~/.cargo/registry/src/*/%s/src/lib.rs" % CRATE))
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
        if NEW in text:
            print("already patched: %s" % path)
            continue
        if OLD not in text:
            print("error: valid_prefix() not found in %s" % path, file=sys.stderr)
            return 1
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text.replace(OLD, NEW, 1))
        print("patched %s: shared FFmpeg prefix accepted" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
