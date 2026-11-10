# cross-build：构建、打包与发布

从 `example-mcp`（Quercus 引擎的 MCP 服务器 `oak-mcp`）构建三平台产物，并打包成
DSH 插件 / npm 包 / GitHub Release 资产。

支持的平台：**Windows x86_64、Linux x86_64、macOS arm64**。

## 目录

```
ci/                          GitHub Actions 各平台构建脚本
  build-linux.sh              Linux：BtbN FFmpeg shared + cargo build + .so/rpath
  build-windows.ps1           Windows：native MSVC + BtbN FFmpeg shared + bundled OCIO
  build-macos.sh              macOS：源码 FFmpeg（FFMPEG_DIR）+ dylib 打包
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

- 上游要求显式 `FFMPEG_DIR`；这里下载固定版本的 **BtbN FFmpeg 9.0.2 GPL shared**
  （autobuild + SHA256），设置 `FFMPEG_DIR`/`PKG_CONFIG_PATH`/`LD_LIBRARY_PATH`。
- OpenColorIO 由 `ocio-sys` 的 bundled 特性从 vendored 源码 CMake **静态**构建。
- `--check` 需要 Mesa 软件 Vulkan（apt `mesa-vulkan-drivers`）。
- 产物把非 glibc 运行库收进 `lib/`，二进制与每个库都带 `$ORIGIN` rpath；按 Ubuntu 24.04
  （glibc 2.39）构建，面向 Debian 13 / Fedora 43 / Arch 等现代发行版。

### Windows x86_64（windows-latest，native MSVC）

- 同样用固定版本的 **BtbN FFmpeg 9.0.2 GPL shared**（headers + MSVC 导入库 + DLL），
  通过 `FFMPEG_DIR`/`PKG_CONFIG_PATH` 动态链接；含 NVENC/NVDEC/CUDA、QSV、AMF、
  D3D11VA/DXVA2/MediaFoundation。
- OpenColorIO 由 `ocio-sys` 的 `bundled` 特性从源码用 CMake **静态构建**。
- `ilammy/msvc-dev-cmd` 设置 MSVC 环境；`BINDGEN_EXTRA_CLANG_ARGS` 从 `INCLUDE`
  生成，保证 bindgen 按 Windows 头文件解析（否则 `AVIOContext` 布局错位）。
- 运行库随 exe app-local：FFmpeg DLL + OCIO/Imath/yaml-cpp/pystring/minizip/expat/
  zlib/bz2/lzma/zstd + MSVC CRT。

### macOS arm64（macos-15 runner）

- 只需 Homebrew 构建工具（cmake/nasm/meson/ninja/pkgconf/autotools/gperf）；
  上游的 FFmpeg 构建脚本（scripts/ffmpeg 或 tooling/ffmpeg）从源码构建 FFmpeg 9，
  导出 `FFMPEG_DIR`；OpenColorIO 由 ocio-sys bundled 静态构建。
  产物通常不依赖任何 Homebrew dylib。
- `cross-build/bundle-macos-dylibs.py` 递归收集 Homebrew dylib 到 `lib/`，把 install name
  改写为 `@executable_path/../lib` / `@loader_path`，并 ad-hoc 重签，产物不依赖本机 Homebrew。

## 打包与发布

`package-plugins.sh`：

```bash
bash cross-build/package-plugins.sh --plugin-src plugin --version 0.1.1 \
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
  → npm 发布（Trusted Publishing：GitHub Actions OIDC + `id-token: write`，无需 `NPM_TOKEN`）；
- `workflow_dispatch` → 只构建并上传 artifacts，不发布。

npmjs.com 上需为 5 个 `@oakvideoeditor/*` 包各配置一个 trusted publisher：
仓库 `OakVideoEditorCommunity/dsh-video-studio-plugin`、workflow 文件名 `build.yml`、环境留空。

发布流程：本地把 tag 打到已通过 CI 的 commit 上，例如

```bash
git tag -a v0.1.1 -m "v0.1.1" && git push origin v0.1.1
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
