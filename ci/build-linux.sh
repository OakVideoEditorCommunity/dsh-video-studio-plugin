#!/usr/bin/env bash
# GitHub Actions: 构建 oak-mcp Linux x86_64，并把 bin/ + lib/ 放到 $OUT_DIR。
#
# FFmpeg 9 与 OpenColorIO 都由 quercus 的 bootstrap 机制从源码**静态**构建：
#   - ffmpeg: quercus-ffmpeg-bootstrap → vendored tooling/ffmpeg/build-ffmpeg.sh
#   - OCIO:   ocio-sys `bundled` 特性 → vendored OpenColorIO CMake
# 不使用系统 FFmpeg。首次构建较慢，workflow 会缓存前缀。
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

SUDO=""
[ "$(id -u)" = 0 ] || SUDO="sudo"

# CI gets the toolchain/system libraries from Quercus itself, so the release
# build and upstream CI share one dependency set (libva/libdrm/ffnvcodec...).
# Local builds are untouched unless QUERCUS_INSTALL_DEPS=1 is set.
if [ "${CI:-}" = "true" ] || [ "${QUERCUS_INSTALL_DEPS:-0}" = "1" ]; then
	echo "==> install system dependencies (Quercus tooling/install-deps.sh)"
	DEPS_SCRIPT=$(ls -d "${CARGO_HOME:-$HOME/.cargo}"/registry/src/*/quercus-ffmpeg-bootstrap-*/tooling/install-deps.sh 2>/dev/null | sort -V | tail -n 1)
	[ -n "$DEPS_SCRIPT" ] || { echo "ERROR: quercus-ffmpeg-bootstrap tooling/install-deps.sh not found (run cargo fetch first)" >&2; exit 1; }
	bash "$DEPS_SCRIPT"
	# Some install-deps branches omit ffnvcodec headers, which NVDEC/NVENC need.
	if ! pkg-config --exists ffnvcodec 2>/dev/null; then
		echo "==> install ffnvcodec headers (NVENC/NVDEC)"
		rm -rf "$WORK_ROOT/nv-codec-headers"
		git clone --depth 1 https://github.com/FFmpeg/nv-codec-headers.git "$WORK_ROOT/nv-codec-headers"
		$SUDO make -C "$WORK_ROOT/nv-codec-headers" install PREFIX=/usr/local
		export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
	fi
fi

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

echo "==> verify hardware codecs (VAAPI / NVENC / NVDEC)"
for enc in h264_vaapi hevc_vaapi h264_nvenc hevc_nvenc; do
	grep -aq "$enc" "$BIN" || { echo "ERROR: $enc not compiled into $BIN" >&2; exit 1; }
done
ldd "$BIN" | grep -q "libva.so" || { echo "ERROR: libva not linked (VAAPI disabled)" >&2; exit 1; }
echo "==> hardware codecs present: VAAPI, NVENC, NVDEC"

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
