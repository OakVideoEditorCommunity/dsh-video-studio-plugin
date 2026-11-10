#!/usr/bin/env bash
# GitHub Actions: 构建 oak-mcp Linux x86_64，并把 bin/ + lib/ 放到 $OUT_DIR。
#
# 环境变量（由 workflow 提供，可覆盖）：
#   UPSTREAM_SRC   干净的 example-mcp 源码目录
#   WORK_ROOT      工作目录（默认 $RUNNER_TEMP/oak-build）
#   FFMPEG_PREFIX  FFmpeg 9 安装前缀（默认 $WORK_ROOT/ffmpeg9）
#   OUT_DIR        产物目录（默认 $WORK_ROOT/out/linux-x64）
#   REPO_ROOT      本插件仓库根目录（提供 ci/ 与 cross-build/）
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
WORK_ROOT="${WORK_ROOT:-${RUNNER_TEMP:-/tmp}/oak-build}"
UPSTREAM_SRC="${UPSTREAM_SRC:?UPSTREAM_SRC is required}"
FFMPEG_PREFIX="${FFMPEG_PREFIX:-$WORK_ROOT/ffmpeg9}"
OUT_DIR="${OUT_DIR:-$WORK_ROOT/out/linux-x64}"
BUILD_SRC="$WORK_ROOT/example-mcp-build"
TARGET_DIR="$WORK_ROOT/target-linux"

mkdir -p "$WORK_ROOT" "$OUT_DIR"

echo "==> FFmpeg 9 ($FFMPEG_PREFIX)"
if [ -f "$FFMPEG_PREFIX/.ok" ] && [ -f "$FFMPEG_PREFIX/lib/pkgconfig/libavcodec.pc" ]; then
	echo "cache hit"
else
	PREFIX="$FFMPEG_PREFIX" bash "$REPO_ROOT/ci/build-ffmpeg9-linux.sh" "$FFMPEG_PREFIX"
fi

echo "==> patched upstream copy"
rm -rf "$BUILD_SRC"
cp -a "$UPSTREAM_SRC" "$BUILD_SRC"
export CARGO_TARGET_DIR="$TARGET_DIR"
cargo fetch --manifest-path "$BUILD_SRC/Cargo.toml"
python3 "$REPO_ROOT/ci/patch-quercus-ffmpeg-link.py" "$BUILD_SRC" "$WORK_ROOT" "$REPO_ROOT"

echo "==> cargo build"
export FFMPEG_DIR="$FFMPEG_PREFIX"
export PKG_CONFIG_PATH="$FFMPEG_PREFIX/lib/pkgconfig"
export WGPU_BACKEND="${WGPU_BACKEND:-vulkan}"
cargo build --release --manifest-path "$BUILD_SRC/Cargo.toml"

BIN="$TARGET_DIR/release/oak-mcp"
[ -x "$BIN" ] || { echo "binary missing: $BIN" >&2; exit 1; }

echo "==> --check"
"$BIN" --check

echo "==> stage bin/ + running libraries"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/bin" "$OUT_DIR/lib"
cp "$BIN" "$OUT_DIR/bin/oak-mcp"
chmod +x "$OUT_DIR/bin/oak-mcp"
while IFS= read -r lib; do
	[ -n "$lib" ] || continue
	base=$(basename "$lib")
	case "$base" in
		libc.so*|libm.so*|libdl.so*|libpthread.so*|librt.so*|libgcc_s.so*|libstdc++.so*|libz.so*|libbz2.so*|liblzma.so*|libpcre2-8.so*|libresolv.so*|libutil.so*|ld-linux*) continue ;;
	esac
	cp -L "$lib" "$OUT_DIR/lib/" 2>/dev/null || true
done < <(ldd "$BIN" | awk '{print $3}' | grep '^/' || true)
ldd "$BIN" | grep "not found" && { echo "ERROR: missing runtime libraries" >&2; exit 1; } || true
echo "==> staged $(ls -1 "$OUT_DIR/lib" | wc -l | tr -d ' ') libraries -> $OUT_DIR"
