. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $python = Ensure-LishenEnvironment
    $main = Join-Path $ProjectRoot 'main.py'
    $pythonw = Get-PythonwPath
    Start-Process -FilePath $pythonw -ArgumentList ('"' + $main + '"') -WorkingDirectory $ProjectRoot
    Write-Host '黎深已启动。日志文件：run.log、error.log'
} catch {
    Write-Host "启动失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host '请先安装 Python 3.12/3.13 x64，并确认命令行可以执行 py -3.12。'
    Read-Host '按回车关闭窗口'
    exit 1
}
