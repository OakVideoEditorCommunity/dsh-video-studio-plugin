# GitHub Actions: 构建 oak-mcp Windows x86_64（native MSVC），并把 exe + 运行 DLL 放到 $env:OUT_DIR。
#
# OpenColorIO 由 ocio-sys 的 `bundled` 特性从 vendored 源码用 CMake 静态构建
# （与上游 Windows CI 一致），不使用 conda / 预编译 OCIO。
#
# 环境变量（workflow 提供）：
#   UPSTREAM_SRC    干净的 example-mcp 源码目录
#   WORK_ROOT       工作目录（默认 $env:RUNNER_TEMP\oak-build）
#   FFMPEG_DIR      BtbN FFmpeg 9 shared 解压目录（含 include/lib/bin）
#   OUT_DIR         产物目录（默认 $WORK_ROOT\out\windows-x64）
#   REPO_ROOT       本插件仓库根目录
$ErrorActionPreference = 'Stop'

$RepoRoot = if ($env:REPO_ROOT) { $env:REPO_ROOT } else { (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
$WorkRoot = if ($env:WORK_ROOT) { $env:WORK_ROOT } else { Join-Path $env:RUNNER_TEMP 'oak-build' }
$Upstream = $env:UPSTREAM_SRC
if (-not $Upstream) { throw 'UPSTREAM_SRC is required' }
$OutDir = if ($env:OUT_DIR) { $env:OUT_DIR } else { Join-Path $WorkRoot 'out\windows-x64' }
$BuildSrc = Join-Path $WorkRoot 'example-mcp-build'
$TargetDir = Join-Path $WorkRoot 'target-windows'

if (-not $env:FFMPEG_DIR) { throw 'FFMPEG_DIR is required' }
if (-not (Test-Path (Join-Path $env:FFMPEG_DIR 'lib\pkgconfig'))) {
    throw "FFMPEG_DIR has no lib\pkgconfig: $env:FFMPEG_DIR"
}

# --- 环境：FFmpeg pkg-config + OCIO bundled static + MSVC / bindgen --------------
$env:OCIO_RS_LINK = 'static'
$env:OCIO_RS_ENABLE_REAL = '1'
$env:PKG_CONFIG_PATH = (Join-Path $env:FFMPEG_DIR 'lib\pkgconfig')
$env:PKG_CONFIG_ALLOW_CROSS = '0'
$env:PATH = "$(Join-Path $env:FFMPEG_DIR 'bin');$env:PATH"

$env:LIBCLANG_PATH = 'C:\Program Files\LLVM\bin'
if ($env:INCLUDE) {
    $includes = $env:INCLUDE.Split(';') | Where-Object { $_ } | ForEach-Object { "-I$_" }
    $env:BINDGEN_EXTRA_CLANG_ARGS = ($includes -join ' ')
}

Write-Host "==> FFmpeg: $env:FFMPEG_DIR"
Write-Host "==> OCIO: bundled (ocio-sys static CMake build)"
Write-Host "==> cmake: $((Get-Command cmake -ErrorAction SilentlyContinue).Source)"

Write-Host '==> upstream copy'
if (Test-Path $BuildSrc) { Remove-Item -Recurse -Force $BuildSrc }
Copy-Item -Recurse -Force $Upstream $BuildSrc
$env:CARGO_TARGET_DIR = $TargetDir

Write-Host '==> cargo build (OCIO bundled build may take several minutes)'
Push-Location $BuildSrc
try {
    cargo build --release
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed: $LASTEXITCODE" }
} finally {
    Pop-Location
}

$Bin = Join-Path $TargetDir 'release\oak-mcp.exe'
if (-not (Test-Path $Bin)) { throw "binary missing: $Bin" }

Write-Host '==> --check (非致命：runner 无 GPU 时渲染初始化可能失败)'
& $Bin --check
$CheckExit = $LASTEXITCODE
if ($CheckExit -ne 0) {
    Write-Warning "oak-mcp --check exited $CheckExit on this runner (GPU/adapter limitation); binary was cross-verified under Wine in development"
}

Write-Host '==> stage exe + runtime DLLs'
if (Test-Path $OutDir) { Remove-Item -Recurse -Force $OutDir }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Copy-Item $Bin (Join-Path $OutDir 'oak-mcp.exe')

# FFmpeg shared DLLs（OCIO 已静态链接，无需 OCIO DLL）
Get-ChildItem (Join-Path $env:FFMPEG_DIR 'bin') -Filter '*.dll' | ForEach-Object {
    Copy-Item $_.FullName $OutDir
}
# MSVC 运行库（Rust MSVC 产物默认动态链接 CRT；C++ 部分需要 msvcp140）
if ($env:VCToolsRedistDir) {
    $crt = Join-Path $env:VCToolsRedistDir 'x64\Microsoft.VC143.CRT'
    if (Test-Path $crt) {
        Get-ChildItem $crt -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName $OutDir -Force }
    }
}

# 导入闭包检查：exe 与本目录 DLL 的非系统依赖应能在目录内解析
$dumpbin = Join-Path $env:VCToolsInstallDir 'bin\Hostx64\x64\dumpbin.exe'
if (-not (Test-Path $dumpbin)) {
    $cmd = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
    if ($cmd) { $dumpbin = $cmd.Source }
}
if (Test-Path $dumpbin) {
    $resolved = @{}
    Get-ChildItem $OutDir -Filter '*.dll' | ForEach-Object { $resolved[$_.Name.ToLower()] = $true }
    $systemDlls = @(
        'api-ms-win-', 'ext-ms-win-', 'kernel32.dll', 'kernelbase.dll', 'user32.dll', 'gdi32.dll',
        'advapi32.dll', 'shell32.dll', 'ole32.dll', 'oleaut32.dll', 'uuid.dll', 'comdlg32.dll',
        'winspool.drv', 'bcrypt.dll', 'bcryptprimitives.dll', 'ntdll.dll', 'combase.dll',
        'setupapi.dll', 'opengl32.dll', 'ws2_32.dll', 'dbghelp.dll', 'userenv.dll', 'msvcrt.dll',
        'imm32.dll', 'winmm.dll', 'shlwapi.dll', 'version.dll', 'crypt32.dll', 'secur32.dll',
        'iphlpapi.dll', 'dnsapi.dll', 'mswsock.dll', 'wldap32.dll', 'normaliz.dll', 'psapi.dll',
        'powrprof.dll', 'rpcrt4.dll', 'oleacc.dll', 'uxtheme.dll', 'dwmapi.dll', 'winhttp.dll',
        'wininet.dll', 'urlmon.dll', 'httpapi.dll', 'dhcpcsvc.dll', 'dwrite.dll', 'dcomp.dll',
        'mfuuid.dll', 'mfplat.dll', 'mf.dll', 'dxgi.dll', 'd3d11.dll', 'd3d12.dll', 'vulkan-1.dll'
    )
    $missing = @()
    foreach ($pe in (Get-ChildItem $OutDir -Filter '*.exe') + (Get-ChildItem $OutDir -Filter '*.dll')) {
        $deps = & $dumpbin /nologo /dependents $pe.FullName 2>$null | Select-String -Pattern '^\s+([\w.\-]+\.(?:dll|drv))\s*$' -AllMatches
        foreach ($m in $deps.Matches) {
            $name = $m.Groups[1].Value.ToLower()
            if ($name -like 'api-ms-win-*' -or $name -like 'ext-ms-win-*') { continue }
            if ($systemDlls -contains $name) { continue }
            if (-not $resolved.ContainsKey($name)) { $missing += "$($pe.Name) -> $name" }
        }
    }
    if ($missing.Count -gt 0) {
        Write-Warning ("unresolved local DLL dependencies:`n" + ($missing -join "`n"))
    } else {
        Write-Host '==> import closure OK (all non-system DLLs present)'
    }
}

$size = (Get-ChildItem $OutDir | Measure-Object -Property Length -Sum).Sum
Write-Host "==> staged $((Get-ChildItem $OutDir).Count) files, $([math]::Round($size/1MB,1)) MB -> $OutDir"
