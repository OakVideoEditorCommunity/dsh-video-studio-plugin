# @oakvideoeditor/oak-deepseek-plugin

A [DeepSeek Harness](https://deepseek-harness.github.io/deepseek-harness/) video-editing plugin:
it connects to the [oak MCP](https://github.com/OakVideoEditorCommunity/example-mcp) server
(backed by the Quercus non-linear video-editing engine), lets the assistant edit video with the
`mcp__oak__*` tools, and plays exported cuts in the **Video Preview** panel in the GUI sidebar.

## Install

```bash
dsh plugin --profile desktop add @oakvideoeditor/oak-deepseek-plugin
# Restart DeepSeek Harness
```

Through `optionalDependencies`, the plugin automatically installs the MCP binary package for the
current platform (`@oakvideoeditor/oak-mcp-darwin-arm64` / `-linux-x64` / `-win32-x64`).
On first activation the host half copies it to:

- Windows: `%LOCALAPPDATA%\video-studio`
- Linux/macOS: `~/.local/share/video-studio`

You can also point the plugin at an existing `oak-mcp` executable with the
`VIDEO_STUDIO_MCP_BIN` environment variable.

The MCP server can also be installed from npm on its own:
`npx -y @oakvideoeditor/oak-mcp` (usable with any MCP client).

## Usage

After restarting, a film icon named **Video Preview** appears in the left sidebar, and 50
`mcp__oak__*` tools appear in the model's tool list. Ask the assistant to edit and export; the
finished video is written to `~/.dsh/video-studio/previews` and shows up in the panel, ready to
play.

## Platforms

- Windows x86_64 (Win10 1809+)
- Linux x86_64
- macOS arm64 (Apple Silicon)

## License

GPL-3.0-or-later. The `oak-mcp` binary is built from the GPL-3.0-or-later licensed example-mcp.
