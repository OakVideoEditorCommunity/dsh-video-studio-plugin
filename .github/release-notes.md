# v0.1.1 — DeepSeek Harness 视频剪辑插件（Windows / Linux / macOS arm64）

把 [Quercus](https://github.com/OakVideoEditorCommunity/quercus-engine)
剪辑引擎的 MCP 服务器 `oak-mcp` 接入
[DeepSeek Harness](https://deepseek-harness.github.io/deepseek-harness/)，
提供 `mcp__oak__*` 工具与 GUI 侧栏「视频预览」面板。

## 变更（0.1.1）

- npm 发布改用 **Trusted Publishing**（GitHub Actions OIDC，`id-token: write`），
  不再依赖 `NPM_TOKEN` secret，npm 包自动附带 provenance 证明；
- 版本号升至 `0.1.1`，npm 发布包补充 `repository` 元数据。

## 下载

| 资产 | 平台 | 说明 |
|---|---|---|
| `video-studio-windows-x86_64.zip` | Windows x86_64 | 插件 + MCP + DLL + 安装脚本 |
| `video-studio-linux-x86_64.tar.gz` | Linux x86_64 | 插件 + MCP + 运行库 + 安装脚本 |
| `video-studio-macos-arm64.tar.gz` | macOS arm64 | 插件 + MCP + 已打包 dylib + 安装脚本 |
| `oak-mcp-windows-x86_64.zip` | Windows x86_64 | 纯 MCP 服务器（接入其他 MCP 客户端） |
| `oak-mcp-linux-x86_64.tar.gz` | Linux x86_64 | 纯 MCP 服务器 |
| `oak-mcp-macos-arm64.tar.gz` | macOS arm64 | 纯 MCP 服务器 |

## npm

主插件包：`@oakvideoeditor/oak-deepseek-plugin`
MCP 服务包：`@oakvideoeditor/oak-mcp`（`npx -y @oakvideoeditor/oak-mcp`，任意 MCP 客户端可用）
平台二进制包：`@oakvideoeditor/oak-mcp-{darwin-arm64,linux-x64,win32-x64}`

```bash
dsh plugin --profile desktop add @oakvideoeditor/oak-deepseek-plugin
```

## 功能

- 50 个剪辑工具：建工程、导入素材、排片、裁剪/拆分、转场、特效、预览帧、异步导出、
  OTIO、撤销/重做等；
- GUI「视频预览」面板：自动刷新最新成片、`<video>` 播放与拖动进度（HTTP Range）、
  历史成片切换、预览帧 PNG；
- 系统提示自动注入剪辑工作流约定与预览目录。

## 验证

- Linux：Docker / CI 原生构建，`--check`（50 tools、render_manager）与真实导出通过；
  干净 ubuntu:24.04 复测通过。
- Windows：MSVC 构建，Wine 下 `--check` + MCP 握手 + 3s H.264/AAC 导出通过。
- macOS arm64：Homebrew FFmpeg/OCIO 构建，dylib 打包后 `--check` 通过。
- 插件 Host/Client 与媒体 Range 路由均实测。

## 已知限制（上游引擎）

- `export_start(video+audio)` 只混入第一条音频片段音频（用 `render_audio` + mux 变通）；
- 关键帧/部分特效不烘焙进导出；
- 并发负载下引擎可能静默退出，建议串行导出。

## License

GPL-3.0-or-later。
