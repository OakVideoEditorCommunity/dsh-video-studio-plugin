#!/usr/bin/env bash
# 打包 per-platform 的 video-studio DSH 插件分发包（Windows / Linux / macOS）。
#
# 用法：
#   ./cross-build/package-plugins.sh \
#     --plugin-src    <bundle dir>            # 例如 repo 的 plugin/ 或 publish/plugin
#     --linux-binary  <path> [--linux-libs <dir>] \
#     --windows-binary <path> [--windows-dlls <dir>] \
#     --macos-binary  <path> [--macos-libs  <dir>] \
#     --version       0.1.1
#
# 产物（$DIST，默认 <repo>/dist）：
#   video-studio-linux-x86_64/    + .tar.gz
#   video-studio-windows-x86_64/  + .zip
#   video-studio-macos-arm64/     + .tar.gz
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIST="${DIST_DIR:-$ROOT/dist}"
TEMPLATES="$ROOT/cross-build/templates"

PLUGIN_SRC=""
LINUX_BIN=""
LINUX_LIBS=""
WINDOWS_BIN=""
WINDOWS_DLLS=""
MACOS_BIN=""
MACOS_LIBS=""
VERSION="0.1.1"
LINUX_DEPS=""
WINDOWS_DEPS=""
MACOS_DEPS=""

while [ $# -gt 0 ]; do
	case "$1" in
		--plugin-src) PLUGIN_SRC="$2"; shift 2 ;;
		--linux-binary) LINUX_BIN="$2"; shift 2 ;;
		--linux-libs) LINUX_LIBS="$2"; shift 2 ;;
		--windows-binary) WINDOWS_BIN="$2"; shift 2 ;;
		--windows-dlls) WINDOWS_DLLS="$2"; shift 2 ;;
		--macos-binary) MACOS_BIN="$2"; shift 2 ;;
		--macos-libs) MACOS_LIBS="$2"; shift 2 ;;
		--version) VERSION="$2"; shift 2 ;;
		--linux-deps) LINUX_DEPS="$2"; shift 2 ;;
		--windows-deps) WINDOWS_DEPS="$2"; shift 2 ;;
		--macos-deps) MACOS_DEPS="$2"; shift 2 ;;
		-h|--help) sed -n '2,20p' "$0"; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

if [ -z "$PLUGIN_SRC" ] || [ ! -f "$PLUGIN_SRC/package.json" ]; then
	echo "--plugin-src must point at a bundle directory with package.json" >&2
	exit 2
fi

render_readme() {
	local out="$1" platform="$2" binary="$3" deps_label="$4" install_ext="$5" code_lang="$6"
	local install_cmd="$7" uninstall_cmd="$8" install_dir="$9" preview_dir="${10}" runtime_deps="${11}"
	VS_PLATFORM="$platform" VS_BINARY="$binary" VS_DEPS_LABEL="$deps_label" VS_INSTALL_EXT="$install_ext" \
	VS_CODE_LANG="$code_lang" VS_INSTALL_CMD="$install_cmd" VS_UNINSTALL_CMD="$uninstall_cmd" \
	VS_INSTALL_DIR="$install_dir" VS_PREVIEW_DIR="$preview_dir" VS_RUNTIME_DEPS="$runtime_deps" \
	python3 "$TEMPLATES/render-readme.py" "$TEMPLATES/README-platform.md" "$out"
}

copy_plugin() {
	local dest="$1"
	rm -rf "$dest"
	cp -a "$PLUGIN_SRC" "$dest"
	# 安装包里的插件不需要 node_modules 之类残留；保留源码/资源即可
	rm -rf "$dest/node_modules" "$dest/bin" 2>/dev/null || true
}

mkdir -p "$DIST"

# ---------- Linux ----------
if [ -n "$LINUX_BIN" ]; then
	[ -f "$LINUX_BIN" ] || { echo "linux binary not found: $LINUX_BIN" >&2; exit 1; }
	OUT="$DIST/video-studio-linux-x86_64"
	rm -rf "$OUT"
	mkdir -p "$OUT/mcp/lib"
	cp -a "$LINUX_BIN" "$OUT/mcp/oak-mcp.bin"
	chmod +x "$OUT/mcp/oak-mcp.bin"
	if [ -n "$LINUX_LIBS" ] && [ -d "$LINUX_LIBS" ]; then
		cp -a "$LINUX_LIBS/." "$OUT/mcp/lib/"
	fi
	copy_plugin "$OUT/plugin"
	cp -a "$TEMPLATES/install-linux.sh" "$OUT/install.sh"
	cp -a "$TEMPLATES/uninstall-linux.sh" "$OUT/uninstall.sh"
	chmod +x "$OUT/install.sh" "$OUT/uninstall.sh"
	[ -n "$LINUX_DEPS" ] || LINUX_DEPS="\`oak-mcp\` 为 x86_64 Linux ELF（PIE），在 Ubuntu 24.04 上构建（glibc ≥ 2.39，现代发行版）；随附 \`mcp/lib/\` 运行库（libva/libstdc++ 等），二进制带 \`\$ORIGIN\` rpath，安装后的启动脚本另设 \`LD_LIBRARY_PATH\`。"
	render_readme "$OUT/README.md" "Linux x86_64" "oak-mcp.bin" "mcp/lib/" ".sh" "bash" "./install.sh" "./uninstall.sh" "\$HOME/.local/share/video-studio" "\$HOME/.dsh/video-studio/previews" "$LINUX_DEPS"
	tar -czf "$DIST/video-studio-linux-x86_64.tar.gz" -C "$DIST" video-studio-linux-x86_64
	echo "linux package: $DIST/video-studio-linux-x86_64.tar.gz"
fi

# ---------- Windows ----------
if [ -n "$WINDOWS_BIN" ]; then
	[ -f "$WINDOWS_BIN" ] || { echo "windows binary not found: $WINDOWS_BIN" >&2; exit 1; }
	OUT="$DIST/video-studio-windows-x86_64"
	rm -rf "$OUT"
	mkdir -p "$OUT/mcp"
	cp -a "$WINDOWS_BIN" "$OUT/mcp/oak-mcp.exe"
	if [ -n "$WINDOWS_DLLS" ] && [ -d "$WINDOWS_DLLS" ]; then
		cp -a "$WINDOWS_DLLS/." "$OUT/mcp/"
	fi
	copy_plugin "$OUT/plugin"
	cp -a "$TEMPLATES/install-windows.ps1" "$OUT/install.ps1"
	cp -a "$TEMPLATES/uninstall-windows.ps1" "$OUT/uninstall.ps1"
	[ -n "$WINDOWS_DEPS" ] || WINDOWS_DEPS="\`oak-mcp.exe\` 与随附 DLL（FFmpeg / OpenColorIO / MSVC 运行库）必须放在同一目录；安装脚本会一起复制到 \`%LOCALAPPDATA%\\video-studio\`。最低要求：Windows 10/11 x64。"
	render_readme "$OUT/README.md" "Windows x86_64" "oak-mcp.exe" "mcp/" ".ps1" "powershell" "powershell -ExecutionPolicy Bypass -File .\\install.ps1" "powershell -ExecutionPolicy Bypass -File .\\uninstall.ps1" "%LOCALAPPDATA%\\video-studio" "%USERPROFILE%\\.dsh\\video-studio\\previews" "$WINDOWS_DEPS"
	(cd "$DIST" && zip -qr -o "video-studio-windows-x86_64.zip" "video-studio-windows-x86_64")
	echo "windows package: $DIST/video-studio-windows-x86_64.zip"
fi

# ---------- macOS ----------
if [ -n "$MACOS_BIN" ]; then
	[ -f "$MACOS_BIN" ] || { echo "macos binary not found: $MACOS_BIN" >&2; exit 1; }
	OUT="$DIST/video-studio-macos-arm64"
	rm -rf "$OUT"
	mkdir -p "$OUT/mcp/lib"
	cp -a "$MACOS_BIN" "$OUT/mcp/oak-mcp.bin"
	chmod +x "$OUT/mcp/oak-mcp.bin"
	if [ -n "$MACOS_LIBS" ] && [ -d "$MACOS_LIBS" ]; then
		cp -RL "$MACOS_LIBS/." "$OUT/mcp/lib/" 2>/dev/null || true
	fi
	copy_plugin "$OUT/plugin"
	cp -a "$TEMPLATES/install-linux.sh" "$OUT/install.sh"
	cp -a "$TEMPLATES/uninstall-linux.sh" "$OUT/uninstall.sh"
	chmod +x "$OUT/install.sh" "$OUT/uninstall.sh"
	[ -n "$MACOS_DEPS" ] || MACOS_DEPS="Apple Silicon（arm64）macOS。\`mcp/lib/\` 内已打包 Homebrew 依赖（FFmpeg/OpenColorIO 等）并改写为 \`@executable_path\`，启动脚本设置 \`DYLD_LIBRARY_PATH\`。二进制为 ad-hoc 签名；如被 Gatekeeper 隔离，执行 \`xattr -dr com.apple.quarantine <目录>\`。"
	render_readme "$OUT/README.md" "macOS arm64" "oak-mcp.bin" "mcp/lib/" ".sh" "bash" "./install.sh" "./uninstall.sh" "\$HOME/.local/share/video-studio" "\$HOME/.dsh/video-studio/previews" "$MACOS_DEPS"
	tar -czf "$DIST/video-studio-macos-arm64.tar.gz" -C "$DIST" video-studio-macos-arm64
	echo "macos package: $DIST/video-studio-macos-arm64.tar.gz"
fi

echo "==> done"
ls -lh "$DIST" | sed -n '1,20p'
