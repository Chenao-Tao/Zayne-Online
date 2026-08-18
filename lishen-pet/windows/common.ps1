Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$VenvDir = Join-Path $ProjectRoot '.venv'
$VenvPython = Join-Path $VenvDir 'Scripts\python.exe'
$VenvPythonw = Join-Path $VenvDir 'Scripts\pythonw.exe'

function Get-PythonCandidate {
    $candidates = @(
        [pscustomobject]@{ Command = 'py'; Prefix = @('-3.14') },
        [pscustomobject]@{ Command = 'py'; Prefix = @('-3.13') },
        [pscustomobject]@{ Command = 'py'; Prefix = @('-3.12') },
        [pscustomobject]@{ Command = 'py'; Prefix = @('-3.11') },
        [pscustomobject]@{ Command = 'py'; Prefix = @('-3.10') },
        [pscustomobject]@{ Command = 'python'; Prefix = @() }
    )
    $probe = 'import platform,sys; print("{0}.{1}.{2}|{3}|{4}".format(sys.version_info[0],sys.version_info[1],sys.version_info[2],platform.architecture()[0],sys.executable))'

    foreach ($candidate in $candidates) {
        $command = Get-Command $candidate.Command -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $command) {
            continue
        }
        try {
            $allArgs = @($candidate.Prefix) + @('-c', $probe)
            $result = (& $command.Source @allArgs 2>$null | Select-Object -First 1)
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($result)) {
                continue
            }
            $parts = $result -split '\|', 4
            $version = [version]$parts[0]
            if ($version -ge [version]'3.10' -and $version -lt [version]'3.15' -and $parts[1] -eq '64bit') {
                return [pscustomobject]@{
                    Executable = $command.Source
                    Prefix = [string[]]$candidate.Prefix
                    Version = $version
                    PythonPath = $parts[2]
                }
            }
        } catch {
            continue
        }
    }
    return $null
}

function Invoke-Python {
    param(
        [Parameter(Mandatory = $true)]$Python,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $allArgs = @($Python.Prefix) + @($Arguments)
    & $Python.Executable @allArgs | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Python 命令执行失败，退出码：$LASTEXITCODE"
    }
}

function Ensure-LishenEnvironment {
    if (-not (Test-Path -LiteralPath $VenvPython)) {
        $basePython = Get-PythonCandidate
        if ($null -eq $basePython) {
            throw '未找到可用的 64 位 Python 3.10–3.14。请先安装 Python 3.12 或 3.13，并勾选 Add python.exe to PATH。'
        }
        Write-Host "正在使用 Python $($basePython.Version) 创建虚拟环境……"
        Invoke-Python $basePython @('-m', 'venv', $VenvDir)
    }

    if (-not (Test-Path -LiteralPath $VenvPython)) {
        throw "虚拟环境创建失败：$VenvPython"
    }

    & $VenvPython -c 'import PySide6' 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host '正在安装 PySide6 依赖，首次运行需要联网……'
        & $VenvPython -m pip install --upgrade pip | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw 'pip 升级失败，请检查网络或代理设置。'
        }
        & $VenvPython -m pip install -r (Join-Path $ProjectRoot 'requirements.txt') | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw '依赖安装失败，请查看上方 pip 错误信息。'
        }
    }
    return $VenvPython
}

function Get-PythonwPath {
    if (Test-Path -LiteralPath $VenvPythonw) {
        return $VenvPythonw
    }
    return $VenvPython
}
