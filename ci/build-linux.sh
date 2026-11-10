#!/usr/bin/env bash
# GitHub Actions: 构建 oak-mcp Linux x86_64，并把 bin/ + lib/ 放到 $OUT_DIR。
#
# FFmpeg 9 与 OpenColorIO 都由 quercus 的 bootstrap 机制从源码**静态**构建：
#   - ffmpeg: quercus-ffmpeg-bootstrap → vendored tooling/ffmpeg/build-ffmpeg.sh
#   - OCIO:   ocio-sys `bundled` 特性 → vendored OpenColorIO CMake
# 不使用系统 FFmpeg / conda / Homebrew OCIO。首次构建较慢，workflow 会缓存前缀。
#
# 环境变量：
#   UPSTREAM_SRC          干净的 example-mcp 源码目录
#   WORK_ROOT             工作目录（默认 $RUNNER_TEMP/oak-build）
#   QUERCUS_FFMPEG_CACHE  bootstrap 缓存目录（默认 $WORK_ROOT/quercus-ffmpeg）
#   OUT_DIR               产物目录（默认 $WORK_ROOT/out/linux-x64）
#   REPO_ROOT             本插件仓库根目录
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
WORK_ROOT="${WORK_ROOT:-${RUNNER_TEMP:-/tmp}/oak-build}"
UPSTREAM_SRC="${UPSTREAM_SRC:?UPSTREAM_SRC is required}"
OUT_DIR="${OUT_DIR:-$WORK_ROOT/out/linux-x64}"
BUILD_SRC="$WORK_ROOT/example-mcp-build"
TARGET_DIR="$WORK_ROOT/target-linux"
export QUERCUS_FFMPEG_CACHE="${QUERCUS_FFMPEG_CACHE:-$WORK_ROOT/quercus-ffmpeg}"

mkdir -p "$WORK_ROOT" "$OUT_DIR" "$QUERCUS_FFMPEG_CACHE"

echo "==> patched upstream copy"
rm -rf "$BUILD_SRC"
cp -a "$UPSTREAM_SRC" "$BUILD_SRC"
export CARGO_TARGET_DIR="$TARGET_DIR"
cargo fetch --manifest-path "$BUILD_SRC/Cargo.toml"
python3 "$REPO_ROOT/ci/patch-quercus-ffmpeg-link.py" "$BUILD_SRC" "$WORK_ROOT" "$REPO_ROOT"
python3 "$REPO_ROOT/ci/patch-quercus-engine-static.py"

echo "==> cargo build (FFmpeg + OCIO built from source, static; first run is slow)"
export WGPU_BACKEND="${WGPU_BACKEND:-vulkan}"
# 让 bootstrap FFmpeg prefix 的 -L 排在系统路径之前：否则链接器可能选中
# /usr/lib 下非 PIC / 带额外依赖的系统静态库（freetype→png/brotli 等）。
export RUSTFLAGS="${RUSTFLAGS:-} -L native=$QUERCUS_FFMPEG_CACHE/ffmpeg/lib"
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
