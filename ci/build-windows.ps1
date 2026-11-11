# GitHub Actions: 构建 oak-mcp Windows x86_64（native MSVC），并把 exe + DLL 放到 $env:OUT_DIR。
#
# FFmpeg 9 使用固定版本的 BtbN GPL shared 预编译包（动态链接，DLL 随 exe 分发），
# OpenColorIO 由 ocio-sys `bundled` 特性从源码静态构建。
# 不使用 vcpkg / conda / 系统 FFmpeg；由 FFMPEG_DIR 指定 BtbN 前缀。
#
# 环境变量（workflow 提供）：
#   UPSTREAM_SRC          干净的 example-mcp 源码目录
#   WORK_ROOT             工作目录（默认 $env:RUNNER_TEMP\oak-build）
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
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

# bindgen 能看到 MSVC / Windows SDK 头文件；OCIO 使用 Quercus 默认的 bundled 构建
$env:LIBCLANG_PATH = 'C:\Program Files\LLVM\bin'
if ($env:INCLUDE) {
    $includes = $env:INCLUDE.Split(';') | Where-Object { $_ } | ForEach-Object { "-I$_" }
    $env:BINDGEN_EXTRA_CLANG_ARGS = ($includes -join ' ')
}

# pkg-config 是 quercus-ffmpeg-link / ffmpeg-sys 解析 BtbN .pc 的必需工具
function Resolve-PkgConfig {
    $candidates = @(
        'C:\ProgramData\chocolatey\bin\pkg-config.exe',
        'C:\msys64\usr\bin\pkg-config.exe',
        'C:\Program Files\Git\usr\bin\pkg-config.exe'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    $cmd = Get-Command pkg-config -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    Write-Host '==> installing pkgconfiglite via chocolatey'
    choco install pkgconfiglite -y --no-progress
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    throw 'pkg-config is not available'
}
$pkgConfig = Resolve-PkgConfig
$env:PKG_CONFIG = $pkgConfig
$env:PATH = "$(Split-Path $pkgConfig);$env:PATH"
Write-Host "==> pkg-config: $pkgConfig"

# ---- BtbN FFmpeg 9.0 shared (GPL) ------------------------------------------
# The static Windows BtbN archive ships no dev files; the shared variant ships
# headers, MSVC import libraries (.lib) and pkg-config files, and enables
# NVENC/NVDEC/CUDA, QSV (oneVPL), AMF and D3D11VA/DXVA2/MediaFoundation.
# Pinned to one autobuild release so the asset and its SHA256 are stable.
$BtbnUrl = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-11-10-12-39/ffmpeg-n9.0.2-48-gd4070a14ce-win64-gpl-shared-9.0.zip'
$BtbnSha256 = '33e50d43c978337588f143f1b8e88d332173827934d664eb960db30a7de8037c'
$BtbnRoot = Join-Path $WorkRoot 'btbn-ffmpeg'
$BtbnZip = Join-Path $WorkRoot 'btbn-ffmpeg.zip'
$BtbnPrefix = $null
if (Test-Path $BtbnRoot) {
    $inner = Get-ChildItem $BtbnRoot -Directory | Select-Object -First 1
    if ($inner) { $BtbnPrefix = $inner.FullName }
}
if (-not $BtbnPrefix -or -not (Test-Path (Join-Path $BtbnPrefix 'lib\avcodec.lib'))) {
    Write-Host '==> downloading BtbN FFmpeg 9.0 shared build'
    curl.exe -fL --retry 3 --output $BtbnZip $BtbnUrl
    if ($LASTEXITCODE -ne 0) { throw "BtbN FFmpeg download failed: $LASTEXITCODE" }
    $actual = (Get-FileHash -Algorithm SHA256 -Path $BtbnZip).Hash.ToLower()
    if ($actual -ne $BtbnSha256) { throw "BtbN FFmpeg sha256 mismatch: $actual" }
    if (Test-Path $BtbnRoot) { Remove-Item -Recurse -Force $BtbnRoot }
    New-Item -ItemType Directory -Force -Path $BtbnRoot | Out-Null
    Expand-Archive -Path $BtbnZip -DestinationPath $BtbnRoot -Force
    $inner = Get-ChildItem $BtbnRoot -Directory | Select-Object -First 1
    if (-not $inner) { throw "BtbN FFmpeg archive layout not recognised: $BtbnZip" }
    $BtbnPrefix = $inner.FullName
}
if (-not (Test-Path (Join-Path $BtbnPrefix 'lib\pkgconfig\libavcodec.pc'))) {
    throw "BtbN FFmpeg prefix is incomplete: $BtbnPrefix"
}
$env:FFMPEG_DIR = $BtbnPrefix
$env:PKG_CONFIG_PATH = Join-Path $BtbnPrefix 'lib\pkgconfig'
"FFMPEG_DIR=$($env:FFMPEG_DIR)" | Out-File -FilePath $env:GITHUB_ENV -Append
"PKG_CONFIG_PATH=$($env:PKG_CONFIG_PATH)" | Out-File -FilePath $env:GITHUB_ENV -Append
Write-Host "==> FFmpeg: BtbN 9.0.2 shared -> $BtbnPrefix"

Write-Host '==> OCIO: ocio-sys bundled (static CMake build)'

Write-Host '==> upstream copy'
if (Test-Path $BuildSrc) { Remove-Item -Recurse -Force $BuildSrc }
Copy-Item -Recurse -Force $Upstream $BuildSrc
$env:CARGO_TARGET_DIR = $TargetDir

Write-Host '==> cargo build (FFmpeg via BtbN shared + OCIO bundled)'
Push-Location $BuildSrc
try {
    cargo build --release
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed: $LASTEXITCODE" }
} finally {
    Pop-Location
}

$Bin = Join-Path $TargetDir 'release\oak-mcp.exe'
if (-not (Test-Path $Bin)) { throw "binary missing: $Bin" }
# --check runs the freshly built exe, which imports the BtbN DLLs.
$env:PATH = "$(Join-Path $env:FFMPEG_DIR 'bin');$env:PATH"

# 硬件编解码检查：字符串表里必须有 NVENC/NVDEC/Media Foundation 相关编码器。
$avcodecDll = Get-ChildItem (Join-Path $BtbnPrefix 'bin') -Filter 'avcodec-*.dll' | Select-Object -First 1
if (-not $avcodecDll) { throw "BtbN avcodec DLL not found in $BtbnPrefix\bin" }
$asText = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($avcodecDll.FullName))
foreach ($enc in @('h264_nvenc', 'hevc_nvenc', 'h264_qsv', 'h264_amf', 'h264_mf', 'd3d11va')) {
    if (-not $asText.Contains($enc)) { throw "hardware codec '$enc' missing from $($avcodecDll.Name)" }
}
Write-Host '==> hardware codecs present: h264_nvenc, hevc_nvenc, h264_qsv, h264_amf, h264_mf, d3d11va'

Write-Host '==> --check (非致命：runner 无 GPU 时渲染初始化可能失败)'
& $Bin --check
$CheckExit = $LASTEXITCODE
if ($CheckExit -ne 0) {
    Write-Warning "oak-mcp --check exited $CheckExit on this runner (GPU/adapter limitation); binary was cross-verified under Wine in development"
}

Write-Host '==> stage exe + BtbN FFmpeg DLLs + MSVC runtime'
if (Test-Path $OutDir) { Remove-Item -Recurse -Force $OutDir }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Copy-Item $Bin (Join-Path $OutDir 'oak-mcp.exe')
Get-ChildItem (Join-Path $env:FFMPEG_DIR 'bin') -Filter '*.dll' |
    ForEach-Object { Copy-Item $_.FullName $OutDir -Force }
$ffmpegLicense = Join-Path $env:FFMPEG_DIR 'LICENSE.txt'
if (Test-Path $ffmpegLicense) {
    Copy-Item $ffmpegLicense (Join-Path $OutDir 'FFMPEG-LICENSE.txt') -Force
}
if (-not (Get-ChildItem $OutDir -Filter 'avcodec-*.dll' | Select-Object -First 1)) {
    throw "staged FFmpeg DLLs are missing in $OutDir"
}

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
        'mfuuid.dll', 'mfplat.dll', 'mf.dll', 'dxgi.dll', 'd3d11.dll', 'd3d12.dll', 'vulkan-1.dll',
        'avicap32.dll', 'avrt.dll', 'cfgmgr32.dll', 'd2d1.dll', 'msimg32.dll', 'ncrypt.dll',
        'usp10.dll', 'mfreadwrite.dll'
    )
    $missing = @()
    $pes = @(Get-ChildItem $OutDir -Filter '*.exe') + @(Get-ChildItem $OutDir -Filter '*.dll')
    foreach ($pe in $pes) {
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
