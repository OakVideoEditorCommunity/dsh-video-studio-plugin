#!/usr/bin/env bash
# 组装 npm 发布包：三个平台二进制包 + 主插件包。
#
# 用法：
#   ./cross-build/package-npm.sh \
#     --plugin-src <bundle dir> --version 0.1.1 --out <dir> \
#     --linux-binary <bin> [--linux-libs <dir>] \
#     --windows-binary <exe> [--windows-dlls <dir>] \
#     --macos-binary <bin> [--macos-libs <dir>]
#
# 产物（<out>/）：
#   oak-mcp-darwin-arm64/  oak-mcp-linux-x64/  oak-mcp-win32-x64/  oak-mcp/  oak-deepseek-plugin/
set -euo pipefail

PLUGIN_SRC=""
VERSION="0.1.1"
OUT=""
LINUX_BIN=""; LINUX_LIBS=""
WINDOWS_BIN=""; WINDOWS_DLLS=""
MACOS_BIN=""; MACOS_LIBS=""

while [ $# -gt 0 ]; do
	case "$1" in
		--plugin-src) PLUGIN_SRC="$2"; shift 2 ;;
		--version) VERSION="$2"; shift 2 ;;
		--out) OUT="$2"; shift 2 ;;
		--linux-binary) LINUX_BIN="$2"; shift 2 ;;
		--linux-libs) LINUX_LIBS="$2"; shift 2 ;;
		--windows-binary) WINDOWS_BIN="$2"; shift 2 ;;
		--windows-dlls) WINDOWS_DLLS="$2"; shift 2 ;;
		--macos-binary) MACOS_BIN="$2"; shift 2 ;;
		--macos-libs) MACOS_LIBS="$2"; shift 2 ;;
		-h|--help) sed -n '2,15p' "$0"; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

[ -n "$OUT" ] || { echo "--out is required" >&2; exit 2; }
[ -n "$PLUGIN_SRC" ] || { echo "--plugin-src is required" >&2; exit 2; }
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_LAUNCHER="${REPO_LAUNCHER:-$SCRIPT_DIR/oak-mcp-launcher.mjs}"
[ -f "$REPO_LAUNCHER" ] || { echo "launcher missing: $REPO_LAUNCHER" >&2; exit 1; }
rm -rf "$OUT"
mkdir -p "$OUT"

platform_pkg() {
	local dir="$1" name="$2" os="$3" cpu="$4" desc="$5"
	mkdir -p "$dir/bin"
	cat > "$dir/package.json" <<EOF
{
  "name": "${name}",
  "version": "${VERSION}",
  "description": "${desc}",
  "license": "GPL-3.0-or-later",
  "repository": {
    "type": "git",
    "url": "git+https://github.com/OakVideoEditorCommunity/dsh-video-studio-plugin.git"
  },
  "os": ["${os}"],
  "cpu": ["${cpu}"],
  "files": ["bin", "lib", "README.md"]
}
EOF
	cat > "$dir/README.md" <<EOF
# ${name}

oak-mcp ${VERSION}（Quercus 引擎的 MCP 服务器）— ${desc}。

本包由 \`@oakvideoeditor/oak-deepseek-plugin\` 作为 optionalDependency 安装，
其 Host 半会把二进制复制到用户目录后启动 MCP。独立使用时：\`bin/oak-mcp --check\`。

License: GPL-3.0-or-later。
EOF
}

# ---- darwin arm64 ----
if [ -n "$MACOS_BIN" ]; then
	D="$OUT/oak-mcp-darwin-arm64"
	platform_pkg "$D" "@oakvideoeditor/oak-mcp-darwin-arm64" darwin arm64 "macOS arm64 binary"
	cp -a "$MACOS_BIN" "$D/bin/oak-mcp"; chmod +x "$D/bin/oak-mcp"
	if [ -n "$MACOS_LIBS" ] && [ -d "$MACOS_LIBS" ]; then
		mkdir -p "$D/lib"; cp -RL "$MACOS_LIBS/." "$D/lib/" 2>/dev/null || true
	fi
fi

# ---- linux x64 ----
if [ -n "$LINUX_BIN" ]; then
	D="$OUT/oak-mcp-linux-x64"
	platform_pkg "$D" "@oakvideoeditor/oak-mcp-linux-x64" linux x64 "Linux x86_64 binary"
	cp -a "$LINUX_BIN" "$D/bin/oak-mcp"; chmod +x "$D/bin/oak-mcp"
	if [ -n "$LINUX_LIBS" ] && [ -d "$LINUX_LIBS" ]; then
		mkdir -p "$D/lib"; cp -a "$LINUX_LIBS/." "$D/lib/"
	fi
fi

# ---- win32 x64 ----
if [ -n "$WINDOWS_BIN" ]; then
	D="$OUT/oak-mcp-win32-x64"
	platform_pkg "$D" "@oakvideoeditor/oak-mcp-win32-x64" win32 x64 "Windows x86_64 binary"
	cp -a "$WINDOWS_BIN" "$D/bin/oak-mcp.exe"
	if [ -n "$WINDOWS_DLLS" ] && [ -d "$WINDOWS_DLLS" ]; then
		cp -a "$WINDOWS_DLLS/." "$D/bin/"
	fi
fi

# ---- main plugin ----
D="$OUT/oak-deepseek-plugin"
cp -a "$PLUGIN_SRC/." "$D/"
rm -rf "$D/node_modules" "$D/bin" 2>/dev/null || true
node - "$D/package.json" "$VERSION" <<'EOF'
const fs = require('node:fs')
const [file, version] = process.argv.slice(2)
const pkg = JSON.parse(fs.readFileSync(file, 'utf8'))
pkg.version = version
if (pkg.optionalDependencies) {
	for (const key of Object.keys(pkg.optionalDependencies)) pkg.optionalDependencies[key] = version
}
fs.writeFileSync(file, `${JSON.stringify(pkg, null, 2)}\n`)
EOF

# ---- oak-mcp launcher package (works with any MCP client) ----
D="$OUT/oak-mcp"
mkdir -p "$D/bin"
cp "$REPO_LAUNCHER" "$D/bin/oak-mcp.mjs"
chmod +x "$D/bin/oak-mcp.mjs"
cat > "$D/package.json" <<EOF
{
  "name": "@oakvideoeditor/oak-mcp",
  "version": "${VERSION}",
  "description": "MCP server for the Quercus non-linear video-editing engine (oak-mcp)",
  "license": "GPL-3.0-or-later",
  "repository": {
    "type": "git",
    "url": "git+https://github.com/OakVideoEditorCommunity/dsh-video-studio-plugin.git"
  },
  "type": "module",
  "bin": { "oak-mcp": "bin/oak-mcp.mjs" },
  "files": ["bin", "README.md"],
  "optionalDependencies": {
    "@oakvideoeditor/oak-mcp-darwin-arm64": "${VERSION}",
    "@oakvideoeditor/oak-mcp-linux-x64": "${VERSION}",
    "@oakvideoeditor/oak-mcp-win32-x64": "${VERSION}"
  },
  "engines": { "node": ">=20.3.0" }
}
EOF
cat > "$D/README.md" <<'README_EOF'
# @oakvideoeditor/oak-mcp

Quercus 非线性剪辑引擎的 MCP 服务器（stdio）。npx 直接运行：

```json
{
  "mcpServers": {
    "oak": { "command": "npx", "args": ["-y", "@oakvideoeditor/oak-mcp"] }
  }
}
```

本包按平台安装 `@oakvideoeditor/oak-mcp-*` 二进制包并 exec。CLI：`oak-mcp --check`。

License: GPL-3.0-or-later。
README_EOF

echo "==> npm packages assembled in $OUT"
ls -1 "$OUT"
