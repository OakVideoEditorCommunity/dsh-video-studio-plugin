#!/usr/bin/env bash
# GitHub Actions: 构建 oak-mcp Linux x86_64，并把 bin/ + lib/ 放到 $OUT_DIR。
#
# FFmpeg 9 使用固定版本的 BtbN GPL shared 预编译包（动态链接，DLL/SO 随产物分发），
# OpenColorIO 由 ocio-sys `bundled` 特性从源码静态构建。
# 不构建 FFmpeg 源码，也不使用系统 FFmpeg。
#
# 环境变量：
#   UPSTREAM_SRC          干净的 example-mcp 源码目录
#   WORK_ROOT             工作目录（默认 $RUNNER_TEMP/oak-build）
#   OUT_DIR               产物目录（默认 $WORK_ROOT/out/linux-x64）
#   REPO_ROOT             本插件仓库根目录
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
WORK_ROOT="${WORK_ROOT:-${RUNNER_TEMP:-/tmp}/oak-build}"
UPSTREAM_SRC="${UPSTREAM_SRC:?UPSTREAM_SRC is required}"
OUT_DIR="${OUT_DIR:-$WORK_ROOT/out/linux-x64}"
BUILD_SRC="$WORK_ROOT/example-mcp-build"
TARGET_DIR="$WORK_ROOT/target-linux"

# Pinned BtbN FFmpeg 9.0.2 GPL shared build (autobuild release + SHA256).
BTBN_URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-11-10-12-39/ffmpeg-n9.0.2-48-gd4070a14ce-linux64-gpl-shared-9.0.tar.xz"
BTBN_SHA256="19bc462dc230253465326c4600ca24a72475c6945b4f0c5d2bca522fdc2afc3f"
BTBN_ROOT="$WORK_ROOT/btbn-ffmpeg-linux"

mkdir -p "$WORK_ROOT" "$OUT_DIR"

echo "==> patched upstream copy"
rm -rf "$BUILD_SRC"
cp -a "$UPSTREAM_SRC" "$BUILD_SRC"
export CARGO_TARGET_DIR="$TARGET_DIR"
cargo fetch --manifest-path "$BUILD_SRC/Cargo.toml"

SUDO=""
[ "$(id -u)" = 0 ] || SUDO="sudo"

# CI gets the toolchain/system libraries from Quercus itself, so the release
# build and upstream CI share one dependency set.
if [ "${CI:-}" = "true" ] || [ "${QUERCUS_INSTALL_DEPS:-0}" = "1" ]; then
	echo "==> install system dependencies (Quercus tooling/install-deps.sh)"
	DEPS_SCRIPT=$(ls -d "${CARGO_HOME:-$HOME/.cargo}"/registry/src/*/quercus-ffmpeg-bootstrap-*/tooling/install-deps.sh 2>/dev/null | sort -V | tail -n 1)
	[ -n "$DEPS_SCRIPT" ] || { echo "ERROR: quercus-ffmpeg-bootstrap tooling/install-deps.sh not found (run cargo fetch first)" >&2; exit 1; }
	bash "$DEPS_SCRIPT"
fi

# ---- BtbN FFmpeg 9.0 GPL shared ------------------------------------------------
BTBN_PREFIX=""
if [ -d "$BTBN_ROOT" ]; then
	BTBN_PREFIX=$(find "$BTBN_ROOT" -maxdepth 1 -mindepth 1 -type d -name 'ffmpeg-*' | head -n 1)
fi
if [ -z "$BTBN_PREFIX" ] || [ ! -e "$BTBN_PREFIX/lib/libavcodec.so" ]; then
	echo "==> downloading BtbN FFmpeg 9.0 shared build"
	ARCHIVE="$WORK_ROOT/btbn-ffmpeg-linux.tar.xz"
	curl -fL --retry 3 --output "$ARCHIVE" "$BTBN_URL"
	echo "$BTBN_SHA256  $ARCHIVE" | sha256sum -c -
	rm -rf "$BTBN_ROOT"
	mkdir -p "$BTBN_ROOT"
	tar -xJf "$ARCHIVE" -C "$BTBN_ROOT"
	BTBN_PREFIX=$(find "$BTBN_ROOT" -maxdepth 1 -mindepth 1 -type d -name 'ffmpeg-*' | head -n 1)
fi
[ -n "$BTBN_PREFIX" ] && [ -e "$BTBN_PREFIX/lib/libavcodec.so" ] || {
	echo "ERROR: BtbN FFmpeg prefix is incomplete: $BTBN_PREFIX" >&2
	exit 1
}
export FFMPEG_DIR="$BTBN_PREFIX"
export PKG_CONFIG_PATH="$BTBN_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="$BTBN_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
echo "==> FFmpeg: BtbN 9.0.2 shared -> $BTBN_PREFIX"

python3 "$REPO_ROOT/ci/patch-quercus-ffmpeg-bootstrap-shared.py"
python3 "$REPO_ROOT/ci/patch-quercus-codec-dynamic.py"
python3 "$REPO_ROOT/ci/patch-quercus-ffmpeg-link.py" "$BUILD_SRC" "$WORK_ROOT" "$REPO_ROOT"
python3 "$REPO_ROOT/ci/patch-quercus-engine-static.py"

echo "==> cargo build (FFmpeg via BtbN shared + OCIO bundled)"
export WGPU_BACKEND="${WGPU_BACKEND:-vulkan}"
cargo build --release --manifest-path "$BUILD_SRC/Cargo.toml"

BIN="$TARGET_DIR/release/oak-mcp"
[ -x "$BIN" ] || { echo "binary missing: $BIN" >&2; exit 1; }

echo "==> --check"
"$BIN" --check

echo "==> verify hardware codecs (VAAPI / NVENC / NVDEC / QSV / AMF)"
AVCODEC_LIB=$(ls "$BTBN_PREFIX"/lib/libavcodec.so.63* 2>/dev/null | head -n 1)
[ -n "$AVCODEC_LIB" ] || { echo "ERROR: BtbN libavcodec not found" >&2; exit 1; }
for enc in h264_vaapi hevc_vaapi h264_nvenc hevc_nvenc h264_qsv h264_amf; do
	grep -aq "$enc" "$AVCODEC_LIB" || { echo "ERROR: $enc not compiled into libavcodec" >&2; exit 1; }
done
ldd "$BIN" | grep -q "libavcodec.so" || { echo "ERROR: libavcodec not linked" >&2; exit 1; }
echo "==> hardware codecs present: VAAPI, NVENC, NVDEC, QSV, AMF"

echo "==> stage bin/ + running libraries"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/bin" "$OUT_DIR/lib"
cp "$BIN" "$OUT_DIR/bin/oak-mcp"
chmod +x "$OUT_DIR/bin/oak-mcp"
while IFS= read -r lib; do
	[ -n "$lib" ] || continue
	base=$(basename "$lib")
	case "$base" in
		libc.so*|libm.so*|libmvec.so*|libdl.so*|libpthread.so*|librt.so*|libresolv.so*|libutil.so*|ld-linux*) continue ;;
	esac
	cp -L "$lib" "$OUT_DIR/lib/" 2>/dev/null || true
done < <(ldd "$BIN" | awk '{print $3}' | grep '^/' || true)
ldd "$BIN" | grep "not found" && { echo "ERROR: missing runtime libraries" >&2; exit 1; } || true
echo "==> staged $(ls -1 "$OUT_DIR/lib" | wc -l | tr -d ' ') libraries -> $OUT_DIR"

echo "==> set \$ORIGIN rpath (bundled libs)"
command -v patchelf >/dev/null || { echo "ERROR: patchelf is required for \$ORIGIN rpath" >&2; exit 1; }
RPATH='$ORIGIN:$ORIGIN/lib:$ORIGIN/../lib'
patchelf --set-rpath "$RPATH" "$OUT_DIR/bin/oak-mcp"
while IFS= read -r -d '' lib; do
	patchelf --set-rpath '$ORIGIN' "$lib" 2>/dev/null || true
done < <(find "$OUT_DIR/lib" -maxdepth 1 -type f -name '*.so*' -print0)
readelf -d "$OUT_DIR/bin/oak-mcp" | grep -Eq '(RPATH|RUNPATH).*\$ORIGIN' || { echo "ERROR: \$ORIGIN rpath missing from oak-mcp" >&2; exit 1; }
echo "==> rpath: $RPATH"

echo "==> verify self-contained runtime closure"
LD_LIBRARY_PATH="$OUT_DIR/lib" ldd "$OUT_DIR/bin/oak-mcp" | grep "not found" && { echo "ERROR: bundled runtime closure is incomplete" >&2; exit 1; } || true
LD_LIBRARY_PATH="$OUT_DIR/lib" "$OUT_DIR/bin/oak-mcp" --check

echo "==> verify glibc baseline (Ubuntu 24.04 / modern distros)"
MAX_GLIBC=$(objdump -T "$OUT_DIR/bin/oak-mcp" | grep -o 'GLIBC_[0-9][0-9.]*' | sed 's/^GLIBC_//' | sort -Vu | tail -n 1)
[ -n "$MAX_GLIBC" ] || { echo "ERROR: could not determine glibc baseline" >&2; exit 1; }
[ "$(printf '%s\n' '2.39' "$MAX_GLIBC" | sort -V | tail -n 1)" = '2.39' ] || {
	echo "ERROR: binary requires GLIBC_$MAX_GLIBC (> 2.39); build on an older/modern-distro baseline" >&2
	exit 1
}
[ -f "$OUT_DIR/lib/libstdc++.so.6" ] || { echo "ERROR: libstdc++.so.6 not bundled" >&2; exit 1; }
echo "==> max glibc symbol: $MAX_GLIBC; libstdc++/libgcc bundled (Debian 13/Fedora 43/Arch)"
