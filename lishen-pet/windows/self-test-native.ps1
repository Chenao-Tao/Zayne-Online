$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$nativeScript = Join-Path $PSScriptRoot 'native-pet.ps1'
$output = Join-Path $ProjectRoot '主程序测试输出.txt'
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

try {
    & $powershell '-NoProfile' '-ExecutionPolicy' 'Bypass' '-File' $nativeScript '-SelfTest' *> $output
    $exitCode = $LASTEXITCODE
    Add-Content -LiteralPath $output -Value "主程序退出码: $exitCode" -Encoding UTF8
    Write-Host "无 Python 自检完成，输出文件：$output"
    if ($exitCode -ne 0) {
        Write-Host '主程序自检失败，请同时查看 error.log 和 run.log。' -ForegroundColor Red
        exit $exitCode
    }
} catch {
    Write-Host "自检失败：$($_.Exception.Message)" -ForegroundColor Red
    Read-Host '按回车关闭窗口'
    exit 1
}
Read-Host '按回车关闭窗口'
