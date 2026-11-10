#!/usr/bin/env bash
# GitHub Actions: 构建 oak-mcp macOS arm64，并把可重定位的 bin/ + lib/ 放到 $OUT_DIR。
#
# 依赖（workflow 中 brew 安装）：ffmpeg、opencolorio。
# 环境变量：
#   UPSTREAM_SRC   干净的 example-mcp 源码目录
#   WORK_ROOT      工作目录（默认 $RUNNER_TEMP/oak-build）
#   OUT_DIR        产物目录（默认 $WORK_ROOT/out/macos-arm64）
#   REPO_ROOT      本插件仓库根目录
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
WORK_ROOT="${WORK_ROOT:-${RUNNER_TEMP:-/tmp}/oak-build}"
UPSTREAM_SRC="${UPSTREAM_SRC:?UPSTREAM_SRC is required}"
OUT_DIR="${OUT_DIR:-$WORK_ROOT/out/macos-arm64}"
BUILD_SRC="$WORK_ROOT/example-mcp-build"
TARGET_DIR="$WORK_ROOT/target-macos"

[ "$(uname -s)" = "Darwin" ] || { echo "macOS only" >&2; exit 1; }
[ "$(uname -m)" = "arm64" ] || { echo "arm64 only" >&2; exit 1; }

echo "==> dependencies"
command -v ffmpeg >/dev/null || brew install ffmpeg
brew list --versions opencolorio >/dev/null 2>&1 || brew install opencolorio
command -v pkg-config >/dev/null || brew install pkgconf

FFMPEG_PREFIX="$(brew --prefix ffmpeg)"
OCIO_PREFIX="$(brew --prefix opencolorio)"
echo "ffmpeg: $("$FFMPEG_PREFIX/bin/ffmpeg" -version | head -1)"
echo "opencolorio: $(pkg-config --modversion OpenColorIO 2>/dev/null || true)"

echo "==> upstream copy"
rm -rf "$BUILD_SRC"
cp -a "$UPSTREAM_SRC" "$BUILD_SRC"
export CARGO_TARGET_DIR="$TARGET_DIR"
export FFMPEG_DIR="$FFMPEG_PREFIX"
export OCIO_INSTALL_DIR="$OCIO_PREFIX"
export OCIO_RS_LINK=dynamic
export PKG_CONFIG_PATH="$FFMPEG_PREFIX/lib/pkgconfig:$OCIO_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

echo "==> cargo build"
cargo build --release --manifest-path "$BUILD_SRC/Cargo.toml"

BIN="$TARGET_DIR/release/oak-mcp"
[ -x "$BIN" ] || { echo "binary missing: $BIN" >&2; exit 1; }

echo "==> --check"
"$BIN" --check

echo "==> bundle Homebrew dylibs"
rm -rf "$OUT_DIR"
python3 "$REPO_ROOT/cross-build/bundle-macos-dylibs.py" "$BIN" "$OUT_DIR"
echo "==> staged -> $OUT_DIR"
