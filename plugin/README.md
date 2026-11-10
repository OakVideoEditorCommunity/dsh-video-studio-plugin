# @oakvideoeditor/oak-deepseek-plugin

[DeepSeek Harness](https://deepseek-harness.github.io/deepseek-harness/) 视频剪辑插件：
接入 [oak MCP](https://github.com/OakVideoEditorCommunity/example-mcp)（Quercus 非线性剪辑引擎），
让助手用 `mcp__oak__*` 工具剪辑视频，并在 GUI 左侧栏「视频预览」面板播放成片。

## 安装

```bash
dsh plugin --profile desktop add @oakvideoeditor/oak-deepseek-plugin
# 重启 DeepSeek Harness
```

本包通过 `optionalDependencies` 自动安装当前平台的 MCP 二进制包
（`@oakvideoeditor/oak-deepseek-plugin-darwin-arm64` / `-linux-x64` / `-win32-x64`），
首次激活时由 Host 半自动复制到：

- Windows：`%LOCALAPPDATA%\video-studio`
- Linux/macOS：`~/.local/share/video-studio`

也可用环境变量 `VIDEO_STUDIO_MCP_BIN` 指定已有的 `oak-mcp` 可执行文件。

MCP 服务器也可单独从 npm 安装：`npx -y @oakvideoeditor/oak-mcp`（任意 MCP 客户端可用）。

## 使用

重启后左侧栏出现胶片图标「视频预览」，模型工具列表出现 `mcp__oak__*`（50 个）。
让助手剪辑并导出，成片写入 `~/.dsh/video-studio/previews` 后面板自动出现并可播放。

## 平台

- Windows x86_64（Win10 1809+）
- Linux x86_64
- macOS arm64（Apple Silicon）

## 许可

GPL-3.0-or-later。`oak-mcp` 二进制由 GPL-3.0-or-later 的 example-mcp 构建。
