# oak-mcp (example-mcp 0.1.0) — Linux x86_64 build report

Task: task-1 on the shared board (cross-build team). Build `example-mcp`'s
`oak-mcp` for Linux x86_64, verify with `--check` + real MCP export, package
binary + runtime deps, test in a clean Ubuntu container.

- Status: **SUCCESS** (`--check` OK, MCP export OK, clean-container OK)
- Date: 2026-11-10 (Asia/Shanghai), start 17:11, final artifacts 19:22
- Host: macOS arm64, Docker 29, amd64 emulation; container: Ubuntu 24.04 amd64,
  Rust 1.99.1, FFmpeg 9.0 built from source into `/opt/ffmpeg9`
- Delivered binary: `/Users/sunyu/Documents/deepseek-harness/default-workspace/dist/linux-x86_64/bin/oak-mcp`
  (68,008,632 bytes, sha256 `6c051c75b5ceec8bd724002205e64052cb28346402918f7e13c5e648ee9a98d9`)

## Deliverables (absolute paths)

```
/Users/sunyu/Documents/deepseek-harness/default-workspace/dist/linux-x86_64/
├── bin/oak-mcp                      ELF 64-bit PIE, x86-64, 68,008,632 B
├── lib/                             41 non-base .so, 34 MB (cp -L, soname names)
├── README.md                        run deps / build recipe / verification
└── video-studio-linux-x86_64.tar.gz 34 MB, sha256 667095ae0e4187d5455c6154485d880ecb8115ce75cc31a2e0fb8ac43eec7be4
```

Build workspace (internal disk, NAS outage replacement): `/Users/sunyu/cross-linux/`

```
example-mcp/                        source copy (upstream + [patch.crates-io] for the build)
src/quercus-ffmpeg-link-patched/    patched link crate (see "Pitfall 4")
docker/Dockerfile                   reproducible build image (Ubuntu 24.04 + deps + Rust + FFmpeg 9)
docker/build-ffmpeg9.sh             FFmpeg 9.0 static build script
scripts/e2e_linux.py                MCP stdio end-to-end test
media/clip_a.mp4, clip_b.mp4        2x 4 s 1280x720 H.264/AAC test clips
logs/                               cargo/ffmpeg/e2e logs
```

Build image kept for reuse: `oak-linux-build:with-ffmpeg9` (4.43 GB) — Ubuntu
24.04 amd64 toolchain + codec/audio/GL/Vulkan dev+runtime packages + Rust 1.99.1
+ `/opt/ffmpeg9` + cargo registry cache.

## Key commands

### 1. Build environment / FFmpeg 9.0

```sh
docker build --platform linux/amd64 -t oak-linux-build:9.0 docker/     # Dockerfile
# FFmpeg 9.0 -> /opt/ffmpeg9 (build-ffmpeg9.sh), essentials:
./configure --prefix=/opt/ffmpeg9 --enable-gpl --enable-version3 --disable-doc \
  --disable-debug --disable-programs --disable-network \
  --enable-avcodec --enable-avformat --enable-avfilter --enable-avutil \
  --enable-swscale --enable-swresample --enable-static --disable-shared --enable-pic \
  --pkg-config-flags=--static --extra-cflags=-I/opt/ffmpeg9/include \
  --extra-ldflags=-L/opt/ffmpeg9/lib \
  --enable-libx264 --enable-libx265 --enable-libdav1d --enable-libvpx \
  --enable-libopus --enable-libvorbis --enable-libtheora --enable-libmp3lame \
  --enable-libspeex --enable-libopenjpeg --enable-libwebp --enable-libsnappy \
  --enable-libfreetype --enable-libfribidi --enable-libass --enable-libfontconfig \
  --disable-indev=xcbgrab --disable-xlib --disable-libxcb
make -j8 && make install
```

Configure output confirmed **all** external libraries enabled (no codec was
disabled): `bzlib iconv libass libdav1d libfontconfig libfreetype libfribidi
libmp3lame libopenjpeg libopus libsnappy libspeex libtheora libvorbis libvpx
libwebp libx264 libx265 lzma zlib`. `/opt/ffmpeg9/lib/pkgconfig` contains
libavcodec/avformat/avfilter/avutil/swscale/swresample/avdevice `.pc` files;
`Libs:` carries the full static closure (that is what quercus-ffmpeg-link reads).

### 2. Build oak-mcp

```sh
docker run -d --name oakbuild2 --platform linux/amd64 \
  -v /Users/sunyu/cross-linux:/work -w /work/example-mcp \
  -e FFMPEG_DIR=/opt/ffmpeg9 -e PKG_CONFIG_PATH=/opt/ffmpeg9/lib/pkgconfig \
  -e CARGO_TARGET_DIR=/work/target -e WGPU_BACKEND=vulkan \
  -e CXXFLAGS="-include cstdint" oak-linux-build:with-ffmpeg9 sleep infinity
docker exec oakbuild2 bash -lc 'cd /work/example-mcp && cargo build --release -j4'
# final build: Finished in 1m58s (incremental after the link patch);
# initial full compile ~12 min on 10-core Rosetta.
```

### 3. Verification

```sh
docker exec oakbuild2 bash -lc 'WGPU_BACKEND=vulkan /work/target/release/oak-mcp --check'
# exit 0, see output below

docker exec oakbuild2 bash -lc 'WGPU_BACKEND=vulkan python3 /work/scripts/e2e_linux.py \
  --bin /work/target/release/oak-mcp --media /work/media/clip_a.mp4 --media2 /work/media/clip_b.mp4'
```

`--check` output:

```json
{"ok": true, "version": "0.1.0", "engine": "quercus-engine-rs", "sequence": 3,
 "sequences": 1, "tracks": 4, "render_manager": true, "tools": 50,
 "protocol_versions": ["2025-06-18", "2025-03-26", "2024-11-05"]}
```

E2E (real stdio MCP: initialize → tools/list → project_new → media_import x2 →
clip_place_linked x2 → timeline_get → preview_frame → export_start → task_wait):

```
tools: 50
imported[0]: id=10 4.0s video=1 audio=1
imported[1]: id=11 4.0s video=1 audio=1
timeline: Sequence 1 1280x720 clips v=2 a=2
preview: 640x360 -> /work/e2e/export_linux.png
export started: task=t1
export finished: succeeded (10.903277s)
export verified: /work/e2e/export_linux.mp4 h264 1280x720 8.00s audio_streams=1 (['aac'])
OK: 10 checks passed
```

ffprobe of the exported file: `h264 1280x720 8.00s`, 1 audio stream `aac` —
matches the 2x4 s timeline.

### 4. Packaging

```sh
cp -L target/release/oak-mcp dist/bin/oak-mcp
ldd dist/bin/oak-mcp | awk '/=>/ {print $1, $3}'   # 47 shared objects
# copy every soname NOT shipped by bare ubuntu:24.04 into dist/lib (cp -L)
tar -czf video-studio-linux-x86_64.tar.gz bin lib README.md
```

Bundled (41): `libass libfontconfig libfreetype libvpx libwebpmux libdav1d
libsnappy libmp3lame libopenjp2 libopus libspeex libtheoraenc libtheoradec
libvorbisenc libvorbis libwebp libx264 libx265 libfribidi libharfbuzz
libunibreak libexpat libpng16 libbrotlidec libogg libcairo libsharpyuv libnuma
libglib-2.0 libgraphite2 libbrotlicommon libX11 libXext libXrender libxcb
libxcb-render libxcb-shm libpixman-1 libXau libXdmcp libbsd`.

Not bundled (present in base `ubuntu:24.04`): glibc/ld-linux, libm, libgcc_s,
libstdc++, libz, libbz2, liblzma, libpcre2-8, libmd.

### 5. Clean-container test (mandatory)

```sh
docker run --rm --platform linux/amd64 \
  -v .../dist/linux-x86_64:/pkg:ro ubuntu:24.04 bash -lc '
    apt-get update -qq && apt-get install -y --no-install-recommends \
      libvulkan1 mesa-vulkan-drivers libgl1 libegl1 libglx-mesa0 >/dev/null 2>&1
    cd /pkg; LD_LIBRARY_PATH=/pkg/lib ./bin/oak-mcp --check; echo EXIT:$?'
```

Result: `ldd` finds **0 missing libraries**, `--check` prints the same OK JSON
(`render_manager: true`, 50 tools), **EXIT:0**. No compiler, FFmpeg, or OCIO
package installed in that container.

## Failures and fixes

| # | Failure | Root cause | Fix |
|---|---|---|---|
| 1 | `docker build`: `ERROR: x265 not found using pkg-config` | Ubuntu's `x265.pc` `Libs.private` lists `-lnuma`, but `libnuma-dev` was missing; `--pkg-config-flags=--static` made configure's probe link `-lnuma` → test link failed | install `libnuma-dev` (added to Dockerfile) |
| 2 | cargo: `libspa-sys` build script panic: cannot find `libpipewire-0.3` | `install-deps.sh`'s audio-backend packages were not in the first Dockerfile | apt `libpipewire-0.3-dev libspa-0.2-dev libasound2-dev libpulse-dev libjack-jackd2-dev libsndfile1-dev libxkbcommon-dev libxkbcommon-x11-dev libudev-dev` (added to Dockerfile) |
| 3 | `quercus-ofx-plugin` build.rs: `fatal error: GL/gl.h: No such file or directory` | OpenGL dev headers missing (runtime `libgl1` only) | apt `libgl-dev libglvnd-dev libgl1-mesa-dev libegl-dev` (added to Dockerfile) |
| 4 | link `libquercus_engine.so`: `relocation R_X86_64_PC32 cannot be used against symbol 'stderr'; recompile with -fPIC` (bzlib.o/blocksort.o) | `quercus-ffmpeg-link` 0.7.0 bundles distro static archives (`libbz2.a`, `libz.a`, `libx264.a`, …) into the cdylib; Ubuntu static archives are not PIC. Upstream builds a staticlib, so the bug only shows with a cdylib target. | local patch of the crate (copy at `/Users/sunyu/cross-linux/src/quercus-ffmpeg-link-patched`, wired via `[patch.crates-io]` in the build-only source copy): system libs outside the FFmpeg prefix are linked **dynamically**; prefix archives stay static. After patching: `cargo clean -p quercus-ffmpeg-link && cargo build --release -j4` → success. Consequence: the codec/text stack appears as `.so` and ships in `lib/`. |
| 5 | Work area lost mid-build | `/Volumes/ExternalStorage` (NAS SMB) went offline at ~17:57; logs/target/source on it became unreachable | container was committed to image `oak-linux-build:with-ffmpeg9`; resumed in `/Users/sunyu/cross-linux` (internal disk). No rebuild of FFmpeg/apt needed. |

Codec differences vs. the requested set: **none** — all 16 requested external
libraries configured and enabled, no `--disable-*` fallback was needed. The only
configure-time additions were autodetected `zlib/bzlib/lzma/iconv` and
`--disable-xlib --disable-libxcb --disable-indev=xcbgrab` copied from
`scripts/ffmpeg/build-ffmpeg.sh` (X11 glue not needed by the engine; X11 libs
still end up as dynamic deps of libass/fontconfig).

## Notes / reproducibility

- OCIO comes from `ocio-sys`'s vendored `bundled` sources (distro OCIO 2.1.3 is
  too old for `ocio-sys` ≥ 2.4.1); `OCIO_INSTALL_DIR` is deliberately unset and
  `OCIO_RS_LINK` left at its static default. `CXXFLAGS="-include cstdint"` is
  required for the vendored yaml-cpp with GCC 13.
- `CARGO_TARGET_DIR` lives on the bind-mounted workspace, never in the container
  layer. Build target totals ~2.6 GB.
- The `[patch.crates-io]` entry exists only in `/Users/sunyu/cross-linux/example-mcp`
  (the build copy); the upstream reference source in `default-workspace/example-mcp`
  was not modified.
- Timing: FFmpeg 9.0 compile+install ~9 min (10-core, Rosetta); full cargo build
  ~12 min; incremental rebuild after the link patch 1m58s; `--check` < 1 s;
  MCP export 8 s clip → 10.9 s; packaging + clean-container test ~3 min.
