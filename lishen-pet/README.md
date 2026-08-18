# 黎深桌宠 · Lishen Desktop Pet

一只会陪你的 macOS / Windows 桌面小宠物。以《恋与深空》角色 **黎深（Zayne）** 的口吻，
在整点、饭点和深夜随机冒出一句短短的关心；点他一下，他会回你话。悬浮、透明、
置顶，可以拖着到处走，气泡会跟着他一起动。

<p align="center">
  <img src="assets/lishen.gif" width="180" alt="黎深桌宠动画">
</p>

> 情侣口吻的克制温柔，不说教、不肉麻、不"人机"。台词全部可自定义。

---

## ✨ 功能

- **悬浮桌宠**：透明置顶的小动画，可拖动到屏幕任意位置。
- **定时关心**：整点随机（带 ±12 分钟抖动，仅 7–23 点）、11:00 午饭提醒、
  18:00 晚饭提醒、23:30 深夜哄睡，每类台词最近不重复。
- **点击互动**：戳一下弹出"被戳"台词（"专心。""戳我，是想说什么吗？"…）。
- **磨砂气泡**：仿聊天界面的淡蓝圆角气泡 + 小尾巴 + 柔和阴影，拖动时同步跟随。
- **菜单栏控制**：让他说句话 / 显示·隐藏桌宠 / 暂停提醒 / 退出。
- **可选系统通知**：气泡的同时可一并发系统通知。
- **开机自启**：macOS 使用 launchd，Windows 使用当前用户 Startup 文件夹。

---

## 🚀 安装与运行（macOS）

> 需要系统自带的 `python3`（装了 Xcode Command Line Tools 即有）。

**最简单：双击运行**

1. 下载 / clone 本仓库到本地。
2. 双击 `启动黎深.command`。首次会自动创建独立环境并安装依赖（走清华镜像，约 1–2 分钟），之后秒开。
3. 想让他常驻后台、开机自启：双击 `设置开机自启.command`。

> 首次双击若提示"未验证的开发者"，到 **系统设置 → 隐私与安全性** 里点"仍要打开"即可。

**或者：手动用命令行**

```bash
cd lishen-pet
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py
```

---

## 🚀 安装与运行（Windows 11）

> 需要先安装官方 64 位 Python 3.12 或 3.13，并在安装器中勾选 **Add python.exe to PATH**。
> 项目不会修改系统 Python，只会在本目录创建独立的 `.venv`。

**最简单：双击运行**

1. 将整个 `lishen-pet` 文件夹放到本地路径。
2. 双击 `启动黎深-Windows.cmd`。首次运行会自动创建 `.venv` 并安装 `requirements.txt`，之后直接启动桌宠。
3. 想让他随当前用户开机启动：双击 `设置开机自启-Windows.cmd`。
4. 想取消：双击 `取消开机自启-Windows.cmd`。

依赖安装失败时，先在 PowerShell 中确认 `py -3.12 --version` 或 `py -3.13 --version` 能正常输出版本，再重新运行启动脚本。

**或者：手动用 PowerShell**

```powershell
cd lishen-pet
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe main.py
```

**诊断与自检**

- `诊断-Windows.cmd`：生成 `诊断报告-Windows.txt`。
- `测试主程序-Windows.cmd`：运行 3 秒并生成 `主程序测试输出.txt`。

Windows 版本不使用 macOS 的 `.command` 文件；macOS 版本仍按上面的 macOS 章节运行。

---

## ⚙️ 自定义

**改台词** —— 编辑 `data/lines.json`。按分类（`greeting` / `daily` / `night` /
`cheer` / `miss` / `weather` / `lunch` / `dinner` / `poke`）增删句子即可，改完重启生效。

**改时间、气泡样式、桌宠大小** —— 打开 `main.py`，顶部的配置区都有中文注释：
`LUNCH_HOUR`、`DINNER_HOUR`、`NIGHT_HOUR`、`PET_HEIGHT`、`BUBBLE_FILL`（气泡颜色）、
`BUBBLE_FONT_PX`（字号）等。

**换成你自己的角色图** —— 见下方「制作素材」。

---

## 🎨 制作素材（可选，换角色时才需要）

`assets/frames/` 里的 6 帧和 `assets/lishen.gif` 是用两个脚本从原图生成的：

```bash
pip install opencv-python Pillow numpy
python cut_and_matte.py   # 切割精灵图 + 边缘屏障洪水填充抠图（保留浅色底座）
python make_anim.py       # 6 帧合成循环动图
```

把 `assets/spritesheet.jpg` 换成你自己的多表情精灵图，调一下脚本里的行列数即可。

---

## 📁 项目结构

```
lishen-pet/
├── main.py               # 桌宠主程序（PySide6）
├── data/lines.json       # 台词库（分类，可自定义）
├── assets/               # 帧图、动图、图标（美术素材，见免责声明）
├── cut_and_matte.py      # 抠图脚本（制作用）
├── make_anim.py          # 动画合成脚本（制作用）
├── 启动黎深.command       # 一键启动
├── 设置开机自启.command    # 一键开机自启（launchd）
├── 启动黎深-Windows.cmd   # Windows 一键启动
├── 设置开机自启-Windows.cmd
├── 取消开机自启-Windows.cmd
├── 测试主程序-Windows.cmd
├── 诊断-Windows.cmd
├── windows/               # Windows PowerShell 安装、启动、自启和诊断脚本
├── requirements.txt
└── 安装与使用说明.md
```

---

## 🙏 致谢 & ⚠️ 免责声明

- 桌宠角色形象为手机游戏 **《恋与深空》（Love and Deepspace）** 中的角色
  **黎深 / Zayne**，著作权归 **叠纸游戏（Papergames / infold）** 及其权利人所有。
- 本项目为**个人非商业**的粉丝作品，仅供学习与自用；`assets/` 内的美术素材
  **不在本项目开源许可范围内**（代码为 MIT，见 [LICENSE](LICENSE)）。
- **请勿将本项目或其中素材用于任何商业用途。** 若版权方提出异议，请联系作者，
  我会立即移除相关素材。

---

## 📄 License

代码部分采用 [MIT License](LICENSE)。美术素材版权归原权利人所有，不适用 MIT。
