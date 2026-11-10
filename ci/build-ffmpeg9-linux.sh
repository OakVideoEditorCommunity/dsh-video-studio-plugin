#!/usr/bin/env bash
# 构建 FFmpeg 9.0 静态库到 $1（默认 $RUNNER_TEMP/ffmpeg9）。
# 与 macOS/Windows 不同，Ubuntu 发行版没有 FFmpeg 9，CI 里从源码构建一次并缓存。
set -euo pipefail

PREFIX="${1:?usage: build-ffmpeg9-linux.sh <prefix>}"
VERSION="9.0"
SRC="${FFMPEG_SRC:-$(dirname "$PREFIX")/ffmpeg-src}"
JOBS="${JOBS:-$(nproc)}"

if [ -f "$PREFIX/.ok" ] && [ -f "$PREFIX/lib/pkgconfig/libavcodec.pc" ]; then
	echo "FFmpeg 9 cache hit: $PREFIX"
	exit 0
fi

mkdir -p "$SRC"
cd "$SRC"
if [ ! -f "ffmpeg-${VERSION}.tar.xz" ]; then
	curl -fL --retry 3 -o "ffmpeg-${VERSION}.tar.xz" \
		"https://ffmpeg.org/releases/ffmpeg-${VERSION}.tar.xz"
fi
rm -rf "ffmpeg-${VERSION}"
tar xf "ffmpeg-${VERSION}.tar.xz"
cd "ffmpeg-${VERSION}"

FLAGS=(
	"--prefix=$PREFIX"
	--enable-gpl
	--enable-version3
	--disable-doc
	--disable-debug
	--disable-programs
	--disable-network
	--enable-avcodec --enable-avformat --enable-avfilter
	--enable-avutil --enable-swscale --enable-swresample
	--enable-static --disable-shared --enable-pic
	--pkg-config-flags=--static
	"--extra-cflags=-I$PREFIX/include"
	"--extra-ldflags=-L$PREFIX/lib"
	--enable-libx264 --enable-libx265 --enable-libdav1d --enable-libvpx
	--enable-libopus --enable-libvorbis --enable-libtheora
	--enable-libmp3lame --enable-libspeex
	--enable-libopenjpeg --enable-libwebp --enable-libsnappy
	--enable-libfreetype --enable-libfribidi --enable-libass --enable-libfontconfig
	--disable-indev=xcbgrab
	--disable-xlib --disable-libxcb
)

echo ">> configure FFmpeg $VERSION -> $PREFIX"
./configure "${FLAGS[@]}"
echo ">> make -j$JOBS"
make -j"$JOBS"
echo ">> make install"
make install
touch "$PREFIX/.ok"
echo ">> FFmpeg installed: $PREFIX"
