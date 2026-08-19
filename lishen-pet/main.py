#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
黎深桌宠 (Lishen Desktop Pet)
- 悬浮、透明、置顶的动图小黎深，可拖动、可点击
- 点击 -> 弹气泡说一句"被戳"台词
- 菜单栏(系统托盘)图标：让他说句话 / 显示·隐藏 / 开关提醒 / 退出
- 定时关心：每小时随机(带抖动) + 11:00 午饭 + 18:00 晚饭 + 深夜哄睡
台词全部来自 data/lines.json，可自行增删。
依赖：PySide6   ->  pip install PySide6
"""

import sys, os, json, random, time, traceback
from collections import deque, defaultdict
from datetime import datetime

from PySide6.QtCore import Qt, QTimer, QRect, QRectF, QSize
from PySide6.QtGui import (QPixmap, QIcon, QAction, QPainter, QPainterPath,
                           QMovie,
                           QPen, QColor, QFont, QFontMetrics)
from PySide6.QtWidgets import (QApplication, QWidget, QLabel, QSystemTrayIcon,
                               QMenu, QGraphicsDropShadowEffect)

# ----------------------------------------------------------------------------
# 配置：想改行为改这里就行
# ----------------------------------------------------------------------------
APP_DIR   = os.path.dirname(os.path.abspath(__file__))
ASSET_DIR = os.path.join(APP_DIR, "assets")
FRAME_DIR = os.path.join(ASSET_DIR, "frames")
STAR_DIR  = os.path.join(ASSET_DIR, "star")
DATA_FILE = os.path.join(APP_DIR, "data", "lines.json")
LOG_FILE  = os.path.join(APP_DIR, "error.log")
DBG_FILE  = os.path.join(APP_DIR, "run.log")


def dbg(step):
    """逐步记录，定位崩在哪一步。"""
    line = f"[{datetime.now():%H:%M:%S}] {step}\n"
    try:
        with open(DBG_FILE, "a", encoding="utf-8") as f:
            f.write(line)
            f.flush()
    except Exception:
        pass
    print(line, end="")

PET_HEIGHT      = 170     # 桌宠显示高度(像素)，想更大改这里
HOURLY_JITTER   = 12      # 整点问候的随机抖动(分钟, ±)
LUNCH_HOUR      = 11      # 午饭提醒
DINNER_HOUR     = 18      # 晚饭提醒
NIGHT_HOUR      = 23      # 深夜哄睡(23:30 附近)
NIGHT_MINUTE    = 30
BUBBLE_SECONDS  = 8       # 气泡停留时间(秒)
RECENT_MEMORY   = 5       # 每类最近多少条不重复
NOTIFY_TOO      = True    # 除了气泡，是否同时发系统通知

# 动画：帧序列 + 每帧时长(毫秒)。frame_0..5 对应六个表情。
ANIM_SEQ   = [0, 0, 1, 3, 2, 4, 5, 0]
ANIM_MS    = [1400, 200, 500, 700, 900, 700, 600, 400]

STAR_ACTIONS = {
    "idle": ["沈星回喵：嗨.gif", "沈星回喵：呆.gif", "沈星回喵：右摇摆.gif", "沈星回喵：左摇摆.gif"],
    "greeting": ["沈星回喵：嗨.gif", "沈星回喵：兔叽咪.gif"],
    "poke": ["沈星回喵：玩.gif", "沈星回喵：兔叽咪.gif", "沈星回喵：糟糕.gif"],
    "lunch": ["沈星回喵：饿了.gif", "沈星回喵：嚼嚼嚼.gif", "沈星回喵：吃撑了.gif"],
    "dinner": ["沈星回喵：饿了.gif", "沈星回喵：嚼嚼嚼.gif", "沈星回喵：吃撑了.gif"],
    "night": ["沈星回喵：打瞌睡.gif", "沈星回喵：躺平.gif"],
    "cheer": ["沈星回喵：热舞正面.gif", "沈星回喵：热舞转身.gif"],
    "miss": ["沈星回喵：兔叽咪.gif", "沈星回喵：玩.gif"],
    "weather": ["沈星回喵：左摇摆.gif", "沈星回喵：右摇摆.gif"],
}

STAR_DRAG_ACTIONS = {
    "left": "沈星回喵：左拎喵喵.gif",
    "right": "沈星回喵：右拎喵喵.gif",
}


def log_err(where=""):
    """把异常写进 error.log，方便排查；同时打印到终端。"""
    msg = f"\n[{datetime.now():%Y-%m-%d %H:%M:%S}] 出错于 {where}\n" + traceback.format_exc()
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(msg)
    except Exception:
        pass
    print(msg)


# ----------------------------------------------------------------------------
# 台词管理：分类 + 最近不重复
# ----------------------------------------------------------------------------
class Lines:
    def __init__(self, path):
        with open(path, "r", encoding="utf-8") as f:
            self.data = json.load(f)
        self.default_cats = self.data.get("categories", {})
        characters = self.data.get("characters", {})
        self.character_cats = {
            "lishen": self.default_cats,
            "star": characters.get("star", {}).get("categories", self.default_cats),
        }
        self.recent = defaultdict(lambda: deque(maxlen=RECENT_MEMORY))

    def pick(self, category, character="lishen"):
        cats = self.character_cats.get(character, self.default_cats)
        pool = cats.get(category) or []
        if not pool:
            return None
        recent = self.recent[(character, category)]
        choices = [s for s in pool if s not in recent] or pool
        line = random.choice(choices)
        recent.append(line)
        return line


# ----------------------------------------------------------------------------
# 气泡：仿参考聊天界面的磨砂淡蓝圆角对话框 + 朝下小尾巴 + 柔和阴影
# ----------------------------------------------------------------------------
# 视觉参数（想调气泡外观改这里）
BUBBLE_RADIUS   = 20                      # 圆角
BUBBLE_PAD_H    = 17                      # 文字左右内边距
BUBBLE_PAD_V    = 13                      # 文字上下内边距
BUBBLE_MAXW     = 300                     # 气泡最大宽度
BUBBLE_TAIL_W   = 20                      # 尾巴宽
BUBBLE_TAIL_H   = 11                      # 尾巴高
BUBBLE_FONT_PX  = 15                      # 字号
BUBBLE_FILL     = QColor(244, 248, 252, 236)   # 磨砂白蓝底
BUBBLE_EDGE     = QColor(255, 255, 255, 170)   # 高光描边
BUBBLE_TEXT     = QColor(64, 79, 97)           # 石板灰蓝文字


class _Balloon(QWidget):
    """真正画气泡的子控件（圆角框 + 尾巴 + 文字），阴影加在它身上。"""
    def __init__(self, parent):
        super().__init__(parent)
        self._text = ""
        self._font = QFont("PingFang SC", BUBBLE_FONT_PX)
        self._font.setStyleStrategy(QFont.PreferAntialias)
        self._body_w = self._body_h = 0
        self._tw = self._th = 0

    def set_text(self, text):
        self._text = text
        fm = QFontMetrics(self._font)
        avail = BUBBLE_MAXW - 2 * BUBBLE_PAD_H
        r = fm.boundingRect(QRect(0, 0, avail, 100000),
                            Qt.TextWordWrap, text)
        self._tw, self._th = r.width(), r.height()
        self._body_w = self._tw + 2 * BUBBLE_PAD_H
        self._body_h = self._th + 2 * BUBBLE_PAD_V
        self.resize(self._body_w, self._body_h + BUBBLE_TAIL_H)
        self.update()

    def paintEvent(self, _):
        try:
            p = QPainter(self)
            p.setRenderHint(QPainter.Antialiasing, True)
            body = QRectF(0, 0, self._body_w, self._body_h)
            path = QPainterPath()
            path.addRoundedRect(body, BUBBLE_RADIUS, BUBBLE_RADIUS)
            cx = self._body_w / 2
            tail = QPainterPath()
            tail.moveTo(cx - BUBBLE_TAIL_W / 2, self._body_h - 2)
            tail.lineTo(cx, self._body_h + BUBBLE_TAIL_H)
            tail.lineTo(cx + BUBBLE_TAIL_W / 2, self._body_h - 2)
            tail.closeSubpath()
            path = path.united(tail)
            p.setPen(QPen(BUBBLE_EDGE, 1))
            p.setBrush(BUBBLE_FILL)
            p.drawPath(path)
            p.setPen(BUBBLE_TEXT)
            p.setFont(self._font)
            p.drawText(QRectF(BUBBLE_PAD_H, BUBBLE_PAD_V, self._tw, self._th),
                       int(Qt.TextWordWrap | Qt.AlignLeft | Qt.AlignVCenter),
                       self._text)
        except Exception:
            log_err("气泡绘制")


class Bubble(QWidget):
    MARGIN = 20   # 给阴影留出的边距，避免被窗口裁掉

    def __init__(self):
        super().__init__(None,
            Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool |
            Qt.WindowTransparentForInput)
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setAttribute(Qt.WA_ShowWithoutActivating)
        self.balloon = _Balloon(self)
        eff = QGraphicsDropShadowEffect(self)
        eff.setBlurRadius(26)
        eff.setColor(QColor(40, 64, 96, 90))
        eff.setOffset(0, 5)
        self.balloon.setGraphicsEffect(eff)
        self._cx = self._top = 0
        self._t = QTimer(self)
        self._t.setSingleShot(True)
        self._t.timeout.connect(self.hide)

    def show_text(self, text, center_x, top_y):
        if not text:
            return
        self.balloon.set_text(text)
        self.balloon.move(self.MARGIN, self.MARGIN)
        self.resize(self.balloon.width() + 2 * self.MARGIN,
                    self.balloon.height() + 2 * self.MARGIN)
        self.reposition(center_x, top_y)
        self.show()
        self.raise_()
        self._t.start(BUBBLE_SECONDS * 1000)

    def reposition(self, center_x, top_y):
        """把气泡摆到桌宠正上方，尾巴尖对准桌宠头顶。拖动时同步调用。"""
        self._cx, self._top = center_x, top_y
        w, h = self.width(), self.height()
        x = int(center_x - w / 2)
        y = int(top_y - h + self.MARGIN)   # 尾巴尖(距窗口底 MARGIN)落在 top_y
        self.move(max(0, x), max(0, y))


# ----------------------------------------------------------------------------
# 桌宠窗口
# ----------------------------------------------------------------------------
class Pet(QWidget):
    def __init__(self, lines, bubble):
        super().__init__(None,
            Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool)
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.lines = lines
        self.bubble = bubble
        self.character = "lishen"
        self._movie = None
        self._star_movies = {}
        self._attached_edge = None
        self._drag_direction = None
        self._last_global_x = 0

        self.frames = []
        for i in range(6):
            pm = QPixmap(os.path.join(FRAME_DIR, f"frame_{i}.png"))
            if not pm.isNull():
                pm = pm.scaledToHeight(PET_HEIGHT, Qt.SmoothTransformation)
            self.frames.append(pm)
        w = max((f.width() for f in self.frames if not f.isNull()), default=160)
        self.resize(w, PET_HEIGHT)

        self.label = QLabel(self)
        self.label.resize(self.size())
        self._seq_i = 0
        self._set_frame(ANIM_SEQ[0])

        self.anim = QTimer(self)
        self.anim.timeout.connect(self._advance)
        self.anim.start(ANIM_MS[0])

        screen = QApplication.primaryScreen().availableGeometry()
        self.move(screen.right() - w - 40, screen.bottom() - PET_HEIGHT - 60)

        self._drag_pos = None
        self._moved = False

    def _star_movie(self, filename):
        movie = self._star_movies.get(filename)
        if movie is None:
            path = os.path.join(STAR_DIR, filename)
            if not os.path.exists(path):
                log_err(f"缺少星星动作素材: {path}")
                return None
            movie = QMovie(path)
            movie.setCacheMode(QMovie.CacheAll)
            self._star_movies[filename] = movie
        return movie

    def _resize_for_size(self, size):
        if size.isEmpty() or size.height() <= 0:
            return
        w = max(100, int(size.width() * PET_HEIGHT / size.height()))
        self.resize(w, PET_HEIGHT)
        self.label.resize(self.size())

    def _set_star_file(self, filename):
        movie = self._star_movie(filename)
        if movie is None:
            return
        if self._movie is not None:
            self._movie.stop()
        self._movie = movie
        movie.start()
        size = movie.frameRect().size()
        if size.isEmpty():
            size = QSize(PET_HEIGHT, PET_HEIGHT)
        movie.setScaledSize(QSize(max(100, int(size.width() * PET_HEIGHT / size.height())), PET_HEIGHT))
        self.label.setMovie(movie)
        self._resize_for_size(movie.scaledSize())

    def _set_star_action(self, category):
        files = STAR_ACTIONS.get(category) or STAR_ACTIONS["idle"]
        self._drag_direction = None
        self._set_star_file(random.choice(files))

    def _set_drag_action(self, direction):
        if self.character != "star" or self._drag_direction == direction:
            return
        self._drag_direction = direction
        self._set_star_file(STAR_DRAG_ACTIONS[direction])

    def _snap_to_edge(self, global_pos):
        screen = QApplication.screenAt(global_pos) or QApplication.primaryScreen()
        area = screen.availableGeometry()
        near_left = self.x() <= area.left() + 32
        near_right = self.x() + self.width() >= area.x() + area.width() - 32
        if not near_left and not near_right:
            return False
        center_x = self.x() + self.width() // 2
        area_center_x = area.x() + area.width() // 2
        direction = "left" if near_left and (not near_right or center_x <= area_center_x) else "right"
        self._set_drag_action(direction)
        x = area.left() if direction == "left" else area.x() + area.width() - self.width()
        y = max(area.top(), min(self.y(), area.y() + area.height() - self.height()))
        self.move(x, y)
        self._attached_edge = direction
        return True

    def set_character(self, character):
        if character not in ("star", "lishen"):
            return
        self.character = character
        self._attached_edge = None
        self._drag_direction = None
        if character == "star":
            self.anim.stop()
            self._set_star_action("idle")
            return
        if self._movie is not None:
            self._movie.stop()
            self._movie = None
        self.label.setMovie(None)
        w = max((f.width() for f in self.frames if not f.isNull()), default=160)
        self.resize(w, PET_HEIGHT)
        self.label.resize(self.size())
        self._seq_i = 0
        self._set_frame(ANIM_SEQ[0])
        self.anim.start(ANIM_MS[0])

    def set_category_action(self, category):
        if self.character == "star" and self._attached_edge is None:
            self._set_star_action(category)

    def _set_frame(self, idx):
        if 0 <= idx < len(self.frames) and not self.frames[idx].isNull():
            self.label.setPixmap(self.frames[idx])

    def _advance(self):
        try:
            if self.character != "lishen":
                return
            self._seq_i = (self._seq_i + 1) % len(ANIM_SEQ)
            self._set_frame(ANIM_SEQ[self._seq_i])
            self.anim.start(ANIM_MS[self._seq_i])
        except Exception:
            log_err("动画帧切换")

    def say(self, text):
        try:
            gx = self.x() + self.width() / 2
            gy = self.y() + 10
            self.bubble.show_text(text, gx, gy)
        except Exception:
            log_err("显示气泡")

    def say_category(self, cat):
        self.set_category_action(cat)
        self.say(self.lines.pick(cat, self.character))

    def mousePressEvent(self, e):
        if e.button() == Qt.LeftButton:
            self._drag_pos = e.globalPosition().toPoint() - self.frameGeometry().topLeft()
            self._moved = False
            self._last_global_x = e.globalPosition().toPoint().x()

    def mouseMoveEvent(self, e):
        if self._drag_pos is not None and (e.buttons() & Qt.LeftButton):
            new = e.globalPosition().toPoint() - self._drag_pos
            if (new - self.pos()).manhattanLength() > 3:
                self._moved = True
                self._attached_edge = None
            self.move(new)
            global_x = e.globalPosition().toPoint().x()
            if self.character == "star" and global_x != self._last_global_x:
                self._set_drag_action("left" if global_x < self._last_global_x else "right")
                self._last_global_x = global_x
            # 气泡若正显示，跟着人一起走
            if self.bubble.isVisible():
                self.bubble.reposition(self.x() + self.width() / 2,
                                       self.y() + 10)

    def mouseReleaseEvent(self, e):
        if e.button() == Qt.LeftButton:
            if not self._moved:
                category = "hanging" if self.character == "star" and self._attached_edge else "poke"
                self.say_category(category)
            elif self.character == "star" and not self._snap_to_edge(e.globalPosition().toPoint()):
                self._attached_edge = None
                self._set_star_action("idle")
            self._drag_pos = None


# ----------------------------------------------------------------------------
# 主控制器：托盘菜单 + 定时调度
# ----------------------------------------------------------------------------
class Controller:
    def __init__(self, app):
        self.app = app
        dbg("Controller: 读取台词库")
        self.lines = Lines(DATA_FILE)
        dbg("Controller: 创建气泡")
        self.bubble = Bubble()
        dbg("Controller: 创建桌宠")
        self.pet = Pet(self.lines, self.bubble)
        self.character = "star"
        self.character_name = "星星"
        self.pet.set_character(self.character)
        dbg("Controller: 显示桌宠")
        self.pet.show()
        self.reminders_on = True

        dbg("Controller: 创建托盘图标")
        icon_path = os.path.join(ASSET_DIR, "icon_256.png")
        self.tray = QSystemTrayIcon(QIcon(icon_path), app)
        self.tray.setToolTip("星星")
        dbg("Controller: 创建菜单")
        menu = QMenu()
        self.act_say = QAction("让角色说句话", app)
        self.act_say.triggered.connect(self.say_now)
        act_toggle = QAction("显示 / 隐藏桌宠", app)
        act_toggle.triggered.connect(self.toggle_pet)
        self.act_rem = QAction("暂停提醒", app)
        self.act_rem.triggered.connect(self.toggle_reminders)
        character_menu = QMenu("切换角色", menu)
        act_star = QAction("星星（默认）", app)
        act_lishen = QAction("黎深", app)
        act_star.triggered.connect(lambda: self.set_character("star"))
        act_lishen.triggered.connect(lambda: self.set_character("lishen"))
        character_menu.addAction(act_star)
        character_menu.addAction(act_lishen)
        act_quit = QAction("退出", app)
        act_quit.triggered.connect(app.quit)
        menu.addMenu(character_menu)
        menu.addSeparator()
        for a in (self.act_say, act_toggle, self.act_rem):
            menu.addAction(a)
        menu.addSeparator()
        menu.addAction(act_quit)
        self.tray.setContextMenu(menu)
        self.tray.activated.connect(self._tray_click)
        self._character_actions = {"star": act_star, "lishen": act_lishen}
        self.set_character("star")
        dbg("Controller: 显示托盘")
        self.tray.show()

        dbg("Controller: 安排开场问候")
        QTimer.singleShot(1500, lambda: self.pet.say_category("greeting"))

        self._fired = set()
        self._next_hourly = self._plan_hourly()
        self.sched = QTimer(app)
        self.sched.timeout.connect(self._tick)
        self.sched.start(30_000)
        dbg("Controller: 初始化完成")

    def set_character(self, character):
        if character not in ("star", "lishen"):
            return
        self.character = character
        self.character_name = "星星" if character == "star" else "黎深"
        self.pet.set_character(character)
        self.tray.setToolTip(self.character_name)
        for key, action in self._character_actions.items():
            action.setCheckable(True)
            action.setChecked(key == character)

    def _tray_click(self, reason):
        if reason == QSystemTrayIcon.Trigger:
            self.say_now()

    def say_now(self):
        try:
            h = datetime.now().hour
            if h == LUNCH_HOUR: cat = "lunch"
            elif h == DINNER_HOUR: cat = "dinner"
            elif h >= 23 or h < 6: cat = "night"
            else: cat = random.choice(["daily", "miss", "cheer"])
            if not self.pet.isVisible():
                self.pet.show()
            self.pet.say_category(cat)
        except Exception:
            log_err("手动说话")

    def toggle_pet(self):
        show = not self.pet.isVisible()
        self.pet.setVisible(show)
        if not show:                 # 隐藏桌宠时，气泡也一起收起
            self.bubble.hide()

    def toggle_reminders(self):
        self.reminders_on = not self.reminders_on
        self.act_rem.setText("暂停提醒" if self.reminders_on else "恢复提醒")

    def _plan_hourly(self):
        now = datetime.now()
        base = now.replace(minute=0, second=0, microsecond=0)
        nxt = base.timestamp() + 3600
        jitter = random.randint(-HOURLY_JITTER, HOURLY_JITTER) * 60
        return nxt + jitter

    def _speak(self, cat):
        if not self.pet.isVisible():
            self.pet.show()
        self.pet.set_category_action(cat)
        line = self.lines.pick(cat, self.character)
        self.pet.say(line)
        if NOTIFY_TOO and line:
            try:
                self.tray.showMessage(self.character_name, line, QSystemTrayIcon.NoIcon, 6000)
            except Exception:
                pass

    def _tick(self):
        try:
            if not self.reminders_on:
                return
            now = datetime.now()
            day = now.strftime("%Y%m%d")
            key = f"{day}-lunch"
            if now.hour == LUNCH_HOUR and now.minute < 30 and key not in self._fired:
                self._fired.add(key); self._speak("lunch"); return
            key = f"{day}-dinner"
            if now.hour == DINNER_HOUR and now.minute < 30 and key not in self._fired:
                self._fired.add(key); self._speak("dinner"); return
            key = f"{day}-night"
            if now.hour == NIGHT_HOUR and now.minute >= NIGHT_MINUTE and key not in self._fired:
                self._fired.add(key); self._speak("night"); return
            if time.time() >= self._next_hourly:
                self._next_hourly = self._plan_hourly()
                if 7 <= now.hour <= 23:
                    self._speak(random.choice(["daily", "miss", "cheer", "weather"]))
        except Exception:
            log_err("定时调度")


def main():
    # 捕获所有未处理异常（含 Qt 槽函数里的），写进日志，避免"闪退无痕"
    def hook(exctype, value, tb):
        msg = "\n[未捕获异常]\n" + "".join(traceback.format_exception(exctype, value, tb))
        try:
            with open(LOG_FILE, "a", encoding="utf-8") as f:
                f.write(msg)
        except Exception:
            pass
        print(msg)
    sys.excepthook = hook

    try:
        try:
            open(DBG_FILE, "w").close()   # 清空上次的 run.log
        except Exception:
            pass
        dbg("main: 启动 QApplication")
        app = QApplication(sys.argv)
        app.setQuitOnLastWindowClosed(False)
        if not QSystemTrayIcon.isSystemTrayAvailable():
            dbg("提示：系统托盘不可用，桌宠仍会显示。")
        dbg("main: 创建 Controller")
        ctrl = Controller(app)
        # 自检模式：设了环境变量 LISHEN_SELFTEST 就 3 秒后自动退出
        if os.environ.get("LISHEN_SELFTEST"):
            dbg("main: 自检模式，3 秒后自动退出")
            QTimer.singleShot(3000, app.quit)
        dbg("main: 进入事件循环 app.exec()")
        rc = app.exec()
        dbg(f"main: 事件循环结束 rc={rc}")
        sys.exit(rc)
    except SystemExit:
        raise
    except BaseException:
        log_err("启动")
        sys.exit(1)


if __name__ == "__main__":
    main()
