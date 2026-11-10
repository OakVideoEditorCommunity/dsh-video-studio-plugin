"""渲染分发包 README 模板；所有替换值来自 VS_* 环境变量，避免 shell 转义问题。"""
import os
import sys

template = open(sys.argv[1], encoding="utf-8").read()
env = os.environ
values = {
    "{{PLATFORM}}": env["VS_PLATFORM"],
    "{{BINARY}}": env["VS_BINARY"],
    "{{DEPS_LABEL}}": env["VS_DEPS_LABEL"],
    "{{INSTALL_EXT}}": env["VS_INSTALL_EXT"],
    "{{CODE_LANG}}": env["VS_CODE_LANG"],
    "{{INSTALL_CMD}}": env["VS_INSTALL_CMD"],
    "{{UNINSTALL_CMD}}": env["VS_UNINSTALL_CMD"],
    "{{INSTALL_DIR}}": env["VS_INSTALL_DIR"],
    "{{PREVIEW_DIR}}": env["VS_PREVIEW_DIR"],
    "{{RUNTIME_DEPS}}": env["VS_RUNTIME_DEPS"],
}
for key, value in values.items():
    template = template.replace(key, value)
open(sys.argv[2], "w", encoding="utf-8").write(template)
