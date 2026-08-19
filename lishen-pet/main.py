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

import sys, os, json, random, time, traceback, math
from collections import deque, defaultdict
from datetime import datetime

from PySide6.QtCore import Qt, QTimer, QRect, QRectF, QSize, QProcess
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
APPLE_FILE = os.path.join(ASSET_DIR, "apple.png")
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
NOTIFY_TOO      = False   # 除了气泡，是否同时发系统通知
THROW_SPEED_PX  = 1450    # 快速甩飞的速度阈值(像素/秒)
THROW_WAIT_SEC  = 4       # 甩飞后多久回来
ANGRY_SEC       = 12      # 回来后生气多久
THROW_TICK_MS    = 16      # 甩飞动画刷新间隔
THROW_PAD_PX     = 180     # 甩出屏幕外的余量
FEED_SEC        = 8       # 喂食动作停留时间
APPLE_SIZE_PX   = 86      # 苹果显示尺寸
APPLE_FEED_RANGE = 110    # 苹果送到星星附近的判定范围
APPLE_TIMEOUT_SEC = 20    # 苹果未送达的保留时间
THROW_SENSITIVITY_LEVELS = [
    ("高灵敏度", 1100),
    ("标准", 1450),
    ("低灵敏度", 1800),
]

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
    "feed": ["沈星回喵：饿了.gif", "沈星回喵：嚼嚼嚼.gif", "沈星回喵：吃撑了.gif"],
    "angry": ["沈星回喵：糟糕.gif"],
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
# 苹果：喂食用的可拖动小物件
# ----------------------------------------------------------------------------
class Apple(QWidget):
    def __init__(self, controller):
        super().__init__(None, Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool)
        self.controller = controller
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setAttribute(Qt.WA_ShowWithoutActivating)
        self._pixmap = QPixmap(APPLE_FILE)
        if self._pixmap.isNull():
            log_err(f"缺少苹果素材: {APPLE_FILE}")
        else:
            self._pixmap = self._pixmap.scaled(APPLE_SIZE_PX, APPLE_SIZE_PX, Qt.KeepAspectRatio, Qt.SmoothTransformation)
        size = self._pixmap.size() if not self._pixmap.isNull() else QSize(APPLE_SIZE_PX, APPLE_SIZE_PX)
        self.resize(size)
        self._drag_pos = None
        self._moved = False
        self._life = QTimer(self)
        self._life.setSingleShot(True)
        self._life.timeout.connect(self.hide_apple)
        self.hide()

    def paintEvent(self, _):
        try:
            if self._pixmap.isNull():
                return
            p = QPainter(self)
            p.setRenderHint(QPainter.Antialiasing, True)
            p.drawPixmap(self.rect(), self._pixmap)
        except Exception:
            log_err("苹果绘制")

    def drop_from_pet(self, pet):
        if pet is None:
            return
        screen = QApplication.screenAt(pet.mapToGlobal(pet.rect().center())) or QApplication.primaryScreen()
        area = screen.availableGeometry()
        x = int(pet.x() + pet.width() * 0.5 - self.width() * 0.5 + random.randint(-22, 22))
        y = int(pet.y() - self.height() + 10)
        x = max(area.left(), min(x, area.right() - self.width()))
        y = max(area.top(), min(y, area.bottom() - self.height()))
        self.move(x, y)
        self._drag_pos = None
        self._moved = False
        self._life.stop()
        self.show()
        self.raise_()
        self._life.start(APPLE_TIMEOUT_SEC * 1000)

    def hide_apple(self):
        self._life.stop()
        self._drag_pos = None
        self._moved = False
        self.hide()

    def mousePressEvent(self, e):
        if e.button() == Qt.LeftButton:
            self.controller.mark_interaction()
            self._drag_pos = e.globalPosition().toPoint() - self.frameGeometry().topLeft()
            self._moved = False

    def mouseMoveEvent(self, e):
        if self._drag_pos is not None and (e.buttons() & Qt.LeftButton):
            new = e.globalPosition().toPoint() - self._drag_pos
            if (new - self.pos()).manhattanLength() > 3:
                self._moved = True
            self.move(new)

    def mouseReleaseEvent(self, e):
        if e.button() == Qt.LeftButton:
            if self._moved:
                self.controller.feed_from_apple(self)
            self._drag_pos = None


# ----------------------------------------------------------------------------
# 桌宠窗口
# ----------------------------------------------------------------------------
class Pet(QWidget):
    def __init__(self, lines, bubble, on_interaction=None, on_click_combo=None, on_throw=None):
        super().__init__(None,
            Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool)
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.lines = lines
        self.bubble = bubble
        self.on_interaction = on_interaction
        self.on_click_combo = on_click_combo
        self.on_throw = on_throw
        self.character = "lishen"
        self._movie = None
        self._star_movies = {}
        self._attached_edge = None
        self._drag_direction = None
        self._state_action = None
        self._last_global_x = 0
        self._click_count = 0
        self._last_click_at = 0
        self._drag_start_at = 0
        self._drag_start_pos = None
        self._drag_last_at = 0
        self._drag_last_pos = None

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
        self._drag_last_pos = None
        self._drag_last_at = 0

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
        self._state_action = None
        self._drag_start_at = 0
        self._drag_start_pos = None
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
            if self._state_action is not None and category != self._state_action:
                return
            self._set_star_action(category)

    def set_state_action(self, action):
        self._state_action = action

    def is_hanging(self):
        return self.character == "star" and self._attached_edge in ("left", "right")

    def set_click_through(self, enabled):
        was_visible = self.isVisible()
        position = self.pos()
        self.setWindowFlag(Qt.WindowTransparentForInput, enabled)
        if was_visible:
            self.show()
            self.move(position)

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
            if self.on_interaction:
                self.on_interaction()
            self._drag_start_at = time.time()
            self._drag_start_pos = e.globalPosition().toPoint()
        self._drag_pos = e.globalPosition().toPoint() - self.frameGeometry().topLeft()
        self._moved = False
        self._last_global_x = e.globalPosition().toPoint().x()
        self._drag_last_pos = self._drag_start_pos
        self._drag_last_at = self._drag_start_at

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
            self._drag_last_pos = e.globalPosition().toPoint()
            self._drag_last_at = time.time()
            # 气泡若正显示，跟着人一起走
            if self.bubble.isVisible():
                self.bubble.reposition(self.x() + self.width() / 2,
                                       self.y() + 10)

    def mouseReleaseEvent(self, e):
        if e.button() == Qt.LeftButton:
            if not self._moved:
                now = time.time()
                self._click_count = self._click_count + 1 if now - self._last_click_at <= 4 else 1
                self._last_click_at = now
                if not self.is_hanging() and self._click_count >= 5 and self.on_click_combo:
                    self._click_count = 0
                    self.on_click_combo()
                    self._drag_pos = None
                    self._drag_start_pos = None
                    self._drag_start_at = 0
                    self._drag_last_pos = None
                    self._drag_last_at = 0
                    return
                if self._state_action == "feed":
                    category = "feed"
                else:
                    category = "hanging" if self.character == "star" and self._attached_edge else "poke"
                self.say_category(category)
            elif self.character == "star":
                release_pos = e.globalPosition().toPoint()
                if self._drag_start_pos is not None and self._drag_start_at:
                    drag_start_pos = self._drag_start_pos
                    sample_pos = self._drag_last_pos or drag_start_pos
                    sample_at = self._drag_last_at or self._drag_start_at
                    elapsed = max(time.time() - sample_at, 0.001)
                    dx = release_pos.x() - drag_start_pos.x()
                    dy = release_pos.y() - drag_start_pos.y()
                    recent_dx = release_pos.x() - sample_pos.x()
                    recent_dy = release_pos.y() - sample_pos.y()
                    drag_distance = math.hypot(dx, dy)
                    recent_distance = math.hypot(recent_dx, recent_dy)
                    average_speed = drag_distance / max(time.time() - self._drag_start_at, 0.001)
                    recent_speed = recent_distance / elapsed
                    speed = max(recent_speed, average_speed * 0.7)
                    if (self.on_throw and not self.is_hanging() and
                            speed >= self.throw_speed_px and drag_distance >= 160 and recent_distance >= 40):
                        direction = "left" if dx < 0 else "right"
                        self._drag_pos = None
                        self._drag_start_pos = None
                        self._drag_start_at = 0
                        self._drag_last_pos = None
                        self._drag_last_at = 0
                        if self.on_throw(direction, drag_start_pos, release_pos, speed):
                            return
                drag_category = f"drag_{self._drag_direction}" if self._drag_direction in ("left", "right") else None
                snapped = self._snap_to_edge(release_pos)
                if drag_category is None and self._drag_direction in ("left", "right"):
                    drag_category = f"drag_{self._drag_direction}"
                if not snapped:
                    self._attached_edge = None
                    self._set_star_action(self._state_action or "idle")
                if drag_category:
                    self.say_category(drag_category)
            self._drag_pos = None
            self._drag_start_pos = None
            self._drag_start_at = 0
            self._drag_last_pos = None
            self._drag_last_at = 0


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
        self.pet = Pet(self.lines, self.bubble, self.mark_interaction, self.celebrate_clicks, self.throw_pet)
        self.apple = Apple(self)
        self.character = "star"
        self.character_name = "星星"
        self.pet.set_character(self.character)
        dbg("Controller: 显示桌宠")
        self.pet.show()
        self.reminders_on = True
        self.pet_state = "normal"
        self.state_until = None
        self.last_interaction = time.time()
        self.click_through = False
        self.throw_origin = None
        self.throw_motion = None
        self.throw_speed_px = THROW_SPEED_PX

        dbg("Controller: 创建托盘图标")
        icon_path = os.path.join(ASSET_DIR, "icon_256.png")
        self.tray = QSystemTrayIcon(QIcon(icon_path), app)
        self.tray.setToolTip("星星")
        dbg("Controller: 创建菜单")
        menu = QMenu()
        self.act_say = QAction("让角色说句话", app)
        self.act_say.triggered.connect(self.say_now)
        self.act_feed = QAction("喂食苹果", app)
        self.act_feed.triggered.connect(self.drop_apple)
        act_toggle = QAction("显示 / 隐藏桌宠", app)
        act_toggle.triggered.connect(self.toggle_pet)
        self.act_rem = QAction("暂停提醒", app)
        self.act_rem.triggered.connect(self.toggle_reminders)
        self.state_menu = QMenu("状态：普通", menu)
        act_focus = QAction("开始专注（25 分钟）", app)
        act_focus.triggered.connect(self.start_focus)
        act_complete = QAction("完成一件事", app)
        act_complete.triggered.connect(self.complete_task)
        act_idle = QAction("陪我发呆", app)
        act_idle.triggered.connect(self.idle_together)
        act_normal = QAction("恢复普通状态", app)
        act_normal.triggered.connect(self.restore_normal)
        self.state_menu.addAction(act_focus)
        self.state_menu.addAction(act_complete)
        self.state_menu.addAction(act_idle)
        self.state_menu.addSeparator()
        self.state_menu.addAction(act_normal)
        opacity_menu = QMenu("透明度", menu)
        self._opacity_actions = {}
        for percent in (100, 80, 60, 40):
            action = QAction(f"{percent}%", app)
            action.setCheckable(True)
            action.triggered.connect(lambda checked=False, value=percent: self.set_opacity(value))
            opacity_menu.addAction(action)
            self._opacity_actions[percent] = action
        self._opacity_actions[100].setChecked(True)
        self.act_click_through = QAction("鼠标穿透（从托盘关闭）", app)
        self.act_click_through.setCheckable(True)
        self.act_click_through.toggled.connect(self.set_click_through)
        throw_menu = QMenu("触发门槛", menu)
        self._throw_speed_actions = {}
        for label, speed_px in THROW_SENSITIVITY_LEVELS:
            action = QAction(label, app)
            action.setCheckable(True)
            action.triggered.connect(lambda checked=False, value=speed_px: self.set_throw_sensitivity(value))
            throw_menu.addAction(action)
            self._throw_speed_actions[speed_px] = action
        self._throw_speed_actions[self.throw_speed_px].setChecked(True)
        character_menu = QMenu("切换角色", menu)
        act_star = QAction("星星（默认）", app)
        act_lishen = QAction("黎深", app)
        act_star.triggered.connect(lambda: self.set_character("star"))
        act_lishen.triggered.connect(lambda: self.set_character("lishen"))
        character_menu.addAction(act_star)
        character_menu.addAction(act_lishen)
        act_quit = QAction("退出", app)
        act_quit.triggered.connect(app.quit)
        act_restart = QAction("重启桌宠", app)
        act_restart.triggered.connect(self.restart)
        menu.addMenu(character_menu)
        menu.addSeparator()
        menu.addAction(self.act_say)
        menu.addAction(self.act_feed)
        menu.addMenu(self.state_menu)
        menu.addMenu(opacity_menu)
        menu.addMenu(throw_menu)
        for a in (self.act_click_through, act_toggle, self.act_rem):
            menu.addAction(a)
        menu.addSeparator()
        menu.addAction(act_restart)
        menu.addAction(act_quit)
        self.tray.setContextMenu(menu)
        self.tray.activated.connect(self._tray_click)
        self._character_actions = {"star": act_star, "lishen": act_lishen}
        self._throw_speed_menu = throw_menu
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
        self.state_timer = QTimer(app)
        self.state_timer.timeout.connect(self.update_state)
        self.state_timer.start(30_000)
        self.throw_timer = QTimer(app)
        self.throw_timer.setInterval(THROW_TICK_MS)
        self.throw_timer.timeout.connect(self.update_throw_motion)
        dbg("Controller: 初始化完成")

    def set_character(self, character):
        if character not in ("star", "lishen"):
            return
        self.character = character
        self.character_name = "星星" if character == "star" else "黎深"
        self.pet_state = "normal"
        self.state_until = None
        self.throw_origin = None
        self.throw_motion = None
        self.throw_timer.stop()
        self._drag_last_pos = None
        self._drag_last_at = 0
        self.pet.set_state_action(None)
        self.pet.set_character(character)
        self.hide_apple()
        self.act_feed.setEnabled(character == "star")
        self._throw_speed_menu.setEnabled(character == "star")
        if not self.pet.isVisible():
            self.pet.show()
        self.tray.setToolTip(self.character_name)
        self.update_state_title()
        for key, action in self._character_actions.items():
            action.setCheckable(True)
            action.setChecked(key == character)

    def _tray_click(self, reason):
        if reason == QSystemTrayIcon.Trigger:
            self.say_now()

    def mark_interaction(self):
        self.last_interaction = time.time()

    def _clamp(self, value, low, high):
        return max(low, min(value, high))

    def _ease_out_cubic(self, t):
        return 1 - pow(1 - t, 2)

    def _ease_in_cubic(self, t):
        return t * t

    def _cubic_point(self, p0, p1, p2, p3, t):
        u = 1 - t
        uu = u * u
        tt = t * t
        uuu = uu * u
        ttt = tt * t
        x = (uuu * p0[0] + 3 * uu * t * p1[0] +
             3 * u * tt * p2[0] + ttt * p3[0])
        y = (uuu * p0[1] + 3 * uu * t * p1[1] +
             3 * u * tt * p2[1] + ttt * p3[1])
        return x, y

    def _build_throw_motion(self, direction, start_pos, release_pos, speed):
        screen = QApplication.screenAt(release_pos) or QApplication.primaryScreen()
        area = screen.availableGeometry()
        origin = (float(self.pet.x()), float(self.pet.y()))
        width = float(self.pet.width())
        height = float(self.pet.height())
        start_center = (origin[0] + width / 2, origin[1] + height / 2)
        delta_x = release_pos.x() - start_pos.x()
        delta_y = release_pos.y() - start_pos.y()
        drag_len = max(math.hypot(delta_x, delta_y), 1.0)
        force = self._clamp((speed - self.throw_speed_px) / 1800.0, 0.0, 1.0)
        exit_pad = THROW_PAD_PX + min(130, 30 + drag_len * 0.06 + force * 90)
        target_x = (area.left() - width - exit_pad) if direction == "left" else (area.right() + width + exit_pad)
        target_y = self._clamp(
            start_center[1] + delta_y * 0.36 - (force * 35),
            area.top() + height / 2,
            area.bottom() - height / 2,
        )
        arc = 70 + force * 95 + min(64, drag_len * 0.07)
        dx = target_x - start_center[0]
        p0 = start_center
        p3 = (target_x, target_y)
        p1 = (start_center[0] + dx * 0.26, start_center[1] - arc)
        p2 = (start_center[0] + dx * 0.72, target_y - arc * 0.48)
        launch_ms = int(self._clamp(560 - force * 150 - min(120, drag_len * 0.05), 300, 560))
        return {
            "origin": origin,
            "start_center": start_center,
            "target": p3,
            "control1": p1,
            "control2": p2,
            "launch_ms": launch_ms,
            "return_ms": max(launch_ms + 120, int(launch_ms * 1.22)),
            "wait_until": time.time() + THROW_WAIT_SEC,
            "start_at": time.time(),
            "phase": "launch",
            "force": force,
        }

    def update_throw_motion(self):
        motion = self.throw_motion
        if not motion:
            self.throw_timer.stop()
            return
        now = time.time()
        if motion["phase"] == "launch":
            t = self._clamp((now - motion["start_at"]) * 1000 / motion["launch_ms"], 0.0, 1.0)
            t = self._ease_out_cubic(t)
            x, y = self._cubic_point(motion["start_center"], motion["control1"], motion["control2"], motion["target"], t)
            self.pet.move(int(x - self.pet.width() / 2), int(y - self.pet.height() / 2))
            if t >= 1.0:
                motion["phase"] = "wait"
                motion["wait_until"] = now + THROW_WAIT_SEC
                self.throw_motion = motion
            return
        if motion["phase"] == "wait":
            if now < motion["wait_until"]:
                return
            motion["phase"] = "return"
            motion["start_at"] = now
            motion["return_start"] = motion["target"]
            motion["return_c1"] = motion["control2"]
            motion["return_c2"] = motion["control1"]
            self.throw_motion = motion
            self.pet.show()
            return
        if motion["phase"] == "return":
            t = self._clamp((now - motion["start_at"]) * 1000 / motion["return_ms"], 0.0, 1.0)
            t = self._ease_in_cubic(t)
            x, y = self._cubic_point(motion["target"], motion["return_c1"], motion["return_c2"], motion["start_center"], t)
            self.pet.move(int(x - self.pet.width() / 2), int(y - self.pet.height() / 2))
            if t >= 1.0:
                self.throw_motion = None
                self.throw_timer.stop()
                self._finish_throw_return()

    def update_state_title(self):
        names = {
            "normal": "普通",
            "focus": "专注中",
            "idle": "陪你发呆",
            "celebrate": "庆祝",
            "feed": "喂食中",
            "angry": "生气中",
            "thrown": "飞出去",
        }
        self.state_menu.setTitle(f"状态：{names.get(self.pet_state, self.pet_state)}")

    def set_pet_state(self, state, action="idle", seconds=None):
        if self.pet.is_hanging() or self.pet_state == "thrown":
            return False
        self.pet_state = state
        self.state_until = time.time() + seconds if seconds else None
        self.last_interaction = time.time()
        self.pet.set_state_action(None if state == "normal" else action)
        self.pet.set_category_action(action)
        if state not in ("normal", "feed"):
            self.hide_apple()
        self.update_state_title()
        return True

    def set_throw_sensitivity(self, speed_px):
        allowed = {value for _, value in THROW_SENSITIVITY_LEVELS}
        if speed_px not in allowed:
            return
        self.throw_speed_px = speed_px
        for value, action in self._throw_speed_actions.items():
            action.setChecked(value == speed_px)
        dbg(f"触发门槛：{speed_px}")

    def hide_apple(self):
        if self.apple is not None:
            self.apple.hide_apple()

    def drop_apple(self):
        if self.character != "star" or self.pet_state != "normal" or self.pet.is_hanging():
            return
        self.apple.drop_from_pet(self.pet)
        self.pet.say("苹果掉出来了，拖给我吧。")

    def throw_pet(self, direction, drag_start_pos, release_pos, speed):
        if self.pet.is_hanging() or self.pet_state in ("thrown", "angry", "feed"):
            return False
        self.throw_origin = self.pet.pos()
        self.pet_state = "thrown"
        self.state_until = time.time() + THROW_WAIT_SEC
        self.last_interaction = time.time()
        self.pet.set_state_action(None)
        self.pet.show()
        self.pet.raise_()
        self.bubble.hide()
        self.throw_motion = self._build_throw_motion(direction, drag_start_pos, release_pos, speed)
        self.throw_motion["origin"] = (float(self.throw_origin.x()), float(self.throw_origin.y()))
        self.throw_motion["start_center"] = (
            float(self.throw_origin.x() + self.pet.width() / 2),
            float(self.throw_origin.y() + self.pet.height() / 2),
        )
        self.update_state_title()
        dbg(f"甩飞：{direction}")
        self.throw_timer.start()
        return True

    def _finish_throw_return(self):
        if self.pet_state != "thrown":
            return
        if self.throw_origin is not None:
            self.pet.move(self.throw_origin)
        self.pet_state = "angry"
        self.state_until = time.time() + ANGRY_SEC
        self.last_interaction = time.time()
        self.pet.set_state_action("angry")
        self.pet.set_category_action("angry")
        self.pet.say("哼，刚才那一下我记住了。")
        self.update_state_title()
        self.throw_origin = None
        self._drag_last_pos = None
        self._drag_last_at = 0
        QTimer.singleShot(ANGRY_SEC * 1000, lambda: self.pet_state == "angry" and self.restore_normal())

    def start_focus(self):
        if self.set_pet_state("focus", "idle", 25 * 60):
            self.pet.say("开始专注。我会安静陪着你。")

    def complete_task(self):
        if self.set_pet_state("celebrate", "cheer", 12):
            self.pet.say("完成得很好。这次值得庆祝一下。")

    def celebrate_clicks(self):
        if self.set_pet_state("celebrate", "cheer", 10):
            self.pet.say("今天很有精神嘛。奖励一段舞。")

    def feed_pet(self):
        self.drop_apple()

    def feed_from_apple(self, apple):
        if apple is None or self.pet.is_hanging() or self.pet_state in ("thrown", "angry", "feed"):
            return False
        if not apple.isVisible():
            return False
        apple_center_x = apple.x() + apple.width() / 2
        apple_center_y = apple.y() + apple.height() / 2
        pet_center_x = self.pet.x() + self.pet.width() / 2
        pet_center_y = self.pet.y() + self.pet.height() / 2
        if abs(apple_center_x - pet_center_x) > APPLE_FEED_RANGE or abs(apple_center_y - pet_center_y) > APPLE_FEED_RANGE:
            return False
        if self.set_pet_state("feed", "feed", FEED_SEC):
            apple.hide_apple()
            self.pet.say_category("feed")
            return True
        return False

    def idle_together(self):
        if self.set_pet_state("idle", "idle"):
            self.pet.say("好，我们一起安静待一会儿。")

    def restore_normal(self):
        self.throw_origin = None
        self.throw_motion = None
        self.throw_timer.stop()
        self._drag_last_pos = None
        self._drag_last_at = 0
        self.hide_apple()
        self.set_pet_state("normal", "idle")

    def set_opacity(self, percent):
        self.pet.setWindowOpacity(percent / 100)
        for value, action in self._opacity_actions.items():
            action.setChecked(value == percent)

    def set_click_through(self, enabled):
        self.click_through = enabled
        self.pet.set_click_through(enabled)

    def update_state(self):
        if self.pet.is_hanging():
            return
        now = time.time()
        if self.pet_state == "thrown":
            return
        if self.pet_state == "angry":
            return
        if self.state_until and now >= self.state_until:
            if self.pet_state == "focus":
                if self.set_pet_state("celebrate", "cheer", 12):
                    self.pet.say("专注结束。完成得很好。")
            else:
                self.restore_normal()
            return
        if self.pet_state != "normal":
            return
        idle_minutes = (now - self.last_interaction) / 60
        if idle_minutes >= 20:
            self.pet.set_category_action("night")
        elif idle_minutes >= 10:
            self.pet.set_category_action("idle")

    def restart(self):
        try:
            started = QProcess.startDetached(sys.executable, [os.path.abspath(__file__)], APP_DIR)
            if isinstance(started, tuple):
                started = started[0]
            if not started:
                raise RuntimeError("无法启动新的桌宠进程")
            self.app.quit()
        except Exception:
            log_err("重启桌宠")

    def say_now(self):
        try:
            if self.pet_state == "thrown":
                return
            h = datetime.now().hour
            if self.pet_state == "feed":
                cat = "feed"
            elif self.pet_state == "angry":
                cat = "angry"
            elif h == LUNCH_HOUR: cat = "lunch"
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
            self.hide_apple()

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
        if self.pet_state == "thrown":
            return
        if self.pet_state == "feed":
            cat = "feed"
        if self.pet_state == "angry":
            cat = "angry"
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
