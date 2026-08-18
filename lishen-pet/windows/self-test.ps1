. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $python = Ensure-LishenEnvironment
    $main = Join-Path $ProjectRoot 'main.py'
    $output = Join-Path $ProjectRoot '主程序测试输出.txt'
    $previous = $env:LISHEN_SELFTEST
    $env:LISHEN_SELFTEST = '1'
    try {
        & $python $main *> $output
        $exitCode = $LASTEXITCODE
    } finally {
        if ($null -eq $previous) {
            Remove-Item Env:LISHEN_SELFTEST -ErrorAction SilentlyContinue
        } else {
            $env:LISHEN_SELFTEST = $previous
        }
    }
    Add-Content -LiteralPath $output -Value "主程序退出码: $exitCode" -Encoding UTF8
    Write-Host "自检完成，输出文件：$output"
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
