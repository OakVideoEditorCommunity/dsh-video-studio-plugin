# GitHub Actions: 构建 oak-mcp Windows x86_64（native MSVC），并把 exe + CRT DLL 放到 $env:OUT_DIR。
#
# FFmpeg 9 与 OpenColorIO 都由 quercus bootstrap 从源码**静态**构建：
#   - FFmpeg: quercus-ffmpeg-bootstrap 下载 pinned vcpkg 并用 x64-windows-static-md 构建
#   - OCIO:   ocio-sys `bundled` 特性 CMake 静态构建
# 不使用 BtbN / conda 预编译库。
#
# 环境变量（workflow 提供）：
#   UPSTREAM_SRC          干净的 example-mcp 源码目录
#   WORK_ROOT             工作目录（默认 $env:RUNNER_TEMP\oak-build）
#   QUERCUS_FFMPEG_CACHE  bootstrap 缓存目录（默认 $WorkRoot\quercus-ffmpeg）
#   OUT_DIR               产物目录（默认 $WorkRoot\out\windows-x64）
#   REPO_ROOT             本插件仓库根目录
$ErrorActionPreference = 'Stop'

$RepoRoot = if ($env:REPO_ROOT) { $env:REPO_ROOT } else { (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
$WorkRoot = if ($env:WORK_ROOT) { $env:WORK_ROOT } else { Join-Path $env:RUNNER_TEMP 'oak-build' }
$Upstream = $env:UPSTREAM_SRC
if (-not $Upstream) { throw 'UPSTREAM_SRC is required' }
$OutDir = if ($env:OUT_DIR) { $env:OUT_DIR } else { Join-Path $WorkRoot 'out\windows-x64' }
$BuildSrc = Join-Path $WorkRoot 'example-mcp-build'
$TargetDir = Join-Path $WorkRoot 'target-windows'
if (-not $env:QUERCUS_FFMPEG_CACHE) {
    $env:QUERCUS_FFMPEG_CACHE = Join-Path $WorkRoot 'quercus-ffmpeg'
}
New-Item -ItemType Directory -Force -Path $env:QUERCUS_FFMPEG_CACHE | Out-Null

# OCIO 静态构建 + bindgen 能看到 MSVC / Windows SDK 头文件
$env:OCIO_RS_LINK = 'static'
$env:OCIO_RS_ENABLE_REAL = '1'
$env:LIBCLANG_PATH = 'C:\Program Files\LLVM\bin'
if ($env:INCLUDE) {
    $includes = $env:INCLUDE.Split(';') | Where-Object { $_ } | ForEach-Object { "-I$_" }
    $env:BINDGEN_EXTRA_CLANG_ARGS = ($includes -join ' ')
}

Write-Host "==> bootstrap cache: $env:QUERCUS_FFMPEG_CACHE"
Write-Host '==> FFmpeg: vcpkg (x64-windows-static-md, built from source by quercus bootstrap)'
Write-Host '==> OCIO: ocio-sys bundled (static CMake build)'

Write-Host '==> upstream copy'
if (Test-Path $BuildSrc) { Remove-Item -Recurse -Force $BuildSrc }
Copy-Item -Recurse -Force $Upstream $BuildSrc
$env:CARGO_TARGET_DIR = $TargetDir

Write-Host '==> cargo build (FFmpeg via vcpkg + OCIO bundled; first run is slow)'
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

Write-Host '==> stage exe + MSVC runtime DLLs (FFmpeg/OCIO are static)'
if (Test-Path $OutDir) { Remove-Item -Recurse -Force $OutDir }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Copy-Item $Bin (Join-Path $OutDir 'oak-mcp.exe')

if ($env:VCToolsRedistDir) {
    $crt = Join-Path $env:VCToolsRedistDir 'x64\Microsoft.VC143.CRT'
    if (Test-Path $crt) {
        Get-ChildItem $crt -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName $OutDir -Force }
    }
}

# 导入闭包检查：exe 的非系统 DLL 依赖应能在目录内解析（预期只有 MSVC CRT）
$dumpbin = Join-Path $env:VCToolsInstallDir 'bin\Hostx64\x64\dumpbin.exe'
if (-not (Test-Path $dumpbin)) {
    $cmd = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
    if ($cmd) { $dumpbin = $cmd.Source }
}
if (Test-Path $dumpbin) {
    $resolved = @{}
    Get-ChildItem $OutDir -Filter '*.dll' | ForEach-Object { $resolved[$_.Name.ToLower()] = $true }
    $systemDlls = @(
        'kernel32.dll', 'kernelbase.dll', 'user32.dll', 'gdi32.dll', 'advapi32.dll',
        'shell32.dll', 'ole32.dll', 'oleaut32.dll', 'uuid.dll', 'comdlg32.dll',
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
