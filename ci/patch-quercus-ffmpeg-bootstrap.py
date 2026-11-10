#!/usr/bin/env python3
"""Enable the vcpkg `nvcodec` feature in the pinned FFmpeg bootstrap (Windows).

`quercus-ffmpeg-bootstrap` hardcodes the vcpkg feature list when it builds
FFmpeg for MSVC. That list omits `nvcodec`, so the Windows oak-mcp cannot use
NVENC/NVDEC/CUDA. Adding the feature makes vcpkg build `ffnvcodec` and pass
`--enable-cuda --enable-nvenc --enable-nvdec --enable-cuvid --enable-ffnvcodec`
to FFmpeg (no CUDA SDK is needed: FFmpeg loads the driver DLLs at runtime).

The edit is applied IN PLACE to the crate in the cargo registry (cargo does not
re-verify extracted sources). Run `cargo fetch` first.

Usage: patch-quercus-ffmpeg-bootstrap.py [--windows]
"""
import glob
import os
import sys

CRATE = "quercus-ffmpeg-bootstrap-0.7.0"
OLD = (
    "ffmpeg[ass,dav1d,freetype,fribidi,gpl,mp3lame,openjpeg,opus,snappy,"
    "speex,theora,vorbis,vpx,webp,x264,x265]:x64-windows-static-md"
)
NEW = (
    "ffmpeg[ass,dav1d,freetype,fribidi,gpl,mp3lame,openjpeg,opus,snappy,"
    "speex,theora,vorbis,vpx,webp,x264,x265,nvcodec]:x64-windows-static-md"
)


def main():
    # The flag is documentation only; the patch is specific to the vcpkg
    # (Windows) code path, but applying it on any host is harmless.
    _ = "--windows" in sys.argv
    pattern = os.path.expanduser(
        "~/.cargo/registry/src/*/%s/src/lib.rs" % CRATE
    )
    candidates = sorted(glob.glob(pattern))
    if not candidates:
        print(
            "error: %s not in cargo registry (run `cargo fetch` first)" % CRATE,
            file=sys.stderr,
        )
        return 1
    patched = 0
    for path in candidates:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        if NEW in text:
            print("already patched: %s" % path)
            continue
        if OLD not in text:
            print(
                "error: expected vcpkg feature list not found in %s" % path,
                file=sys.stderr,
            )
            return 1
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text.replace(OLD, NEW, 1))
        print("patched %s: vcpkg ffmpeg += nvcodec" % path)
        patched += 1
    if patched == 0 and not candidates:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
