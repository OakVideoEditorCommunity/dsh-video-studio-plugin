# video-studio 插件卸载脚本（Windows x86_64）
$ErrorActionPreference = 'Continue'

$data = Join-Path $env:LOCALAPPDATA 'video-studio'
$profileName = if ($env:DSH_PROFILE) { $env:DSH_PROFILE } else { 'desktop' }

$dsh = $env:DSH_CLI
if (-not $dsh) {
    $cmd = Get-Command dsh -ErrorAction SilentlyContinue
    if ($cmd) { $dsh = $cmd.Source }
}
if ($dsh) {
    & $dsh plugin --profile $profileName remove @local/video-studio
}

Remove-Item -Recurse -Force $data -ErrorAction SilentlyContinue
Write-Host "已移除 $data。重启 DeepSeek Harness 后插件消失（预览文件仍保留在 $env:USERPROFILE\.dsh\video-studio\previews）。"
