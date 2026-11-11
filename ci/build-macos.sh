#!/usr/bin/env bash
# GitHub Actions: 构建 oak-mcp macOS arm64，并把 bin/ + lib/ 放到 $OUT_DIR。
#
# 上游 0.7.1 起要求显式提供 FFMPEG_DIR；macOS 没有 BtbN 预编译包，这里用上游
# 的 FFmpeg 构建脚本从源码构建（含 VideoToolbox），OpenColorIO 由 ocio-sys
# bundled 特性静态构建。不依赖 Homebrew ffmpeg/opencolorio。
#
# 环境变量：
#   UPSTREAM_SRC          干净的 example-mcp 源码目录
#   WORK_ROOT             工作目录（默认 $RUNNER_TEMP/oak-build）
#   OUT_DIR               产物目录（默认 $WORK_ROOT/out/macos-arm64）
#   REPO_ROOT             本插件仓库根目录
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
WORK_ROOT="${WORK_ROOT:-${RUNNER_TEMP:-/tmp}/oak-build}"
UPSTREAM_SRC="${UPSTREAM_SRC:?UPSTREAM_SRC is required}"
OUT_DIR="${OUT_DIR:-$WORK_ROOT/out/macos-arm64}"
BUILD_SRC="$WORK_ROOT/example-mcp-build"
TARGET_DIR="$WORK_ROOT/target-macos"

[ "$(uname -s)" = "Darwin" ] || { echo "macOS only" >&2; exit 1; }
[ "$(uname -m)" = "arm64" ] || { echo "arm64 only" >&2; exit 1; }

echo "==> build tools (Homebrew)"
command -v cmake >/dev/null || brew install cmake
command -v nasm >/dev/null || brew install nasm
command -v meson >/dev/null || brew install meson
command -v ninja >/dev/null || brew install ninja
command -v pkg-config >/dev/null || brew install pkgconf
command -v autoconf >/dev/null || brew install autoconf automake libtool autoconf-archive gperf

echo "==> upstream copy"
mkdir -p "$WORK_ROOT"
rm -rf "$BUILD_SRC"
cp -a "$UPSTREAM_SRC" "$BUILD_SRC"
export CARGO_TARGET_DIR="$TARGET_DIR"

# 上游的 FFmpeg 构建脚本位置在 0.7.0/0.7.1 之间可能从 scripts/ 移到 tooling/。
BUILD_FFMPEG="$BUILD_SRC/scripts/ffmpeg/build-ffmpeg.sh"
[ -f "$BUILD_FFMPEG" ] || BUILD_FFMPEG="$BUILD_SRC/tooling/ffmpeg/build-ffmpeg.sh"
[ -f "$BUILD_FFMPEG" ] || { echo "ERROR: upstream FFmpeg build script not found" >&2; exit 1; }

FFMPEG_CACHE_DIR="$WORK_ROOT/ffmpeg-macos"
echo "==> FFmpeg (source, shared, VideoToolbox)"
if [ -f "$FFMPEG_CACHE_DIR/lib/libavcodec.dylib" ]; then
	echo "==> reusing cached FFmpeg prefix: $FFMPEG_CACHE_DIR"
else
	(cd "$BUILD_SRC" && bash "$BUILD_FFMPEG" --shared)
	rm -rf "$FFMPEG_CACHE_DIR"
	cp -a "$BUILD_SRC/.cache/ffmpeg" "$FFMPEG_CACHE_DIR"
fi
# The binary's install names point at .cache/ffmpeg; keep that path valid
# even when the prefix came from the cache.
mkdir -p "$BUILD_SRC/.cache"
rm -rf "$BUILD_SRC/.cache/ffmpeg"
ln -s "$FFMPEG_CACHE_DIR" "$BUILD_SRC/.cache/ffmpeg"
export FFMPEG_DIR="$BUILD_SRC/.cache/ffmpeg"
export PKG_CONFIG_PATH="$FFMPEG_DIR/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
[ -f "$FFMPEG_DIR/lib/libavcodec.dylib" ] || { echo "ERROR: FFMPEG_DIR is incomplete: $FFMPEG_DIR" >&2; exit 1; }

echo "==> cargo fetch + bundled OCIO include fix"
cargo fetch --manifest-path "$BUILD_SRC/Cargo.toml"
bash "$BUILD_SRC/scripts/fix-ocio-bundled.sh"

echo "==> cargo build (FFmpeg via FFMPEG_DIR + default OCIO)"
cargo build --release --manifest-path "$BUILD_SRC/Cargo.toml"

BIN="$TARGET_DIR/release/oak-mcp"
[ -x "$BIN" ] || { echo "binary missing: $BIN" >&2; exit 1; }

echo "==> bundle non-system dylibs"
export BUNDLE_EXTRA_SEARCH_DIRS="$FFMPEG_DIR:$TARGET_DIR"
rm -rf "$OUT_DIR"
python3 "$REPO_ROOT/cross-build/bundle-macos-dylibs.py" "$BIN" "$OUT_DIR"

echo "==> --check (bundled binary, no Homebrew dependency)"
"$OUT_DIR/bin/oak-mcp" --check

echo "==> verify hardware codecs (VideoToolbox)"
AVCODEC_DYLIB=$(ls "$FFMPEG_DIR"/lib/libavcodec*.dylib 2>/dev/null | head -n 1)
[ -n "$AVCODEC_DYLIB" ] || { echo "ERROR: FFmpeg libavcodec dylib not found" >&2; exit 1; }
for enc in h264_videotoolbox hevc_videotoolbox; do
	grep -aq "$enc" "$AVCODEC_DYLIB" || { echo "ERROR: $enc not compiled into libavcodec" >&2; exit 1; }
done
otool -L "$OUT_DIR/bin/oak-mcp" | grep -q "libavcodec" || { echo "ERROR: libavcodec not linked" >&2; exit 1; }
echo "==> hardware codecs present: VideoToolbox (H.264/HEVC)"
echo "==> staged -> $OUT_DIR"
