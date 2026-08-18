. (Join-Path $PSScriptRoot 'common.ps1')

$report = Join-Path $ProjectRoot '诊断报告-Windows.txt'
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('==== 基本信息 ====')
$lines.Add("时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
$lines.Add("系统: $([Environment]::OSVersion.VersionString)")
$lines.Add("架构: $env:PROCESSOR_ARCHITECTURE")
$lines.Add("PowerShell: $($PSVersionTable.PSVersion)")
$lines.Add('')

$lines.Add('==== Python ====')
$basePython = Get-PythonCandidate
if ($null -eq $basePython) {
    $lines.Add('未找到可用的 64 位 Python 3.10–3.14。')
} else {
    $lines.Add("版本: $($basePython.Version)")
    $lines.Add("解释器: $($basePython.PythonPath)")
}
$lines.Add("虚拟环境: $(if (Test-Path -LiteralPath $VenvPython) { $VenvPython } else { '不存在' })")
$lines.Add('')

$lines.Add('==== PySide6 ====')
if (Test-Path -LiteralPath $VenvPython) {
    $pyside = & $VenvPython '-c' 'import PySide6; from PySide6 import QtCore; print("PySide6=" + PySide6.__version__); print("Qt=" + QtCore.qVersion())' 2>&1
    $lines.AddRange([string[]]$pyside)
} else {
    $lines.Add('虚拟环境不存在，未检查 PySide6。')
}
$lines.Add('')
$lines.Add('==== 文件 ====')
foreach ($file in @('main.py', 'requirements.txt', 'data\lines.json', 'assets\icon_256.png')) {
    $lines.Add("{0}: {1}" -f $file, (Test-Path -LiteralPath (Join-Path $ProjectRoot $file)))
}
for ($i = 0; $i -lt 6; $i++) {
    $file = "assets\frames\frame_$i.png"
    $lines.Add("{0}: {1}" -f $file, (Test-Path -LiteralPath (Join-Path $ProjectRoot $file)))
}

$lines | Set-Content -LiteralPath $report -Encoding UTF8
Write-Host "诊断完成：$report"
Read-Host '按回车关闭窗口'
