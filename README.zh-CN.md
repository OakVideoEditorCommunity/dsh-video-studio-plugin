[English](README.md) | [简体中文](README.zh-CN.md)

# Oak DeepSeek Plugin — DeepSeek Harness 视频剪辑台

把 [Quercus](https://github.com/OakVideoEditorCommunity/quercus-engine) 非线性剪辑引擎的 MCP
服务器 `oak-mcp`（由 [example-mcp](https://github.com/OakVideoEditorCommunity/example-mcp) 构建）
接入 [DeepSeek Harness](https://deepseek-harness.github.io/deepseek-harness/)：助手通过
`mcp__oak__*` 工具剪辑视频，GUI 左侧栏的「视频预览」面板播放导出的成片。

## 平台支持

- Windows x86_64（Win10 1809+）
- Linux x86_64（glibc）
- macOS arm64（Apple Silicon）

每个平台提供两种交付：

1. **GitHub Release 安装包**（插件 + MCP 二进制 + 安装脚本）；
2. **npm 包**（`@oakvideoeditor/oak-deepseek-plugin` + 平台二进制包），安装插件后首次激活
   会自动就位 MCP 二进制。

## 安装

### npm（推荐）

```bash
dsh plugin --profile desktop add @oakvideoeditor/oak-deepseek-plugin
```

主包通过 `optionalDependencies` 自动安装当前平台的二进制包：

| 平台包 | 平台 |
|---|---|
| `@oakvideoeditor/oak-mcp-darwin-arm64` | macOS arm64 |
| `@oakvideoeditor/oak-mcp-linux-x64` | Linux x86_64 |
| `@oakvideoeditor/oak-mcp-win32-x64` | Windows x86_64 |

安装后**重启 DeepSeek Harness**：左侧栏出现胶片图标「视频预览」，模型工具列表出现
50 个 `mcp__oak__*` 工具。

### GitHub Release 安装包

到 [Releases](https://github.com/OakVideoEditorCommunity/dsh-video-studio-plugin/releases) 下载：

| 平台 | 文件 |
|---|---|
| Windows x86_64 | `video-studio-windows-x86_64.zip` |
| Linux x86_64 | `video-studio-linux-x86_64.tar.gz` |
| macOS arm64 | `video-studio-macos-arm64.tar.gz` |

解压后运行 `install.ps1`（Windows）或 `install.sh`（Linux/macOS），再重启 DeepSeek Harness。
纯 MCP 构建（接入其他 MCP 客户端）在同一 Release 的 `oak-mcp-<platform>` 资产里。

## MCP 客户端配置（mcp.json）

仓库根目录附带可直接使用的 [mcp.json](mcp.json)（任何读取 `mcpServers` 配置的 MCP 客户端通用）：

```json
{
  "mcpServers": {
    "oak": {
      "command": "npx",
      "args": ["-y", "@oakvideoeditor/oak-mcp"]
    }
  }
}
```

Claude Desktop：把上述内容合并到 `~/Library/Application Support/Claude/claude_desktop_config.json`
（Windows：`%APPDATA%\Claude\claude_desktop_config.json`）；Cursor / VS Code 等放到各自的
MCP 配置文件。首次运行 `npx` 会自动下载本平台的 `oak-mcp` 二进制。

如果已下载 GitHub Release 的纯 MCP 包，也可以直接指定可执行文件：

```json
{
  "mcpServers": {
    "oak": {
      "command": "/path/to/oak-mcp/bin/oak-mcp"
    }
  }
}
```

> 使用 DSH 插件时不需要 mcp.json：`@oakvideoeditor/oak-deepseek-plugin` 的 bundle patch 会自动注册
> `mcp__oak__*` 工具。

## 使用

在对话里描述剪辑需求，例如：

> 把 3 段素材按顺序剪成 10 秒，前两段之间加 0.5 秒交叉溶解，导出 720p MP4。

助手会调用 `mcp__oak__*` 完成 `project_new → media_import → clip_place_linked →
transition_add / effect_add → preview_frame → export_start → task_wait`，成片写入预览目录后
在「视频预览」面板播放。

- 预览目录：`~/.dsh/video-studio/previews`
- 自定义 MCP 路径：环境变量 `VIDEO_STUDIO_MCP_BIN`

## 仓库结构

```
plugin/          DSH bundle 源码（Host + Client，无构建步骤）
cross-build/     打包脚本（插件 / 纯 MCP / npm）与 macOS dylib 打包器
ci/              各平台 CI 构建脚本
.github/workflows/build.yml   三平台构建 + Release + npm 发布
mcp.json         可直接使用的 MCP 客户端配置
```

## 构建与发布（GitHub Actions）

- 三个 job 分别在 `ubuntu-24.04`、`windows-latest`、`macos-15` 原生构建 `oak-mcp`：
  Linux/macOS 由 quercus bootstrap / `ocio-sys` bundled 从源码静态构建 FFmpeg 9 与
  OpenColorIO；Windows 使用固定版本的 BtbN FFmpeg 9.0.2 GPL **shared** 预编译包
  （动态 DLL）+ 静态 bundled OpenColorIO。CI 会缓存构建/下载的前缀。
- 打 `v*` tag 触发构建 → GitHub Release + npm 发布，npm 发布走
  [Trusted Publishing](https://docs.npmjs.com/trusted-publishers)（GitHub Actions OIDC，
  `id-token: write`，不再需要 `NPM_TOKEN` secret）；npmjs.com 上需为 5 个
  `@oakvideoeditor/*` 包分别配置 trusted publisher：仓库
  `OakVideoEditorCommunity/dsh-video-studio-plugin`、workflow `build.yml`、环境留空；
- `workflow_dispatch` 只构建产物、不发布。

### 发布产物的硬件编解码

- Linux：Quercus bootstrap 源码构建，依赖直接来自上游 `tooling/install-deps.sh`
  （libva/libdrm/ffnvcodec 头文件）→ VAAPI + NVENC/NVDEC/CUDA；CI 用 `h264_vaapi`、
  `h264_nvenc`、`hevc_nvenc` 字符串和 `libva.so` 动态链接做校验；
- Windows：固定版本的 **BtbN FFmpeg 9.0.2 GPL shared** 构建（动态 DLL + MSVC 导入库，
  autobuild 资产带 SHA256 校验）→ NVENC/NVDEC/CUDA、QSV（oneVPL）、AMF 以及
  D3D11VA/DXVA2/MediaFoundation；CI 对 `avcodec-*.dll` 做字符串校验；
- macOS：VideoToolbox（H.264/HEVC），FFmpeg bootstrap 默认启用；CI 做字符串校验；
- 注意：引擎**导出**时仍打开默认软件编码器（`libx264`），硬件路径加速的是解码/预览
  （以及经由外部 `ffmpeg` 的代理生成）；硬件编码导出需要改引擎。

本地复现可参考 `cross-build/README.md` 与各 `ci/build-*.sh`。

## 已知限制（上游 Quercus 引擎）

- `export_start(video+audio)` 只混入第一条音频片段音频（用 `render_audio` + mux 变通）；
- 关键帧与部分特效在 `preview_frame` 可见，但不烘焙进导出；
- 并发负载下引擎可能静默退出，建议串行导出。

## License

GPL-3.0-or-later（见 [LICENSE](LICENSE)）。分发包内的 `oak-mcp` 二进制由 GPL-3.0-or-later 的
example-mcp 构建。
