#!/bin/bash
# 双击我 = 一键诊断。会生成"诊断报告.txt"，把它发给 Claude 即可。
cd "$(dirname "$0")"

REPORT="诊断报告.txt"
rm -f "$REPORT"

run() { echo ">>> $*"; "$@" 2>&1; echo; }

{
  echo "==== 基本信息 ===="
  echo "时间: $(date)"
  echo "架构 arch: $(arch)"
  echo "uname -m: $(uname -m)"
  sw_vers 2>&1
  echo

  echo "==== venv Python ===="
  if [ -d ".venv" ]; then
    source .venv/bin/activate
    run which python
    run python --version
    run python -c "import platform,sys; print('machine=',platform.machine()); print('exe=',sys.executable)"
    run python -c "import PySide6; print('PySide6', PySide6.__version__)"
    run python -c "from PySide6 import QtCore; print('Qt', QtCore.__version__)"
  else
    echo "(没有 .venv)"
  fi
  echo

  echo "==== 最小窗口测试(能不能弹窗) ===="
} > "$REPORT" 2>&1

# 单独跑最小窗口测试，把可能的原生崩溃信息(段错误等)也收进文件
if [ -d ".venv" ]; then
  source .venv/bin/activate
  python - > /tmp/minwin.out 2>&1 <<'PY'
import sys, traceback
try:
    from PySide6.QtWidgets import QApplication, QLabel
    from PySide6.QtCore import QTimer
    app = QApplication(sys.argv)
    w = QLabel("测试窗口"); w.show()
    QTimer.singleShot(900, app.quit)
    app.exec()
    print("MINIMAL_WINDOW_OK")
except BaseException:
    traceback.print_exc()
PY
  echo "最小窗口退出码: $?" >> "$REPORT"
  cat /tmp/minwin.out >> "$REPORT" 2>&1
fi

echo "" >> "$REPORT"
echo "==== 主程序 error.log(若有) ====" >> "$REPORT"
cat error.log >> "$REPORT" 2>/dev/null || echo "(无 error.log)" >> "$REPORT"

echo "诊断完成，已生成「诊断报告.txt」。把它的内容发给 Claude 就行。"
echo "报告位置：$(pwd)/诊断报告.txt"
read -n 1 -s -r -p "按任意键关闭此窗口……"
