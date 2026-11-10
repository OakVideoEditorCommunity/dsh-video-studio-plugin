#!/usr/bin/env python3
"""Bundle Homebrew (and @rpath-resolved) dylibs into a macOS binary's lib/.

Usage: bundle-macos-dylibs.py <binary> <out-dir>

Creates <out-dir>/bin/<name> and <out-dir>/lib/*.dylib; rewrites references to
@executable_path/../lib or @loader_path so the folder is relocatable. Resolves
`@rpath/...` dependencies through the binary's LC_RPATH entries (plus Homebrew
lib dirs) and bundles them too. Ad-hoc re-signs every modified Mach-O (required
on arm64).
"""
import glob
import hashlib
import os
import shutil
import subprocess
import sys

SYSTEM_PREFIXES = ("/System/", "/usr/lib/", "/Library/Apple/")
EXTRA_LIB_DIRS = ("/opt/homebrew/lib", "/usr/local/lib")
# keg-only Homebrew formulae install their dylibs under opt/<formula>/lib,
# which is not on the default /opt/homebrew/lib search path.
for _root in ("/opt/homebrew/opt", "/usr/local/opt"):
    if os.path.isdir(_root):
        EXTRA_LIB_DIRS += tuple(sorted(glob.glob(os.path.join(_root, "*", "lib"))))


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


def otool_rpaths(path):
    out = run("otool", "-l", path).stdout
    rpaths = []
    lines = out.splitlines()
    for index, line in enumerate(lines):
        if "LC_RPATH" in line:
            for follow in lines[index + 1 : index + 4]:
                follow = follow.strip()
                if follow.startswith("path "):
                    rpaths.append(follow[len("path ") :].split(" (offset")[0].strip())
                    break
    return rpaths


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

    bin_dir = os.path.dirname(binary)
    bin_name = os.path.basename(binary)
    out_bin = os.path.join(out, "bin", bin_name)
    out_lib = os.path.join(out, "lib")
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(os.path.join(out, "bin"))
    os.makedirs(out_lib)
    shutil.copy2(binary, out_bin)
    os.chmod(out_bin, 0o755)

    def expand_rpath(rpath):
        for token, base in (("@executable_path", bin_dir), ("@loader_path", bin_dir)):
            if rpath.startswith(token):
                return base + rpath[len(token) :]
        return rpath

    def resolve_dep(dep, owner):
        """Return (resolved_abs_or_None, is_system)."""
        if is_system(dep):
            return None, True
        if dep.startswith("@rpath/"):
            suffix = dep[len("@rpath/") :]
            for rpath in otool_rpaths(owner):
                candidate = os.path.join(expand_rpath(rpath), suffix)
                if os.path.exists(candidate):
                    return os.path.realpath(candidate), False
            for lib_dir in EXTRA_LIB_DIRS:
                candidate = os.path.join(lib_dir, suffix)
                if os.path.exists(candidate):
                    return os.path.realpath(candidate), False
            return None, False
        if dep.startswith("@loader_path/"):
            candidate = os.path.join(os.path.dirname(owner), dep[len("@loader_path/") :])
            return (os.path.realpath(candidate), False) if os.path.exists(candidate) else (None, False)
        if dep.startswith("@executable_path/"):
            candidate = os.path.join(bin_dir, dep[len("@executable_path/") :])
            return (os.path.realpath(candidate), False) if os.path.exists(candidate) else (None, False)
        if dep.startswith("@"):
            return None, False
        if os.path.exists(dep):
            return os.path.realpath(dep), False
        return None, False

    # ---- collect closure ---------------------------------------------------
    queue = [os.path.realpath(binary)]
    seen = set()
    copy_source = {}   # bundled basename -> realpath
    mapping = {}       # original reference string -> in-package rel path
    unresolved = []
    while queue:
        current = queue.pop(0)
        if current in seen:
            continue
        seen.add(current)
        for dep in otool_deps(current):
            resolved, system = resolve_dep(dep, current)
            if system:
                continue
            if resolved is None:
                if dep.startswith("@"):
                    unresolved.append(f"{current}: {dep}")
                else:
                    print(f"warning: missing dependency {dep} (from {current})", file=sys.stderr)
                continue
            base = os.path.basename(resolved)
            if base in copy_source and copy_source[base] != resolved:
                digest = hashlib.sha256(resolved.encode()).hexdigest()[:8]
                base = f"{digest}-{base}"
            copy_source[base] = resolved
            mapping[dep] = f"lib/{base}"
            if resolved not in seen:
                queue.append(resolved)

    if unresolved:
        print("error: unresolved @-prefixed dependencies:", file=sys.stderr)
        print("\n".join(unresolved), file=sys.stderr)
        return 1

    for base, real in copy_source.items():
        dest = os.path.join(out_lib, base)
        shutil.copy2(real, dest)
        os.chmod(dest, 0o755)

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

    # ---- verify no absolute / @rpath Homebrew dependencies remain ---------
    leftovers = []
    for target in [out_bin] + [os.path.join(out_lib, b) for b in copy_source]:
        for dep in otool_deps(target):
            if dep.startswith(("/opt/homebrew/", "/usr/local/")):
                leftovers.append(f"{target}: {dep}")
            elif dep.startswith("@rpath/"):
                leftovers.append(f"{target}: {dep}")
    if leftovers:
        print("error: unbound dependencies remain:", file=sys.stderr)
        print("\n".join(leftovers), file=sys.stderr)
        return 1

    print(f"==> ok: {out_bin} + {len(copy_source)} dylibs bundled")
    return 0


if __name__ == "__main__":
    sys.exit(main())
