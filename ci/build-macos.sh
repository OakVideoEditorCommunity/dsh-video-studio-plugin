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

echo "==> upstream copy"
mkdir -p "$WORK_ROOT"
rm -rf "$BUILD_SRC"
cp -a "$UPSTREAM_SRC" "$BUILD_SRC"
export CARGO_TARGET_DIR="$TARGET_DIR"

echo "==> cargo fetch"
cargo fetch --manifest-path "$BUILD_SRC/Cargo.toml"

# 依赖集合直接来自 Quercus 的 tooling/install-deps.sh（brew 包），
# 避免这里和上游各自维护一份列表。
if [ "${CI:-}" = "true" ] || [ "${QUERCUS_INSTALL_DEPS:-0}" = "1" ]; then
	echo "==> install system dependencies (Quercus tooling/install-deps.sh)"
	DEPS_SCRIPT=$(ls -d "${CARGO_HOME:-$HOME/.cargo}"/registry/src/*/quercus-ffmpeg-bootstrap-*/tooling/install-deps.sh 2>/dev/null | sort -V | tail -n 1)
	[ -n "$DEPS_SCRIPT" ] || { echo "ERROR: quercus-ffmpeg-bootstrap tooling/install-deps.sh not found (run cargo fetch first)" >&2; exit 1; }
	bash "$DEPS_SCRIPT"
fi

echo "==> cargo build (FFmpeg + OCIO built from source, static; first run is slow)"
# OCIO 由 ocio-sys bundled 特性静态构建
export OCIO_RS_LINK=static
export OCIO_RS_ENABLE_REAL=1
cargo build --release --manifest-path "$BUILD_SRC/Cargo.toml"

BIN="$TARGET_DIR/release/oak-mcp"
[ -x "$BIN" ] || { echo "binary missing: $BIN" >&2; exit 1; }

echo "==> bundle non-system dylibs (FFmpeg/OCIO static; may still pull zlib etc.)"
export BUNDLE_EXTRA_SEARCH_DIRS="$QUERCUS_FFMPEG_CACHE:$TARGET_DIR"
rm -rf "$OUT_DIR"
python3 "$REPO_ROOT/cross-build/bundle-macos-dylibs.py" "$BIN" "$OUT_DIR"

echo "==> --check (bundled binary, no Homebrew dependency)"
"$OUT_DIR/bin/oak-mcp" --check

echo "==> verify hardware codecs (VideoToolbox)"
for enc in h264_videotoolbox hevc_videotoolbox; do
	grep -aq "$enc" "$OUT_DIR/bin/oak-mcp" || { echo "ERROR: $enc not compiled into oak-mcp" >&2; exit 1; }
done
echo "==> hardware codecs present: VideoToolbox (H.264/HEVC)"
echo "==> staged -> $OUT_DIR"
