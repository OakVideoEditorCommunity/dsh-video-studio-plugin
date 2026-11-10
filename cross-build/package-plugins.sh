#!/usr/bin/env bash
# 打包 per-platform 的 video-studio DSH 插件分发包。
#
# 用法：
#   ./cross-build/package-plugins.sh \
#     --linux-binary  /path/to/oak-mcp-linux-x86_64 \
#     [--linux-libs   /path/to/linux-libs-dir] \
#     --windows-binary /path/to/oak-mcp.exe \
#     [--windows-dlls  /path/to/windows-dll-dir] \
#     [--linux-deps    "运行时依赖说明文本"] \
#     [--windows-deps  "运行时依赖说明文本"]
#
# 产物（workspace/dist/）：
#   video-studio-linux-x86_64/          + .tar.gz
#   video-studio-windows-x86_64/        + .zip
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIST="$ROOT/dist"
PLUGIN_SRC="$ROOT/video-studio-plugin"
TEMPLATES="$ROOT/cross-build/templates"
VARIANTS="$ROOT/cross-build/plugin-variants"

LINUX_BIN=""
LINUX_LIBS=""
WINDOWS_BIN=""
WINDOWS_DLLS=""
LINUX_DEPS=""
WINDOWS_DEPS=""

while [ $# -gt 0 ]; do
	case "$1" in
		--linux-binary) LINUX_BIN="$2"; shift 2 ;;
		--linux-libs) LINUX_LIBS="$2"; shift 2 ;;
		--windows-binary) WINDOWS_BIN="$2"; shift 2 ;;
		--windows-dlls) WINDOWS_DLLS="$2"; shift 2 ;;
		--linux-deps) LINUX_DEPS="$2"; shift 2 ;;
		--windows-deps) WINDOWS_DEPS="$2"; shift 2 ;;
		-h|--help) sed -n '2,20p' "$0"; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

render_readme() {
	local out="$1" platform="$2" binary="$3" deps_dir="$4" install_ext="$5" code_lang="$6"
	local install_cmd="$7" uninstall_cmd="$8" install_dir="$9" preview_dir="${10}" runtime_deps="${11}"
	VS_PLATFORM="$platform" VS_BINARY="$binary" VS_DEPS_LABEL="$deps_dir" VS_INSTALL_EXT="$install_ext" \
	VS_CODE_LANG="$code_lang" VS_INSTALL_CMD="$install_cmd" VS_UNINSTALL_CMD="$uninstall_cmd" \
	VS_INSTALL_DIR="$install_dir" VS_PREVIEW_DIR="$preview_dir" VS_RUNTIME_DEPS="$runtime_deps" \
	python3 "$TEMPLATES/render-readme.py" "$TEMPLATES/README-platform.md" "$out"
}

copy_plugin() {
	local dest="$1" variant="$2"
	rm -rf "$dest"
	mkdir -p "$dest/locale"
	cp -a "$PLUGIN_SRC/index.js" "$PLUGIN_SRC/client.js" "$PLUGIN_SRC/package.json" "$dest/"
	cp -a "$PLUGIN_SRC/icon.svg" "$dest/"
	cp -a "$PLUGIN_SRC/locale/." "$dest/locale/"
	cp -a "$VARIANTS/$variant/cordis.patch.yml" "$dest/cordis.patch.yml"
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
	copy_plugin "$OUT/plugin" generic
	cp -a "$TEMPLATES/install-linux.sh" "$OUT/install.sh"
	cp -a "$TEMPLATES/uninstall-linux.sh" "$OUT/uninstall.sh"
	chmod +x "$OUT/install.sh" "$OUT/uninstall.sh"
	[ -n "$LINUX_DEPS" ] || LINUX_DEPS="\`oak-mcp\` 已尽量静态链接 FFmpeg/OCIO；若 \`mcp/lib/\` 非空，安装后的启动脚本会自动把它加入 \`LD_LIBRARY_PATH\`。最低要求：x86_64 Linux + glibc（构建机发行版或更新的 glibc）。"
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
	copy_plugin "$OUT/plugin" generic
	cp -a "$TEMPLATES/install-windows.ps1" "$OUT/install.ps1"
	cp -a "$TEMPLATES/uninstall-windows.ps1" "$OUT/uninstall.ps1"
	[ -n "$WINDOWS_DEPS" ] || WINDOWS_DEPS="单文件 \`oak-mcp.exe\`；若 \`mcp/\` 下随附 DLL（FFmpeg/OpenColorIO/运行库），它们必须与 exe 放在同一目录（安装脚本会一起复制）。最低要求：Windows 10/11 x64。"
	render_readme "$OUT/README.md" "Windows x86_64" "oak-mcp.exe" "mcp/" ".ps1" "powershell" "powershell -ExecutionPolicy Bypass -File .\\install.ps1" "powershell -ExecutionPolicy Bypass -File .\\uninstall.ps1" "%LOCALAPPDATA%\\video-studio" "%USERPROFILE%\\.dsh\\video-studio\\previews" "$WINDOWS_DEPS"
	(cd "$DIST" && zip -qr -o "video-studio-windows-x86_64.zip" "video-studio-windows-x86_64")
	echo "windows package: $DIST/video-studio-windows-x86_64.zip"
fi

echo "==> done"
ls -lh "$DIST" | sed -n '1,20p'
