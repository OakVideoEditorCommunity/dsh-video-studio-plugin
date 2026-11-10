#!/usr/bin/env bash
# GitHub Actions: 构建 oak-mcp macOS arm64，并把 bin/ + lib/ 放到 $OUT_DIR。
#
# FFmpeg 9 与 OpenColorIO 都由 quercus bootstrap 从源码静态构建（不依赖 Homebrew
# ffmpeg/opencolorio，只需要 Homebrew 的构建工具链）。产物通常只剩系统框架依赖。
#
# 环境变量：
#   UPSTREAM_SRC          干净的 example-mcp 源码目录
#   WORK_ROOT             工作目录（默认 $RUNNER_TEMP/oak-build）
#   QUERCUS_FFMPEG_CACHE  bootstrap 缓存目录（默认 $WORK_ROOT/quercus-ffmpeg）
#   OUT_DIR               产物目录（默认 $WORK_ROOT/out/macos-arm64）
#   REPO_ROOT             本插件仓库根目录
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
WORK_ROOT="${WORK_ROOT:-${RUNNER_TEMP:-/tmp}/oak-build}"
UPSTREAM_SRC="${UPSTREAM_SRC:?UPSTREAM_SRC is required}"
OUT_DIR="${OUT_DIR:-$WORK_ROOT/out/macos-arm64}"
BUILD_SRC="$WORK_ROOT/example-mcp-build"
TARGET_DIR="$WORK_ROOT/target-macos"
export QUERCUS_FFMPEG_CACHE="${QUERCUS_FFMPEG_CACHE:-$WORK_ROOT/quercus-ffmpeg}"

[ "$(uname -s)" = "Darwin" ] || { echo "macOS only" >&2; exit 1; }
[ "$(uname -m)" = "arm64" ] || { echo "arm64 only" >&2; exit 1; }

echo "==> build tools"
# 与 example-mcp scripts/install-deps.sh 的 macOS 列表一致
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

echo "==> cargo build (FFmpeg + OCIO built from source, static; first run is slow)"
# OCIO 由 ocio-sys bundled 特性静态构建
export OCIO_RS_LINK=static
export OCIO_RS_ENABLE_REAL=1
cargo build --release --manifest-path "$BUILD_SRC/Cargo.toml"

BIN="$TARGET_DIR/release/oak-mcp"
[ -x "$BIN" ] || { echo "binary missing: $BIN" >&2; exit 1; }

echo "==> --check"
"$BIN" --check

echo "==> bundle non-system dylibs (usually none: FFmpeg/OCIO are static)"
rm -rf "$OUT_DIR"
python3 "$REPO_ROOT/cross-build/bundle-macos-dylibs.py" "$BIN" "$OUT_DIR"
echo "==> staged -> $OUT_DIR"
