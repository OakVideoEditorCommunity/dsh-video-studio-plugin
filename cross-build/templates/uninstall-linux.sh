#!/usr/bin/env bash
# video-studio 插件卸载脚本（Linux x86_64）
set -euo pipefail

DATA="${XDG_DATA_HOME:-$HOME/.local/share}/video-studio"
PROFILE="${DSH_PROFILE:-desktop}"

DSH_BIN="${DSH_CLI:-}"
if [ -z "$DSH_BIN" ]; then
  DSH_BIN=$(command -v dsh || true)
fi
if [ -n "$DSH_BIN" ] && [ -x "$DSH_BIN" ]; then
  "$DSH_BIN" plugin --profile "$PROFILE" remove @local/video-studio || true
fi

rm -rf "$DATA"
echo "已移除 $DATA。重启 DeepSeek Harness 后插件消失（预览文件仍保留在 ~/.dsh/video-studio/previews）。"
