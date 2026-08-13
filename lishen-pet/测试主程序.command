#!/bin/bash
# 双击我 = 测试主程序。它会跑主程序 3 秒然后自动退出，
# 把完整过程写进 run.log。跑完把 run.log 内容发给 Claude。
cd "$(dirname "$0")"
source .venv/bin/activate 2>/dev/null
export LISHEN_SELFTEST=1
echo "开始测试主程序（3 秒后自动退出）……"
python main.py > 主程序测试输出.txt 2>&1
echo "主程序退出码: $?" >> 主程序测试输出.txt
echo "完成。请把「run.log」和「主程序测试输出.txt」发给 Claude。"
echo "----- run.log -----"
cat run.log 2>/dev/null
echo "----- 测试输出 -----"
cat 主程序测试输出.txt 2>/dev/null
read -n 1 -s -r -p "按任意键关闭此窗口……"
