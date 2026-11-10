# cross-build：oak-mcp 的 Windows / Linux x86_64 交叉构建与插件打包

本目录记录如何从 macOS arm64 交叉构建 [example-mcp](https://atomgit.com/oak-and-quercus/example-mcp)
（Quercus 引擎的 MCP 服务器 `oak-mcp`）的 **Windows x86_64** 与 **Linux x86_64** 版本，
并把「MCP 二进制 + DSH 插件」打包成分发件。

## 产物一览

| 平台 | 产物 | 说明 |
|---|---|---|
| Windows x86_64 | `dist/windows-x86_64/`、`dist/windows-x86_64/oak-mcp-windows-x86_64.zip` | `oak-mcp.exe`（PE32+）+ 26 个运行时 DLL；Wine 下 `--check` 与导出验证通过 |
| Linux x86_64 | `dist/linux-x86_64/`、`dist/linux-x86_64/video-studio-linux-x86_64.tar.gz` | `bin/oak-mcp`（68 MB，ELF PIE x86-64）+ 41 个随附 `.so`；Docker amd64 容器构建，干净 ubuntu:24.04 复测通过 |
| DSH 插件分发包 | `dist/video-studio-windows-x86_64.zip`、`dist/video-studio-linux-x86_64.tar.gz` | 插件 bundle + MCP 二进制 + 安装脚本 |
| macOS arm64（本机，已有） | `video-studio/bin/oak-mcp`、已安装的 `@local/video-studio` | 见 `video-studio-plugin/README.md` |

> 目标架构是 **x86_64（64 位 x86）**；未构建 32 位 i686。

## 目录

```
cross-build/
  package-plugins.sh            # 生成 per-platform 插件分发包 + 压缩包
  plugin-variants/{linux,windows}/cordis.patch.yml   # 平台版 MCP 启动路径（!!js 表达式）
  templates/                    # 安装/卸载脚本与 README 模板
dist/                           # 最终产物
/Volumes/ExternalStorage/cross/{linux,windows}/   # 构建工作区（源代码、依赖、target、日志）
```

## Windows x86_64 构建（成功）

完整报告：`/Volumes/ExternalStorage/cross/windows/REPORT.md`，构建脚本 `.../build.sh`。

要点：

- 目标 `x86_64-pc-windows-msvc`，用 **cargo-xwin**（下载 MSVC CRT + Windows SDK），
  编译器 clang-cl / lld-link（Homebrew LLVM）。
- **FFmpeg 9.0**：必须用 BtbN 的 `ffmpeg-n9.0-latest-win64-gpl-shared-9.0.zip`
  （含 `include/`、`lib/*.lib` 导入库、`lib/pkgconfig/*.pc`、`bin/*.dll`）；
  “gpl 静态包”只有 3 个 exe，没有开发文件。
- **OpenColorIO 2.5.2**：conda-forge `win-64` 包（MSVC 动态库），用 micromamba 展开成
  `ocio-prefix`，经 `OCIO_INSTALL_DIR` + `OpenColorIO.pc` 被 system-deps 探测，`OCIO_RS_LINK=dynamic`。
- 三个必踩的坑及绕过（详见 REPORT）：
  1. `ocio-sys` 的 build script 用 host `cfg!(target_os = "macos")` 泄漏 `-lc++` →
     在 `/LIBPATH` 目录放一个占位 `c++.lib`（空 COFF 归档）；
  2. `quercus-ffmpeg-sys` 的 bindgen 不传 `--target` → 用
     `BINDGEN_EXTRA_CLANG_ARGS_x86_64_pc_windows_msvc="--target=x86_64-pc-windows-msvc ..."`；
  3. `quercus-engine-rs` 的 `[target."cfg(not(windows))".build-dependencies]` 在交叉时按 host
     评估，会去构建 macOS 静态 FFmpeg → 在构建副本里 patch 掉该 build-dep（上游未改）。
- 验证：`file` → PE32+ x86-64；Wine 11.21 `--check`（ok、50 tools、render_manager）；
  MCP 握手 + `tools/list`；端到端导出 3s H.264/AAC MP4（ffprobe 通过）。
- 限制：未在真实 Windows 机器上运行；OCIO 动态链接；需要 Win10 1809+。

## Linux x86_64 构建（成功）

在 `docker run --platform linux/amd64` 的 Ubuntu 24.04 容器内**原生**构建
（Apple Silicon 上通过 Rosetta 模拟，构建较慢）。完整报告：[linux-REPORT.md](linux-REPORT.md)。

成果：

- `dist/linux-x86_64/bin/oak-mcp`：ELF 64-bit PIE x86-64，68,008,632 B，
  sha256 `6c051c75b5ceec8bd724002205e64052cb28346402918f7e13c5e648ee9a98d9`；
- `dist/linux-x86_64/lib/`：41 个非系统 `.so`（约 34 MB，`cp -L` 展开）；
- 干净 `ubuntu:24.04` 容器（只补 Mesa/Vulkan/GL 运行库）：`ldd` 0 missing，`--check` exit 0；
- 真实 MCP 导出：`project_new → media_import ×2 → clip_place_linked ×2 → preview_frame →
  export_start → task_wait`，ffprobe 得到 H.264 1280×720 8.00 s + AAC。

要点：

- Rust stable + **FFmpeg 9.0 从源码**构建到 `/opt/ffmpeg9`（发行版只有 FFmpeg 6/7），
  codec 依赖用发行版 `-dev` 包；16 个外部 codec/filter 全部启用，无禁用。
- OpenColorIO：发行版只有 2.1.3（低于 `ocio-sys` 要求的 2.4.1），不装系统 OCIO，
  由 `ocio-sys` 的 `bundled` 特性从 vendored 源码 CMake 构建。
- 构建镜像 `oak-linux-build:with-ffmpeg9` 保留在 Docker 中（可复现/快速重试）。
- 过程中遭遇 NAS（`/Volumes/ExternalStorage`）掉线，改为内部盘 `/Users/sunyu/cross-linux`
  从已 commit 的镜像续建。

## 插件打包（package-plugins.sh）

```bash
./cross-build/package-plugins.sh \
  --linux-binary dist/linux-x86_64/bin/oak-mcp \
  --linux-libs   dist/linux-x86_64/lib \
  --windows-binary dist/windows-x86_64/oak-mcp.exe \
  --windows-dlls  dist/windows-x86_64
```

产出：

- `dist/video-studio-linux-x86_64/` + `.tar.gz`
- `dist/video-studio-windows-x86_64/` + `.zip`

包结构（两平台相同）：

```
video-studio-<platform>-x86_64/
  README.md          # 平台说明（依赖、安装、使用、限制）
  install.{sh,ps1}   # 复制二进制到平台约定目录 + dsh plugin add
  uninstall.{sh,ps1}
  plugin/            # @local/video-studio DSH bundle
  mcp/               # oak-mcp 二进制 + 运行库
```

MCP 启动路径设计（避免写死绝对路径）：

- bundle patch 用 Loader `!!js` 表达式：
  - Linux：`process.env.VIDEO_STUDIO_MCP_BIN || (process.env.HOME + '/.local/share/video-studio/oak-mcp')`
  - Windows：`process.env.VIDEO_STUDIO_MCP_BIN || ((process.env.LOCALAPPDATA || ...) + '/video-studio/oak-mcp.exe')`
- 安装脚本把二进制放到上述约定目录；用户也可用 `VIDEO_STUDIO_MCP_BIN` 覆盖。
- 预览目录不写死：插件默认 `~/.dsh/video-studio/previews`（Windows 为 `%USERPROFILE%\.dsh\...`），
  系统提示会动态带上该绝对路径。

安装（终端用户）：

```bash
# Linux
tar xzf video-studio-linux-x86_64.tar.gz && cd video-studio-linux-x86_64 && ./install.sh
# Windows (PowerShell)
Expand-Archive video-studio-windows-x86_64.zip . ; cd video-studio-windows-x86_64 ; powershell -ExecutionPolicy Bypass -File .\install.ps1
```

然后重启 DeepSeek Harness。需要 dsh CLI 在 PATH，或设置 `DSH_CLI`；profile 默认 `desktop`
（可用 `DSH_PROFILE` 覆盖）。

## 验证状态

| 项 | Windows | Linux |
|---|---|---|
| 交叉/容器构建 | ✅ | ✅ |
| `--check`（引擎/50 工具/渲染） | ✅ Wine 11.21 | ✅ 容器 + 干净容器 |
| MCP stdio 握手 + tools/list | ✅ | ✅ |
| 真实导出 + ffprobe | ✅ 3 s H.264+AAC | ✅ 8 s H.264+AAC |
| 干净环境可运行性 | ✅ Wine | ✅ 干净 ubuntu:24.04（ldd 0 missing） |
| DSH 插件分发包生成 | ✅ | ✅ |
| 分发包在 DSH 中加载（用 macOS 二进制代跑） | ✅ | ✅ |
| 真实 Windows/Linux GUI 联调 | ⚠️ 未做 | ⚠️ 未做 |

## 上游修复建议

这些是交叉构建时暴露的上游问题（可提给 example-mcp / quercus-engine / ocio-sys）：

1. `ocio-sys` build.rs 应使用 `CARGO_CFG_TARGET_OS` 而不是 host 的 `cfg!(target_os)`；
2. `quercus-engine-rs` 的 `cfg(not(windows))` build-dependency 在交叉时按 host 求值，
   建议改成显式 target 条件；
3. `quercus-ffmpeg-sys` 的 bindgen 应传 `--target`，否则 Windows 头会按 host LP64 解析
   （`AVIOContext` 布局错位）；
4. `quercus-ffmpeg-link` 在 Linux 上把 `/usr/lib` 下的非 PIC 静态系统库（bz2/lzma/z/stdc++/…）
   强绑为 `static=`，链接 shared cdylib 时会报 `R_X86_64_PC32 ... recompile with -fPIC`；
   交叉/发行构建需改为动态链接（本次通过 `[patch.crates-io]` 修正，见 linux-REPORT.md）。
