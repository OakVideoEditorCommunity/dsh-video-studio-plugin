#!/usr/bin/env bash
# 打包纯 MCP 产物（不含 DSH 插件）：三平台 tar/zip。
#
# 用法：
#   ./cross-build/package-mcp.sh \
#     --linux-binary <bin> [--linux-libs <dir>] \
#     --windows-binary <exe> [--windows-dlls <dir>] \
#     --macos-binary <bin> [--macos-libs <dir>] \
#     --version 0.1.1
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIST="${DIST_DIR:-$ROOT/dist}"
LINUX_BIN=""; LINUX_LIBS=""
WINDOWS_BIN=""; WINDOWS_DLLS=""
MACOS_BIN=""; MACOS_LIBS=""
VERSION="0.1.1"

while [ $# -gt 0 ]; do
	case "$1" in
		--linux-binary) LINUX_BIN="$2"; shift 2 ;;
		--linux-libs) LINUX_LIBS="$2"; shift 2 ;;
		--windows-binary) WINDOWS_BIN="$2"; shift 2 ;;
		--windows-dlls) WINDOWS_DLLS="$2"; shift 2 ;;
		--macos-binary) MACOS_BIN="$2"; shift 2 ;;
		--macos-libs) MACOS_LIBS="$2"; shift 2 ;;
		--version) VERSION="$2"; shift 2 ;;
		-h|--help) sed -n '2,12p' "$0"; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

mkdir -p "$DIST"

readme() {
	cat > "$1" <<EOF
# oak-mcp ${VERSION} — $2

Quercus 非线性剪辑引擎的 MCP 服务器（stdio），由
[example-mcp](https://github.com/OakVideoEditorCommunity/example-mcp) 构建。

## 运行

\`\`\`
$3
\`\`\`

MCP 客户端配置（stdio）：command 指向上述可执行文件，args 为空。

## 依赖

$4

## License

GPL-3.0-or-later。
EOF
}

if [ -n "$LINUX_BIN" ]; then
	OUT="$DIST/oak-mcp-linux-x86_64"
	rm -rf "$OUT"; mkdir -p "$OUT/bin" "$OUT/lib"
	cp -a "$LINUX_BIN" "$OUT/bin/oak-mcp"; chmod +x "$OUT/bin/oak-mcp"
	[ -n "$LINUX_LIBS" ] && [ -d "$LINUX_LIBS" ] && cp -a "$LINUX_LIBS/." "$OUT/lib/"
	readme "$OUT/README.md" "Linux x86_64" "./bin/oak-mcp --check" "x86_64 Linux + glibc ≥ 2.39（Ubuntu 24.04 构建，现代发行版）；运行库在 lib/，二进制带 \$ORIGIN rpath。"
	tar -czf "$DIST/oak-mcp-linux-x86_64.tar.gz" -C "$DIST" oak-mcp-linux-x86_64
	echo "mcp package: $DIST/oak-mcp-linux-x86_64.tar.gz"
fi

if [ -n "$WINDOWS_BIN" ]; then
	OUT="$DIST/oak-mcp-windows-x86_64"
	rm -rf "$OUT"; mkdir -p "$OUT"
	cp -a "$WINDOWS_BIN" "$OUT/oak-mcp.exe"
	[ -n "$WINDOWS_DLLS" ] && [ -d "$WINDOWS_DLLS" ] && cp -a "$WINDOWS_DLLS/." "$OUT/"
	readme "$OUT/README.md" "Windows x86_64" "oak-mcp.exe --check" "Windows 10/11 x64；DLL 与 exe 同目录。"
	(cd "$DIST" && zip -qr -o "oak-mcp-windows-x86_64.zip" "oak-mcp-windows-x86_64")
	echo "mcp package: $DIST/oak-mcp-windows-x86_64.zip"
fi

if [ -n "$MACOS_BIN" ]; then
	OUT="$DIST/oak-mcp-macos-arm64"
	rm -rf "$OUT"; mkdir -p "$OUT/bin" "$OUT/lib"
	cp -a "$MACOS_BIN" "$OUT/bin/oak-mcp"; chmod +x "$OUT/bin/oak-mcp"
	[ -n "$MACOS_LIBS" ] && [ -d "$MACOS_LIBS" ] && cp -L "$MACOS_LIBS/." "$OUT/lib/" 2>/dev/null || true
	readme "$OUT/README.md" "macOS arm64" "DYLD_LIBRARY_PATH=./lib ./bin/oak-mcp --check" "Apple Silicon macOS；Homebrew 依赖已打包进 lib/ 并改写为 @executable_path。"
	tar -czf "$DIST/oak-mcp-macos-arm64.tar.gz" -C "$DIST" oak-mcp-macos-arm64
	echo "mcp package: $DIST/oak-mcp-macos-arm64.tar.gz"
fi

echo "==> done"
