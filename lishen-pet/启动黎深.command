#!/bin/bash
# 双击我即可启动恋与深空桌宠。
# 第一次运行会自动创建独立环境并安装依赖(需要联网，约 1-2 分钟)。
cd "$(dirname "$0")"

PY="python3"
VENV=".venv"

if [ ! -d "$VENV" ]; then
  echo "首次运行：正在创建运行环境……"
  $PY -m venv "$VENV"
fi
source "$VENV/bin/activate"

python -c "import PySide6" 2>/dev/null
if [ $? -ne 0 ]; then
  echo "正在安装依赖 PySide6（走国内清华镜像，通常 1-2 分钟）……"
  MIRROR="https://pypi.tuna.tsinghua.edu.cn/simple"
  pip install --upgrade pip -q -i "$MIRROR"
  pip install PySide6 -q -i "$MIRROR"
fi

echo "黎深上线了。关闭这个窗口不影响他运行；要退出请点菜单栏图标里的“退出”。"
python main.py
echo ""
echo "----------------------------------------"
echo "黎深已退出。如果是意外退出，错误信息在同文件夹的 error.log。"
echo "（把 error.log 的内容发给我，我来修）"
read -n 1 -s -r -p "按任意键关闭此窗口……"
