#!/usr/bin/env python3
"""Bundle Homebrew dylibs into a macOS binary's lib/ and rewrite install names.

Usage: bundle-macos-dylibs.py <binary> <out-dir>

Creates <out-dir>/bin/<name> and <out-dir>/lib/*.dylib; rewrites references to
@executable_path/../lib or @loader_path so the folder is relocatable. Ad-hoc
re-signs every modified Mach-O (required on arm64).
"""
import hashlib
import os
import shutil
import subprocess
import sys

SYSTEM_PREFIXES = ("/System/", "/usr/lib/", "/Library/Apple/")


def run(*args):
    return subprocess.run(args, capture_output=True, text=True)


def otool_deps(path):
    out = run("otool", "-L", path).stdout
    deps = []
    for line in out.splitlines()[1:]:
        line = line.strip()
        if not line:
            continue
        deps.append(line.split(" (")[0].strip())
    return deps


def is_system(path):
    return path.startswith(SYSTEM_PREFIXES)


def main():
    if len(sys.argv) != 3:
        print("usage: bundle-macos-dylibs.py <binary> <out-dir>", file=sys.stderr)
        return 2
    binary = os.path.abspath(sys.argv[1])
    out = os.path.abspath(sys.argv[2])
    if not os.path.isfile(binary):
        print(f"binary not found: {binary}", file=sys.stderr)
        return 1

    bin_name = os.path.basename(binary)
    out_bin = os.path.join(out, "bin", bin_name)
    out_lib = os.path.join(out, "lib")
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(os.path.join(out, "bin"))
    os.makedirs(out_lib)
    shutil.copy2(binary, out_bin)
    os.chmod(out_bin, 0o755)

    # ---- collect closure ---------------------------------------------------
    queue = [binary]
    seen = set()
    copy_source = {}   # bundled basename -> realpath
    orig_names = {}    # bundled basename -> set(original reference path)
    order = []
    while queue:
        current = queue.pop(0)
        real = os.path.realpath(current)
        if real in seen:
            continue
        seen.add(real)
        for dep in otool_deps(current):
            if is_system(dep) or dep.startswith("@"):
                continue
            if not os.path.exists(dep):
                print(f"warning: missing dependency {dep} (from {current})", file=sys.stderr)
                continue
            dep_real = os.path.realpath(dep)
            base = os.path.basename(dep_real)
            if base in copy_source and copy_source[base] != dep_real:
                digest = hashlib.sha256(dep_real.encode()).hexdigest()[:8]
                base = f"{digest}-{base}"
            copy_source[base] = dep_real
            orig_names.setdefault(base, set()).add(dep)
            if dep_real not in seen:
                queue.append(dep_real)
        if current == binary:
            # re-register the binary's direct deps verbatim (they may differ from
            # the canonical path recorded through another dylib)
            for dep in otool_deps(binary):
                if is_system(dep) or dep.startswith("@"):
                    continue
                if not os.path.exists(dep):
                    continue
                dep_real = os.path.realpath(dep)
                base = os.path.basename(dep_real)
                if base in copy_source:
                    orig_names[base].add(dep)
    for real in seen:
        if real != os.path.realpath(binary):
            order.append(real)

    mapping = {}  # original reference path -> in-package relative path
    for base, real in copy_source.items():
        dest = os.path.join(out_lib, base)
        shutil.copy2(real, dest)
        os.chmod(dest, 0o755)
        for orig in orig_names.get(base, ()):
            mapping[orig] = f"lib/{base}"

    # ---- rewrite install names --------------------------------------------
    def rewrite(target, kind):
        current_refs = set(otool_deps(target))
        args = []
        for orig, rel in mapping.items():
            if orig not in current_refs:
                continue
            if kind == "exe":
                args += ["-change", orig, f"@executable_path/../{rel}"]
            else:
                args += ["-change", orig, f"@loader_path/{os.path.basename(rel)}"]
        if args:
            result = run("install_name_tool", *args, target)
            if result.returncode != 0:
                raise RuntimeError(f"install_name_tool failed for {target}: {result.stderr}")

    for base in copy_source:
        lib = os.path.join(out_lib, base)
        result = run("install_name_tool", "-id", f"@loader_path/{base}", lib)
        if result.returncode != 0:
            raise RuntimeError(f"install_name_tool -id failed for {lib}: {result.stderr}")
        rewrite(lib, "lib")
    rewrite(out_bin, "exe")

    # ---- ad-hoc re-sign ----------------------------------------------------
    for target in [out_bin] + [os.path.join(out_lib, b) for b in copy_source]:
        result = run("codesign", "--force", "--sign", "-", "--timestamp=none", target)
        if result.returncode != 0:
            print(f"warning: codesign failed for {target}: {result.stderr}", file=sys.stderr)

    # ---- verify no Homebrew absolute deps remain --------------------------
    leftovers = []
    for target in [out_bin] + [os.path.join(out_lib, b) for b in copy_source]:
        for dep in otool_deps(target):
            if dep.startswith(("/opt/homebrew/", "/usr/local/")):
                leftovers.append(f"{target}: {dep}")
    if leftovers:
        print("error: unbundled absolute Homebrew dependencies remain:", file=sys.stderr)
        print("\n".join(leftovers), file=sys.stderr)
        return 1

    print(f"==> ok: {out_bin} + {len(copy_source)} dylibs bundled")
    return 0


if __name__ == "__main__":
    sys.exit(main())
