$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$nativeScript = Join-Path $PSScriptRoot 'native-pet.ps1'

try {
    $startup = [Environment]::GetFolderPath('Startup')
    if ([string]::IsNullOrWhiteSpace($startup)) {
        throw '无法定位当前用户的 Startup 文件夹。'
    }
    if (-not (Test-Path -LiteralPath $nativeScript)) {
        throw "缺少 Windows 原生启动脚本：$nativeScript"
    }

    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shortcutPath = Join-Path $startup '黎深桌宠.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $nativeScript + '"'
    $shortcut.WorkingDirectory = $ProjectRoot
    $shortcut.Save()

    Start-Process -FilePath $powershell -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $nativeScript + '"')
    ) -WorkingDirectory $ProjectRoot
    Write-Host "已设置无 Python 开机自启：$shortcutPath"
} catch {
    Write-Host "设置开机自启失败：$($_.Exception.Message)" -ForegroundColor Red
    Read-Host '按回车关闭窗口'
    exit 1
}
