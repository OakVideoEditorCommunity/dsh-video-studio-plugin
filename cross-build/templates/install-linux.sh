#!/usr/bin/env bash
# video-studio 插件安装脚本（Linux x86_64）
# 用法：./install.sh
# 可选环境变量：
#   DSH_CLI      显式指定 dsh CLI 路径
#   DSH_PROFILE  Harness profile 名（默认 desktop）
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/video-studio"
PROFILE="${DSH_PROFILE:-desktop}"

echo "==> 安装到 $DATA"
mkdir -p "$DATA/lib"
cp -a "$HERE/mcp/." "$DATA/"
chmod +x "$DATA/oak-mcp.bin" 2>/dev/null || chmod +x "$DATA/oak-mcp"

# 生成启动包装脚本（把 lib/ 加入 LD_LIBRARY_PATH；没有 lib/ 时也安全）
cat > "$DATA/oak-mcp" <<'WRAPPER'
#!/bin/sh
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -d "$DIR/lib" ]; then
  LD_LIBRARY_PATH="$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export LD_LIBRARY_PATH
fi
exec "$DIR/oak-mcp.bin" "$@"
WRAPPER
chmod +x "$DATA/oak-mcp"

rm -rf "$DATA/plugin"
cp -a "$HERE/plugin" "$DATA/plugin"

DSH_BIN="${DSH_CLI:-}"
if [ -z "$DSH_BIN" ]; then
  DSH_BIN=$(command -v dsh || true)
fi
if [ -z "$DSH_BIN" ] || [ ! -x "$DSH_BIN" ]; then
  cat >&2 <<'MSG'
未找到 dsh CLI。请设置 DSH_CLI 指向 dsh 可执行文件后重跑，例如：
  DSH_CLI="/path/to/dsh" ./install.sh
MSG
  exit 1
fi

echo "==> 注册插件到 profile: $PROFILE"
"$DSH_BIN" plugin --profile "$PROFILE" add "$DATA/plugin"

cat <<MSG

安装完成。请重启 DeepSeek Harness（或执行 dsh --profile $PROFILE ... 的宿主进程），
重启后左侧栏出现「视频预览」，模型工具列表出现 mcp__oak__* 共 50 个。

MCP 二进制：$DATA/oak-mcp
预览目录 ：$HOME/.dsh/video-studio/previews
MSG
