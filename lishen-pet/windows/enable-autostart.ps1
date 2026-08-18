. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $python = Ensure-LishenEnvironment
    $startup = [Environment]::GetFolderPath('Startup')
    if ([string]::IsNullOrWhiteSpace($startup)) {
        throw '无法定位当前用户的 Startup 文件夹。'
    }

    $shortcutPath = Join-Path $startup '黎深桌宠.lnk'
    $main = Join-Path $ProjectRoot 'main.py'
    $pythonw = Get-PythonwPath
    $icon = Join-Path $ProjectRoot 'assets\icon_256.png'

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $pythonw
    $shortcut.Arguments = '"' + $main + '"'
    $shortcut.WorkingDirectory = $ProjectRoot
    if (Test-Path -LiteralPath $icon) {
        $shortcut.IconLocation = "$icon,0"
    }
    $shortcut.Save()

    Start-Process -FilePath $pythonw -ArgumentList ('"' + $main + '"') -WorkingDirectory $ProjectRoot
    Write-Host "已设置当前用户开机自启：$shortcutPath"
} catch {
    Write-Host "设置开机自启失败：$($_.Exception.Message)" -ForegroundColor Red
    Read-Host '按回车关闭窗口'
    exit 1
}
