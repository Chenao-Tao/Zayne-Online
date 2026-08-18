. (Join-Path $PSScriptRoot 'common.ps1')

$startup = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startup '黎深桌宠.lnk'
if (Test-Path -LiteralPath $shortcutPath) {
    Remove-Item -LiteralPath $shortcutPath -Force
    Write-Host '已取消当前用户开机自启。'
} else {
    Write-Host '未找到黎深桌宠的开机自启快捷方式。'
}
Read-Host '按回车关闭窗口'
