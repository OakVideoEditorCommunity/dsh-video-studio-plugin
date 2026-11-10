# cross-build：构建、打包与发布

从 `example-mcp`（Quercus 引擎的 MCP 服务器 `oak-mcp`）构建三平台产物，并打包成
DSH 插件 / npm 包 / GitHub Release 资产。

支持的平台：**Windows x86_64、Linux x86_64、macOS arm64**。

## 目录

```
ci/                          GitHub Actions 各平台构建脚本
  build-linux.sh              Linux：从源码构建 FFmpeg 9 + cargo build + 收集 .so
  build-ffmpeg9-linux.sh      FFmpeg 9 Linux 源码构建（CI 缓存）
  patch-quercus-ffmpeg-link.py  Linux 非 PIC 静态系统库修复（见下）
  build-windows.ps1           Windows：native MSVC + BtbN FFmpeg + conda OCIO
  build-macos.sh              macOS：Homebrew FFmpeg/OCIO + dylib 打包
  patches/                    上游 crate 补丁
cross-build/
  package-plugins.sh          生成三平台 DSH 插件分发包（zip/tar.gz）
  package-mcp.sh              生成三平台纯 MCP 分发包
  package-npm.sh              组装 npm 包（平台二进制包 + @oakvideoeditor/oak-mcp + 插件包）
  bundle-macos-dylibs.py      macOS：拷贝 Homebrew dylib 并改写为 @executable_path
  oak-mcp-launcher.mjs        npm 包内 oak-mcp 启动器（npx 用）
  templates/                  安装/卸载脚本与 README 模板
.github/workflows/build.yml  push tag（v*）→ 构建 + Release + npm 发布
```

## 各平台构建

### Linux x86_64（ubuntu-24.04 runner）

- 发行版没有 FFmpeg 9，`ci/build-ffmpeg9-linux.sh` 从源码构建到缓存前缀
  （codec 依赖用发行版 `-dev`，16 个外部 codec/filter 全部启用）。
- OCIO 由 `ocio-sys` 的 bundled 特性从 vendored 源码 CMake 构建。
- 上游 `quercus-ffmpeg-link` 会在 Linux 上把 `/usr/lib` 下的**非 PIC** 静态库
  （bz2/lzma/z/stdc++/asound/pipewire…）强绑为 `static=`，导致链接 shared cdylib 时
  `R_X86_64_PC32 ... recompile with -fPIC`。`ci/patches/quercus-ffmpeg-link-linux-dynamic.patch`
  让这些系统库改回动态链接（FFmpeg prefix 内的 .a 仍是 static）。
- `--check` 需要 Mesa 软件 Vulkan（apt `mesa-vulkan-drivers`），runner 上直接可跑。

### Windows x86_64（windows-latest，native MSVC）

- FFmpeg 9 用 BtbN `ffmpeg-n9.0-latest-win64-gpl-shared-9.0.zip`（含 `include/`、
  `lib/*.lib` 导入库、`lib/pkgconfig`、`bin/*.dll`；不要用 static 包，它没有开发文件）。
- OpenColorIO 2.5 用 conda-forge `win-64` 的 `libopencolorio` + `pkgconf` 现装；
  脚本会自动生成 `OpenColorIO.pc` 与 `pkg-config.exe` shim。
- `ilammy/msvc-dev-cmd` 设置 MSVC 环境；`BINDGEN_EXTRA_CLANG_ARGS` 从 `INCLUDE`
  生成，保证 bindgen 按 Windows 头文件解析（否则 `AVIOContext` 布局错位）。
- 运行库随 exe app-local：FFmpeg 7 个 DLL + OCIO/Imath/yaml-cpp/pystring/minizip/expat/
  zlib/bz2/lzma/zstd + MSVC CRT。

### macOS arm64（macos-14 runner）

- `brew install ffmpeg opencolorio`；`FFMPEG_DIR=$(brew --prefix ffmpeg)`、
  `OCIO_INSTALL_DIR=$(brew --prefix opencolorio)`、`OCIO_RS_LINK=dynamic`。
- `cross-build/bundle-macos-dylibs.py` 递归收集 Homebrew dylib 到 `lib/`，把 install name
  改写为 `@executable_path/../lib` / `@loader_path`，并 ad-hoc 重签，产物不依赖本机 Homebrew。

## 打包与发布

`package-plugins.sh`：

```bash
bash cross-build/package-plugins.sh --plugin-src plugin --version 0.1.0 \
  --linux-binary <bin>  --linux-libs <dir> \
  --windows-binary <exe> --windows-dlls <dir> \
  --macos-binary <bin>  --macos-libs <dir>
# dist/video-studio-{linux-x86_64.tar.gz,windows-x86_64.zip,macos-arm64.tar.gz}
```

`package-mcp.sh` 生成纯 MCP 包 `oak-mcp-<platform>.{tar.gz,zip}`；
`package-npm.sh` 组装 5 个 npm 包：

- `@oakvideoeditor/oak-mcp-darwin-arm64|linux-x64|win32-x64`（平台二进制）
- `@oakvideoeditor/oak-mcp`（npx 启动器，`bin: oak-mcp`）
- `@oakvideoeditor/oak-deepseek-plugin`（DSH 插件，`optionalDependencies` 引用平台二进制包）

DSH 插件首次激活时由 Host 半把平台二进制复制到用户目录（Windows
`%LOCALAPPDATA%\video-studio`；Linux/macOS `~/.local/share/video-studio`），
然后 `dsh-mcp-client` 行启动 MCP；也可用 `VIDEO_STUDIO_MCP_BIN` 覆盖。

## GitHub Actions

`.github/workflows/build.yml`：

- `push tag v*` → 三平台构建 → GitHub Release（插件包 + 纯 MCP 包 + SHA256SUMS）
  → npm 发布（需仓库 secret `NPM_TOKEN`）；
- `workflow_dispatch` → 只构建并上传 artifacts，不发布。

发布流程：本地把 tag 打到已通过 CI 的 commit 上，例如

```bash
git tag -a v0.1.0 -m "v0.1.0" && git push origin v0.1.0
```

## 验证记录

- Linux：构建容器 + 干净 `ubuntu:24.04` 均 `--check` 通过（ldd 0 missing），
  真实 MCP 导出（8s H.264+AAC）通过，见 [linux-REPORT.md](linux-REPORT.md)。
- Windows：PE32+ x86-64；Wine 11.21 下 `--check`（ok / 50 tools / render_manager）、
  MCP 握手、3s H.264+AAC 导出通过。
- macOS arm64：dylib 打包后 `--check` 通过（从 `lib/` 加载，不依赖 Homebrew 路径）。
- 插件分发包在干净 Linux 容器 / 临时 DSH profile 中安装加载验证通过。

## 上游修复建议

1. `ocio-sys` build.rs 用 host 的 `cfg!(target_os)` 判断，交叉构建时会泄漏 `-lc++`/`-lstdc++`；
2. `quercus-engine-rs` 的 `cfg(not(windows))` build-dependency 在交叉时按 host 求值；
3. `quercus-ffmpeg-sys` 的 bindgen 应显式传 `--target`；
4. `quercus-ffmpeg-link` 在 Linux 强绑非 PIC 系统静态库（本仓库用 patch 规避）。
