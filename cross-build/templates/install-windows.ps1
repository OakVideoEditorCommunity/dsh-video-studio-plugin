# video-studio 插件安装脚本（Windows x86_64）
# 用法（PowerShell）：powershell -ExecutionPolicy Bypass -File .\install.ps1
# 可选环境变量：
#   DSH_CLI      显式指定 dsh.cmd / dsh.exe 路径
#   DSH_PROFILE  Harness profile 名（默认 desktop）
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$data = Join-Path $env:LOCALAPPDATA 'video-studio'
$profileName = if ($env:DSH_PROFILE) { $env:DSH_PROFILE } else { 'desktop' }

Write-Host "==> 安装到 $data"
New-Item -ItemType Directory -Force -Path $data | Out-Null
Copy-Item -Path (Join-Path $here 'mcp\*') -Destination $data -Recurse -Force
if (Test-Path (Join-Path $data 'plugin')) { Remove-Item -Recurse -Force (Join-Path $data 'plugin') }
Copy-Item -Path (Join-Path $here 'plugin') -Destination $data -Recurse -Force

$dsh = $env:DSH_CLI
if (-not $dsh) {
    $cmd = Get-Command dsh -ErrorAction SilentlyContinue
    if ($cmd) { $dsh = $cmd.Source }
}
if (-not $dsh) {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\resources\runtime\cli\bin\dsh.cmd'),
        (Join-Path $env:PROGRAMFILES 'DeepSeek Harness\resources\runtime\cli\bin\dsh.cmd')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { $dsh = $candidate; break }
    }
}
if (-not $dsh) {
    throw "未找到 dsh CLI。请设置环境变量 DSH_CLI 指向 dsh.cmd 后重跑，例如:`n  `$env:DSH_CLI='C:\...\dsh.cmd'; .\install.ps1"
}

Write-Host "==> 注册插件到 profile: $profileName"
& $dsh plugin --profile $profileName add (Join-Path $data 'plugin')

Write-Host @"

安装完成。请重启 DeepSeek Harness，重启后左侧栏出现「视频预览」，
模型工具列表出现 mcp__oak__* 共 50 个。

MCP 二进制：$data\oak-mcp.exe
预览目录 ：$env:USERPROFILE\.dsh\video-studio\previews
"@
