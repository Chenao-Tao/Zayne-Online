$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$nativeScript = Join-Path $PSScriptRoot 'native-pet.ps1'
$launcher = Join-Path $PSScriptRoot 'launch-native.vbs'

try {
    $startup = [Environment]::GetFolderPath('Startup')
    if ([string]::IsNullOrWhiteSpace($startup)) {
        throw '无法定位当前用户的 Startup 文件夹。'
    }
    if (-not (Test-Path -LiteralPath $nativeScript)) {
        throw "缺少 Windows 原生启动脚本：$nativeScript"
    }
    if (-not (Test-Path -LiteralPath $launcher)) {
        throw "缺少 Windows 无窗口启动器：$launcher"
    }

    $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $shortcutPath = Join-Path $startup '恋与深空桌宠.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $wscript
    $shortcut.Arguments = '"' + $launcher + '"'
    $shortcut.WorkingDirectory = $ProjectRoot
    $shortcut.Save()

    Start-Process -FilePath $wscript -ArgumentList ('"' + $launcher + '"') -WorkingDirectory $ProjectRoot
    Write-Host "已设置无 Python 开机自启：$shortcutPath"
} catch {
    Write-Host "设置开机自启失败：$($_.Exception.Message)" -ForegroundColor Red
    Read-Host '按回车关闭窗口'
    exit 1
}
