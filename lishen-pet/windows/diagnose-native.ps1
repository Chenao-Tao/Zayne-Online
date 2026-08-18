$ProjectRoot = Split-Path -Parent $PSScriptRoot
$nativeScript = Join-Path $PSScriptRoot 'native-pet.ps1'
$report = Join-Path $ProjectRoot '诊断报告-Windows.txt'
$lines = New-Object System.Collections.Generic.List[string]

$lines.Add('==== 基本信息 ====')
$lines.Add("时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
$lines.Add("系统: $([Environment]::OSVersion.VersionString)")
$lines.Add("架构: $env:PROCESSOR_ARCHITECTURE")
$lines.Add("PowerShell: $($PSVersionTable.PSVersion)")
$lines.Add('')
$lines.Add('==== 无 Python 运行环境 ====')

try {
    Add-Type -AssemblyName System.Windows.Forms
    $lines.Add('System.Windows.Forms: True')
} catch {
    $lines.Add("System.Windows.Forms: False - $($_.Exception.Message)")
}
try {
    Add-Type -AssemblyName System.Drawing
    $lines.Add('System.Drawing: True')
} catch {
    $lines.Add("System.Drawing: False - $($_.Exception.Message)")
}

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($nativeScript, [ref]$tokens, [ref]$errors) | Out-Null
$lines.Add("native-pet.ps1 语法错误数: $($errors.Count)")
$lines.Add('')
$lines.Add('==== 文件 ====')
foreach ($file in @('windows\native-pet.ps1', 'data\lines.json', 'assets\icon_256.png')) {
    $lines.Add("{0}: {1}" -f $file, (Test-Path -LiteralPath (Join-Path $ProjectRoot $file)))
}
for ($i = 0; $i -lt 6; $i++) {
    $file = "assets\frames\frame_$i.png"
    $lines.Add("{0}: {1}" -f $file, (Test-Path -LiteralPath (Join-Path $ProjectRoot $file)))
}

$lines | Set-Content -LiteralPath $report -Encoding UTF8
Write-Host "无 Python 诊断完成：$report"
Read-Host '按回车关闭窗口'
