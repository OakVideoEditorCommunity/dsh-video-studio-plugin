# Video Studio（视频剪辑台）— {{PLATFORM}} 分发包

把 [example-mcp](https://atomgit.com/oak-and-quercus/example-mcp)（Quercus 引擎的 MCP
服务器）接入 DeepSeek Harness：助手用 `mcp__oak__*` 工具剪辑视频，GUI 侧栏的
「视频预览」面板自动播放最新成片。

## 包含内容

| 文件 | 说明 |
|---|---|
| `mcp/{{BINARY}}` | oak-mcp MCP 服务器二进制（{{PLATFORM}}） |
| `{{DEPS_LABEL}}` | 运行依赖库（随附 DLL/.so，如有） |
| `plugin/` | DSH bundle 包（`@local/video-studio`，含 MCP 连接配置与预览面板） |
| `install{{INSTALL_EXT}}` | 一键安装脚本 |
| `uninstall{{INSTALL_EXT}}` | 卸载脚本 |

## 安装

```{{CODE_LANG}}
{{INSTALL_CMD}}
```

脚本会做两件事：

1. 把 `oak-mcp` 与运行库安装到 `{{INSTALL_DIR}}`；
2. 用 `dsh plugin --profile <profile> add <plugin>` 把 bundle 注册进 Harness。

**然后重启 DeepSeek Harness**，左侧栏出现胶片图标「视频预览」，模型工具列表出现
`mcp__oak__*` 共 50 个。

> 需要 dsh CLI 在 PATH 中；否则用 `DSH_CLI=/path/to/dsh`（Windows：`$env:DSH_CLI='...'`）指定。
> 无法使用 CLI 时，也可以把 `plugin/` 目录交给 DSH 的插件安装流程（与普通本地 bundle 相同）。

## 使用

在对话里直接说，例如：

> 把 3 段素材按顺序剪成 10 秒，前两段之间加 0.5 秒交叉溶解，导出 720p MP4。

助手会调用 `mcp__oak__*` 完成剪辑与导出，成片写到预览目录后，点侧栏「视频预览」
即可播放（支持进度拖动，HTTP Range 流式读取）。

- 预览目录：`{{PREVIEW_DIR}}`
- 自定义 MCP 路径：设置环境变量 `VIDEO_STUDIO_MCP_BIN` 后重启 Harness。

## 运行依赖

{{RUNTIME_DEPS}}

## 已知限制（来自上游 Quercus 引擎）

- `export_start(video+audio)` 只混入第一条音频片段的音频；变通：先 `render_audio`
  导出整条时间线 WAV，再把 WAV 作为音频素材铺到时间线后导出。
- 关键帧参数与部分特效只在 `preview_frame` 生效，不烘焙进导出文件。
- 并发负载下引擎进程可能静默退出，建议同一时刻只跑一个导出。

## 卸载

```{{CODE_LANG}}
{{UNINSTALL_CMD}}
```
