[English](README.md) | [简体中文](README.zh-CN.md)

# Oak DeepSeek Plugin — Video Studio for DeepSeek Harness

Connects the [Quercus](https://github.com/OakVideoEditorCommunity/quercus-engine) non-linear
video-editing engine's MCP server `oak-mcp` (built from
[example-mcp](https://github.com/OakVideoEditorCommunity/example-mcp)) to
[DeepSeek Harness](https://deepseek-harness.github.io/deepseek-harness/): the agent edits video
through `mcp__oak__*` tools, and a **Video Preview** panel in the GUI sidebar plays the exported cuts.

## Platforms

- Windows x86_64 (Win10 1809+)
- Linux x86_64 (glibc)
- macOS arm64 (Apple Silicon)

Each platform ships in two forms:

1. **GitHub Release installer** (plugin + MCP binary + install scripts);
2. **npm packages** (`@oakvideoeditor/oak-deepseek-plugin` + platform binary packages). Installing
   the plugin also provisions the MCP binary on first activation.

## Install

### npm (recommended)

```bash
dsh plugin --profile desktop add @oakvideoeditor/oak-deepseek-plugin
```

The plugin installs the matching platform binary through `optionalDependencies`:

| Package | Platform |
|---|---|
| `@oakvideoeditor/oak-mcp-darwin-arm64` | macOS arm64 |
| `@oakvideoeditor/oak-mcp-linux-x64` | Linux x86_64 |
| `@oakvideoeditor/oak-mcp-win32-x64` | Windows x86_64 |

Restart DeepSeek Harness afterwards: a film icon **Video Preview** appears in the left sidebar and
the model gets 50 `mcp__oak__*` tools.

### GitHub Release installers

Download from [Releases](https://github.com/OakVideoEditorCommunity/dsh-video-studio-plugin/releases):

| Platform | Asset |
|---|---|
| Windows x86_64 | `video-studio-windows-x86_64.zip` |
| Linux x86_64 | `video-studio-linux-x86_64.tar.gz` |
| macOS arm64 | `video-studio-macos-arm64.tar.gz` |

Extract and run `install.ps1` (Windows) or `install.sh` (Linux/macOS), then restart DeepSeek Harness.
Pure-MCP builds are available as `oak-mcp-<platform>` assets for other MCP clients.

## MCP client configuration (mcp.json)

The repository ships a ready-to-use [mcp.json](mcp.json) (works with any client that reads
`mcpServers`):

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

Claude Desktop: merge it into `~/Library/Application Support/Claude/claude_desktop_config.json`
(Windows: `%APPDATA%\Claude\claude_desktop_config.json`); Cursor/VS Code: put it in their MCP
settings. `npx` downloads the platform binary on first run.

If you already have a pure-MCP release archive, point the client at the executable directly:

```json
{
  "mcpServers": {
    "oak": {
      "command": "/path/to/oak-mcp/bin/oak-mcp"
    }
  }
}
```

> The DSH plugin does not need mcp.json: its bundle patch registers `mcp__oak__*` automatically.

## Use

Describe the edit in the chat, for example:

> Cut the 3 clips into a 10-second sequence with a 0.5 s cross-dissolve between the first two,
> then export a 720p MP4.

The agent calls `mcp__oak__*`: `project_new → media_import → clip_place_linked →
transition_add / effect_add → preview_frame → export_start → task_wait`, and the exported cut shows
up in the **Video Preview** panel.

- Preview folder: `~/.dsh/video-studio/previews`
- Custom MCP binary: environment variable `VIDEO_STUDIO_MCP_BIN`

## Repository layout

```
plugin/          DSH bundle source (Host + Client, no build step)
cross-build/     packagers (plugin / pure MCP / npm) and macOS dylib bundler
ci/              per-platform CI build scripts
.github/workflows/build.yml   three-platform build + Release + npm publish
mcp.json         ready-to-use MCP client configuration
```

## Build & release (GitHub Actions)

- Three jobs build `oak-mcp` natively on `ubuntu-24.04`, `windows-latest` and `macos-15`:
  Linux builds FFmpeg 9 from source; Windows uses BtbN FFmpeg 9 shared; macOS uses Homebrew
  ffmpeg and bundles its dylibs into `lib/`. On every platform OpenColorIO is built from source
  by the `ocio-sys` bundled feature (static), not from conda/Homebrew.
- Pushing a `v*` tag triggers build → GitHub Release + npm publish (repository secret `NPM_TOKEN`).
- `workflow_dispatch` only builds artifacts (no release/publish).

To reproduce locally see `cross-build/README.md` and the `ci/build-*.sh` scripts.

## Known limitations (upstream Quercus engine)

- `export_start(video+audio)` only mixes the audio of the first audio clip (workaround:
  `render_audio` to a WAV, lay it on the timeline, then export);
- keyframed parameters and some effects are visible in `preview_frame` but not baked into exports;
- the engine process may exit silently under concurrent load — run one export at a time.

## License

GPL-3.0-or-later (see [LICENSE](LICENSE)). The bundled `oak-mcp` binaries are built from the
GPL-3.0-or-later example-mcp project.
