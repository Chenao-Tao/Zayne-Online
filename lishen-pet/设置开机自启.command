#!/bin/bash
# 双击我 = 设置"开机自动启动黎深"。再次双击会重新写入(路径变了也没关系)。
cd "$(dirname "$0")"
APPDIR="$(pwd)"
PLIST="$HOME/Library/LaunchAgents/com.lishen.pet.plist"

# 确保依赖已装好(复用启动脚本的环境)
if [ ! -d ".venv" ]; then
  python3 -m venv .venv
  source .venv/bin/activate
  pip install --upgrade pip -q && pip install PySide6 -q
fi
PYBIN="$APPDIR/.venv/bin/python"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.lishen.pet</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYBIN</string>
        <string>$APPDIR/main.py</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$APPDIR</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null
launchctl load "$PLIST"
echo "已设置开机自启，并已立即启动一次。"
echo "以后想取消开机自启：运行 launchctl unload \"$PLIST\" 并删除该文件。"
sleep 2
