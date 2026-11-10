# Video Studio — DeepSeek Harness 视频剪辑插件

把 [example-mcp](https://atomgit.com/oak-and-quercus/example-mcp)（[Quercus](https://github.com/OakVideoEditorCommunity/quercus-engine)
非线性剪辑引擎的 MCP 服务器）接进 [DeepSeek Harness](https://deepseek-harness.github.io/deepseek-harness/)：

- 助手获得 `mcp__oak__*` 共 **50 个**剪辑工具（建工程、导入素材、排片、裁剪、转场、特效、预览帧、导出、OTIO……）；
- GUI 左侧栏多一个 **「视频预览」** 面板，自动刷新并播放最新导出的成片（支持拖动进度、HTTP Range 流式读取、历史成片切换、预览帧 PNG）。

| 平台 | 分发包（Release 资产） |
|---|---|
| Windows x86_64 | `video-studio-windows-x86_64.zip` |
| Linux x86_64 | `video-studio-linux-x86_64.tar.gz` |

> macOS 用户可从源码构建（见 `cross-build/README.md` 与上游 example-mcp 的 macOS 构建说明）。

## 安装

### Windows x86_64

1. 下载 Release 里的 `video-studio-windows-x86_64.zip` 并解压；
2. PowerShell 执行：
   ```powershell
   cd video-studio-windows-x86_64
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```
3. **重启 DeepSeek Harness**。

安装脚本会把 `oak-mcp.exe` 和 26 个运行库 DLL 复制到 `%LOCALAPPDATA%\video-studio`，
并用 `dsh plugin --profile desktop add <plugin>` 注册插件。需要 `dsh` CLI 在 PATH 中；
否则用 `$env:DSH_CLI='C:\...\dsh.cmd'` 指定，`$env:DSH_PROFILE` 可覆盖 profile（默认 `desktop`）。

### Linux x86_64

1. 下载并解压 Release 里的 `video-studio-linux-x86_64.tar.gz`；
2. 执行：
   ```bash
   cd video-studio-linux-x86_64
   ./install.sh
   ```
3. **重启 DeepSeek Harness**。

安装脚本把二进制装到 `~/.local/share/video-studio`（启动包装脚本会自动设置
`LD_LIBRARY_PATH`），并注册插件。需要 `dsh` CLI 在 PATH 或 `DSH_CLI=/path/to/dsh`。

### 安装后

- 左侧栏出现胶片图标「视频预览」；
- 模型工具列表出现 `mcp__oak__*`（50 个）；
- 系统提示自动包含剪辑工作流约定（时间用秒、node id 取返回值、导出到预览目录）。

## 使用

在对话里直接描述剪辑需求，例如：

> 把 3 段素材按顺序剪成 10 秒，前两段之间加 0.5 秒交叉溶解，最后一段不透明度 85%，
> 导出 720p MP4 到预览目录。

助手会调用 `mcp__oak__*` 完成 `project_new → media_import → clip_place_linked →
transition_add / effect_add → preview_frame → export_start → task_wait`，
成片写入预览目录后，点「视频预览」即可播放。

- 预览目录：`~/.dsh/video-studio/previews`（Windows：`%USERPROFILE%\.dsh\video-studio\previews`）
- 自定义 MCP 路径：环境变量 `VIDEO_STUDIO_MCP_BIN`
- 面板每 2 秒刷新；新导出的 MP4/PNG 会自动出现在列表最前面

## 仓库结构

```
plugin/          DSH bundle 源码（Host + Client，无构建步骤）
cross-build/     交叉构建与插件打包脚本、模板、Windows/Linux 构建说明
```

- `plugin/index.js`：Host 半，提供 `/video-studio/state`、`/video-studio/media/*` 路由（Range 流式）与剪辑提示；
- `plugin/client.js`：Client 半，在 `sidebar.panellist` + `main` 槽位注册「视频预览」面板；
- `plugin/cordis.patch.yml`：插入 `@deepseek-ai/dsh-mcp-client`（stdio 启动 oak-mcp）与插件行；
  MCP 路径用 Loader `!!js` 表达式按平台解析，也可用 `VIDEO_STUDIO_MCP_BIN` 覆盖。

## 从源码构建和打包

见 [cross-build/README.md](cross-build/README.md)。要点：

- **Windows x86_64**：macOS/Linux 上 `cargo-xwin` + clang-cl/lld-link + BtbN FFmpeg 9 shared + conda-forge OCIO 2.5；
- **Linux x86_64**：Docker `--platform linux/amd64` 容器内构建，FFmpeg 9 从源码编译，OCIO 由 ocio-sys vendored 源码 CMake 构建；
- 插件分发包由 `cross-build/package-plugins.sh` 生成。

## 验证状态

| 项 | Windows x86_64 | Linux x86_64 |
|---|---|---|
| 构建 | ✅ MSVC 交叉 | ✅ Docker 容器 |
| `oak-mcp --check` | ✅ Wine 11.21（ok / 50 tools / render_manager） | ✅ 容器 |
| MCP stdio 握手 + tools/list | ✅ | ✅ |
| 真实剪辑导出 + ffprobe | ✅（3s H.264+AAC） | ✅ |
| 干净环境运行 | ✅ Wine | ✅ 干净 ubuntu:24.04 |
| DSH 插件安装/加载 | ⚠️ 未在真实 Windows 上联调 | ⚠️ 未在真实 Linux 桌面上联调 |

## 已知限制（上游 Quercus 引擎）

- `export_start(video+audio)` 只混入第一条音频片段的音频；变通：先 `render_audio` 导出整条 WAV，
  再把 WAV 作为音频素材铺到时间线后导出。
- 关键帧与部分特效在 `preview_frame` 可见，但不烘焙进导出文件。
- 并发负载下引擎进程可能静默退出；建议同一时刻只跑一个导出。

## License

- 本仓库的插件代码：**GPL-3.0-or-later**（见 [LICENSE](LICENSE)）。
- 分发包内附带的 `oak-mcp` 二进制由 [example-mcp](https://atomgit.com/oak-and-quercus/example-mcp)
  构建，同样为 **GPL-3.0-or-later**；对应源码见上游仓库。
