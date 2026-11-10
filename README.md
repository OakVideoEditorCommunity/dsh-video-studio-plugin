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

- Three jobs build `oak-mcp` natively on `ubuntu-24.04`, `windows-latest` and `macos-15`.
  Linux/macOS build FFmpeg 9 + OpenColorIO from source (static, Quercus bootstrap /
  `ocio-sys` bundled); Windows uses a pinned BtbN FFmpeg 9.0.2 GPL **shared** prebuilt
  (dynamic DLLs) plus static bundled OpenColorIO. CI caches the built/downloaded prefixes.
- Pushing a `v*` tag triggers build → GitHub Release + npm publish through
  [npm Trusted Publishing](https://docs.npmjs.com/trusted-publishers) (GitHub Actions OIDC,
  `id-token: write`; no `NPM_TOKEN` secret). Each of the five `@oakvideoeditor/*` packages
  must have a trusted publisher configured on npmjs.com: repository
  `OakVideoEditorCommunity/dsh-video-studio-plugin`, workflow `build.yml`, environment empty.
- `workflow_dispatch` only builds artifacts (no release/publish).

### Hardware codecs in release binaries

- Linux: pinned **BtbN FFmpeg 9.0.2 GPL shared** build (dynamic `.so` files,
  SHA256-pinned autobuild) → VAAPI, NVENC/NVDEC/CUDA, QSV and AMF. CI asserts
  `h264_vaapi`/`h264_nvenc`/`hevc_nvenc`/`h264_qsv`/`h264_amf` in `libavcodec.so`.
- Windows: pinned **BtbN FFmpeg 9.0.2 GPL shared** build (dynamic DLLs + MSVC import
  libraries, SHA256-pinned autobuild) → NVENC/NVDEC/CUDA, QSV (oneVPL), AMF and
  D3D11VA/DXVA2/MediaFoundation. CI asserts `h264_nvenc`/`hevc_nvenc`/`h264_qsv`/
  `h264_amf`/`h264_mf`/`d3d11va` in `avcodec-*.dll`.
- macOS: VideoToolbox (H.264/HEVC), always enabled by the FFmpeg bootstrap; verified in CI.
- Linux binaries are built on Ubuntu 24.04 (glibc 2.39 baseline) for modern distros
  (Debian 13, Fedora 43, Arch, ...), bundle libva/libdrm/libstdc++/... in `lib/`, and
  carry `$ORIGIN` rpath, so they run without system FFmpeg/VA-API dev packages.
- Note: the engine still opens its default software encoder for **export** (`libx264`),
  so hardware paths speed up decoding/preview (and proxy generation via an external
  `ffmpeg`); hardware-encoded export needs an engine change.

To reproduce locally see `cross-build/README.md` and the `ci/build-*.sh` scripts.

## Known limitations (upstream Quercus engine)

- `export_start(video+audio)` only mixes the audio of the first audio clip (workaround:
  `render_audio` to a WAV, lay it on the timeline, then export);
- keyframed parameters and some effects are visible in `preview_frame` but not baked into exports;
- the engine process may exit silently under concurrent load — run one export at a time.

## License

GPL-3.0-or-later (see [LICENSE](LICENSE)). The bundled `oak-mcp` binaries are built from the
GPL-3.0-or-later example-mcp project.
