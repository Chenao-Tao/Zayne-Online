$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $PSScriptRoot 'launch-native.vbs'
$output = Join-Path $ProjectRoot '主程序测试输出.txt'
$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'

try {
    $beforeTerminals = @(Get-Process WindowsTerminal -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    $started = Get-Date
    & $wscript $launcher '-SelfTest'

    $log = $null
    $deadline = (Get-Date).AddSeconds(12)
    do {
        Start-Sleep -Milliseconds 300
        $log = Get-ChildItem $env:TEMP -Filter 'lishen-pet-selftest-*.log' -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $started } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -ne $log -and (Get-Content -Raw $log.FullName) -match 'Windows 原生版已退出') {
            break
        }
    } while ((Get-Date) -lt $deadline)

    if ($null -eq $log) {
        throw '无窗口启动器没有生成自检日志。'
    }

    $content = Get-Content -Raw $log.FullName
    $afterTerminals = @(Get-Process WindowsTerminal -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    $newTerminals = @($afterTerminals | Where-Object { $_ -notin $beforeTerminals })

    $checks = @(
        [pscustomobject]@{ Name = 'STA 线程'; Pass = $content -match '线程单元：STA' },
        [pscustomobject]@{ Name = '托盘对象'; Pass = $content -match '托盘状态：Visible=True; Menu=True; PetMenu=True' },
        [pscustomobject]@{ Name = '功能菜单'; Pass = $content -match '功能菜单：让角色说句话' },
        [pscustomobject]@{ Name = '角色台词'; Pass = $content -match '角色台词分离：Lishen=True; Star=True' },
        [pscustomobject]@{ Name = '拖拽素材'; Pass = $content -match '拖拽动作素材已独立加载' },
        [pscustomobject]@{ Name = '贴边悬挂'; Pass = $content -match '贴边悬挂：Left=True; Right=True' },
        [pscustomobject]@{ Name = '悬挂保持'; Pass = $content -match '悬挂状态保持：True' },
        [pscustomobject]@{ Name = '悬挂台词'; Pass = $content -match '悬挂台词库：True' -and $content -match '悬挂点击分类：hanging' },
        [pscustomobject]@{ Name = '拖拽台词'; Pass = $content -match '拖拽点击分类：drag_right' },
        [pscustomobject]@{ Name = '重启入口'; Pass = $content -match '重启入口：Menu=True; Launcher=True' -and $content -match '重启入口自检：True' },
        [pscustomobject]@{ Name = '状态入口'; Pass = $content -match '状态入口：True' },
        [pscustomobject]@{ Name = '显示控制'; Pass = $content -match '显示控制：Opacity=100; ClickThrough=True' },
        [pscustomobject]@{ Name = '系统通知'; Pass = $content -match '系统通知默认关闭：True' },
        [pscustomobject]@{ Name = '躺平与饥饿'; Pass = $content -match '躺平素材：True' -and $content -match '饥饿台词库：True' },
        [pscustomobject]@{ Name = '甩飞功能'; Pass = $content -match '甩飞功能：True' },
        [pscustomobject]@{ Name = '状态动作'; Pass = $content -match '状态动作锁：True' },
        [pscustomobject]@{ Name = '状态锁定'; Pass = $content -match '悬挂状态锁：True' },
        [pscustomobject]@{ Name = '饥饿喂食'; Pass = $content -match '饥饿可喂食：True' },
        [pscustomobject]@{ Name = '重复喂食'; Pass = $content -match '重复喂食出新苹果：True' },
        [pscustomobject]@{ Name = '角色切换'; Pass = $content -match '切换角色：黎深' -and $content -match '切换角色：星星' },
        [pscustomobject]@{ Name = '消息循环退出'; Pass = $content -match 'Windows 原生版已退出' },
        [pscustomobject]@{ Name = '无新终端'; Pass = $newTerminals.Count -eq 0 }
    )

    $report = New-Object System.Collections.Generic.List[string]
    $report.Add($content.TrimEnd())
    $report.Add('')
    $report.Add('==== 断言 ====')
    foreach ($check in $checks) {
        $resultText = "{0}: {1}" -f @($check.Name, $(if ($check.Pass) { '通过' } else { '失败' }))
        $report.Add($resultText)
    }
    $report | Set-Content -LiteralPath $output -Encoding UTF8

    if (@($checks | Where-Object { -not $_.Pass }).Count -gt 0) {
        throw "无 Python 自检存在失败项，请查看：$output"
    }

    Remove-Item -LiteralPath $log.FullName -Force -ErrorAction SilentlyContinue
    Write-Host "无 Python 自检通过，输出文件：$output"
} catch {
    Write-Host "自检失败：$($_.Exception.Message)" -ForegroundColor Red
    Read-Host '按回车关闭窗口'
    exit 1
}
Read-Host '按回车关闭窗口'
