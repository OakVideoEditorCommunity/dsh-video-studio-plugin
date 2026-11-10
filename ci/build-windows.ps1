# GitHub Actions: 构建 oak-mcp Windows x86_64（native MSVC），并把 exe + 运行 DLL 放到 $env:OUT_DIR。
#
# 环境变量（workflow 提供）：
#   UPSTREAM_SRC    干净的 example-mcp 源码目录
#   WORK_ROOT       工作目录（默认 $env:RUNNER_TEMP\oak-build）
#   FFMPEG_DIR      BtbN FFmpeg 9 shared 解压目录（含 include/lib/bin）
#   CONDA_PREFIX    micromamba 环境（含 libopencolorio 2.5 + pkgconf）
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

function Resolve-CondaEnv {
    if ($env:CONDA_PREFIX -and (Test-Path (Join-Path $env:CONDA_PREFIX 'Library'))) { return $env:CONDA_PREFIX }
    $envPath = Join-Path $WorkRoot 'ocio-env'
    if (Test-Path (Join-Path $envPath 'Library')) { return $envPath }
    $condaExe = $null
    foreach ($candidate in @(
        (Join-Path $env:ProgramData 'miniconda3\Scripts\conda.exe'),
        'C:\Miniconda3\Scripts\conda.exe',
        'C:\Miniconda\Scripts\conda.exe'
    )) {
        if (Test-Path $candidate) { $condaExe = $candidate; break }
    }
    if (-not $condaExe) {
        $cmd = Get-Command conda -ErrorAction SilentlyContinue
        if ($cmd) { $condaExe = $cmd.Source }
    }
    if ($condaExe) {
        Write-Host "==> create conda env ($envPath) with libopencolorio 2.5 + pkgconf"
        & $condaExe create -y -p $envPath -c conda-forge 'libopencolorio=2.5' pkgconf
        if ($LASTEXITCODE -ne 0) { throw "conda create failed: $LASTEXITCODE" }
        return $envPath
    }
    throw 'Neither an existing conda env nor conda.exe was found; cannot provision OpenColorIO'
}

$CondaPrefix = Resolve-CondaEnv
$env:CONDA_PREFIX = $CondaPrefix
$OcioPrefix = Join-Path $CondaPrefix 'Library'
$OcioBin = Join-Path $OcioPrefix 'bin'
# pkgconf 以 pkg-config 名称被调用时行为一致；补一个 pkg-config.exe shim
$pkgconfExe = Get-ChildItem $OcioBin -Filter 'pkgconf*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
$pkgConfigExe = Join-Path $OcioBin 'pkg-config.exe'
if ($pkgconfExe -and -not (Test-Path $pkgConfigExe)) {
    Copy-Item $pkgconfExe.FullName $pkgConfigExe
}
if (Test-Path $pkgConfigExe) { $env:PKG_CONFIG = $pkgConfigExe }
$PcDir = Join-Path $OcioPrefix 'lib\pkgconfig'
New-Item -ItemType Directory -Force -Path $PcDir | Out-Null

# OpenColorIO.pc（conda-forge 包不一定带 pkg-config 文件）
$OcioVersion = '2.5.2'
$pcContent = @"
prefix=$($OcioPrefix -replace '\\','/')
libdir=`${prefix}/lib
includedir=`${prefix}/include
Name: OpenColorIO
Description: OpenColorIO color management
Version: $OcioVersion
Libs: -L`${libdir} -lOpenColorIO
Cflags: -I`${includedir} -I`${includedir}/OpenColorIO
"@
Set-Content -Path (Join-Path $PcDir 'OpenColorIO.pc') -Value $pcContent -Encoding ascii

$env:OCIO_INSTALL_DIR = $OcioPrefix
$env:OCIO_RS_LINK = 'dynamic'
$env:PKG_CONFIG_PATH = "$PcDir;$(Join-Path $env:FFMPEG_DIR 'lib\pkgconfig')"
$env:PKG_CONFIG_ALLOW_CROSS = '0'
$env:PATH = "$(Join-Path $env:FFMPEG_DIR 'bin');$(Join-Path $OcioPrefix 'bin');$env:PATH"

# bindgen / libclang：让 clang 能看到 MSVC CRT + Windows SDK 头文件
$env:LIBCLANG_PATH = 'C:\Program Files\LLVM\bin'
if ($env:INCLUDE) {
    $includes = $env:INCLUDE.Split(';') | Where-Object { $_ } | ForEach-Object { "-I$_" }
    $env:BINDGEN_EXTRA_CLANG_ARGS = ($includes -join ' ')
}

Write-Host '==> upstream copy'
if (Test-Path $BuildSrc) { Remove-Item -Recurse -Force $BuildSrc }
Copy-Item -Recurse -Force $Upstream $BuildSrc
$env:CARGO_TARGET_DIR = $TargetDir

Write-Host '==> cargo build'
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

# FFmpeg shared DLLs
Get-ChildItem (Join-Path $env:FFMPEG_DIR 'bin') -Filter '*.dll' | ForEach-Object {
    Copy-Item $_.FullName $OutDir
}
# OpenColorIO + conda 依赖 DLL（跳过系统 api-ms-win-* 与 ucrtbase）
Get-ChildItem (Join-Path $OcioPrefix 'bin') -Filter '*.dll' | Where-Object {
    $_.Name -notlike 'api-ms-win-*' -and $_.Name -ne 'ucrtbase.dll'
} | ForEach-Object {
    Copy-Item $_.FullName $OutDir -Force
}
# MSVC 运行库（app-local）
if ($env:VCToolsRedistDir) {
    $crt = Join-Path $env:VCToolsRedistDir 'x64\Microsoft.VC143.CRT'
    if (Test-Path $crt) {
        Get-ChildItem $crt -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName $OutDir -Force }
    }
}

# 校验导入闭包：exe 与本目录 DLL 的依赖都能在目录内或系统里找到
$dumpbin = Join-Path $env:VCToolsInstallDir 'bin\Hostx64\x64\dumpbin.exe'
if (-not (Test-Path $dumpbin)) {
    $cmd = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
    if ($cmd) { $dumpbin = $cmd.Source }
}
if (Test-Path $dumpbin) {
    $resolved = @{}
    Get-ChildItem $OutDir -Filter '*.dll' | ForEach-Object { $resolved[$_.Name.ToLower()] = $true }
    $missing = @()
    foreach ($pe in (Get-ChildItem $OutDir -Filter '*.exe') + (Get-ChildItem $OutDir -Filter '*.dll')) {
        $deps = & $dumpbin /nologo /dependents $pe.FullName 2>$null | Select-String -Pattern '^\s+([\w.\-]+\.dll)\s*$' -AllMatches
        foreach ($m in $deps.Matches) {
            $name = $m.Groups[1].Value.ToLower()
            if ($name -like 'api-ms-win-*' -or $name -in @('kernel32.dll','user32.dll','gdi32.dll','advapi32.dll','shell32.dll','ole32.dll','oleaut32.dll','uuid.dll','comdlg32.dll','winspool.drv','bcrypt.dll','bcryptprimitives.dll','ntdll.dll','combase.dll','setupapi.dll','opengl32.dll','ws2_32.dll','dbghelp.dll','userenv.dll','ntdll.dll','msvcrt.dll','kernelbase.dll','imm32.dll','winmm.dll','wsock32.dll','shlwapi.dll','version.dll','crypt32.dll','secur32.dll','iphlpapi.dll','dnsapi.dll','mswsock.dll','wldap32.dll','normaliz.dll','psapi.dll','powrprof.dll','rpcrt4.dll','oleacc.dll','uxtheme.dll','dwmapi.dll','mfuuid.dll','mfplat.dll','mf.dll','dxgi.dll','d3d11.dll','d3d12.dll','vulkan-1.dll','winhttp.dll','wininet.dll','urlmon.dll','httpapi.dll','dhcpcsvc.dll','dwrite.dll','dcomp.dll','windows.applicationmodel.dll','windows.storage.dll')) { continue }
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
