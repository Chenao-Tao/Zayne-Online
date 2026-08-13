import cv2
import numpy as np
from PIL import Image
import os

BASE = "/sessions/bold-tender-cray/mnt/outputs/lishen-pet/assets"
FRAMES = os.path.join(BASE, "frames")

def remove_bg_edgewall(bgr):
    h, w = bgr.shape[:2]
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 40, 110)
    dark = (gray < 90).astype(np.uint8) * 255
    walls = cv2.bitwise_or(edges, dark)
    walls = cv2.dilate(walls, np.ones((3, 3), np.uint8), iterations=2)
    mask = np.zeros((h + 2, w + 2), np.uint8)
    mask[1:-1, 1:-1][walls > 0] = 1
    img = bgr.copy()
    flags = 4 | (255 << 8) | cv2.FLOODFILL_MASK_ONLY
    seeds = []
    for x in range(0, w, 20): seeds += [(x, 0), (x, h - 1)]
    for y in range(0, h, 20): seeds += [(0, y), (w - 1, y)]
    for (sx, sy) in seeds:
        if mask[sy + 1, sx + 1] == 0:
            cv2.floodFill(img, mask, (sx, sy), 255, (30,30,30), (30,30,30), flags)
    filled = (mask[1:-1, 1:-1] == 255)
    alpha = np.where(filled, 0, 255).astype(np.uint8)
    alpha = cv2.morphologyEx(alpha, cv2.MORPH_CLOSE, np.ones((5,5), np.uint8), 1)
    num, labels, stats, _ = cv2.connectedComponentsWithStats(alpha, 8)
    keep = np.zeros_like(alpha)
    for i in range(1, num):
        if stats[i, cv2.CC_STAT_AREA] > 4000:
            keep[labels == i] = 255
    alpha = keep
    alpha = cv2.erode(alpha, np.ones((3,3), np.uint8), 1)
    alpha = cv2.GaussianBlur(alpha, (3,3), 0)
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    return np.dstack([rgb, alpha])

sheet = cv2.imread(os.path.join(BASE, "spritesheet.jpg"))
H, W = sheet.shape[:2]
cols, rows = 2, 3
cw, ch = W // cols, H // rows
order = [(0,0),(0,1),(1,1),(1,0),(2,0),(2,1)]

# 1) matte every cell at full (aligned) size
rgbas = []
for (r, c) in order:
    cell = sheet[r*ch:(r+1)*ch, c*cw:(c+1)*cw]
    rgbas.append(remove_bg_edgewall(cell))

# 2) union bounding box across all frames (keeps alignment)
l0, t0, r0, b0 = cw, ch, 0, 0
for rgba in rgbas:
    a = rgba[:, :, 3]
    ys, xs = np.where(a > 20)
    if len(xs):
        l0 = min(l0, xs.min()); r0 = max(r0, xs.max())
        t0 = min(t0, ys.min()); b0 = max(b0, ys.max())
pad = 14
l0 = max(0, l0 - pad); t0 = max(0, t0 - pad)
r0 = min(cw, r0 + pad); b0 = min(ch, b0 + pad)
print("union bbox", (l0, t0, r0, b0), "->", (r0 - l0, b0 - t0))

# 3) save aligned frames
frames_img = []
for n, rgba in enumerate(rgbas):
    out = Image.fromarray(rgba, "RGBA").crop((l0, t0, r0, b0))
    out.save(os.path.join(FRAMES, f"frame_{n}.png"))
    frames_img.append(out)
print("aligned frame size", frames_img[0].size)

# 4) build a gentle looping GIF.
# expression sequence with hold durations (ms). natural idle loop:
# calm(hold) -> surprise -> eyes-open -> content -> half -> sweat -> back
seq = [0, 0, 1, 3, 2, 4, 5, 0]
durations = [1400, 200, 500, 700, 900, 700, 600, 400]
gif_frames = [frames_img[i] for i in seq]

# GIF needs a matte color for transparency; use a color unlikely in art (magenta)
def flatten_for_gif(im, bg=(255, 0, 255)):
    b = Image.new("RGBA", im.size, bg + (255,))
    b.alpha_composite(im)
    p = b.convert("RGB").convert("P", palette=Image.ADAPTIVE, colors=255)
    # set transparency index to the matte color
    return p

# For crisp transparency, export via Pillow with disposal + transparency
pal_frames = []
transp_index = 255
for im in gif_frames:
    b = Image.new("RGBA", im.size, (255, 0, 255, 255))
    b.alpha_composite(im)
    p = b.convert("RGB").quantize(colors=255, method=Image.MEDIANCUT)
    # ensure magenta maps to a reserved index
    pal_frames.append(p)

pal_frames[0].save(
    os.path.join(BASE, "lishen.gif"),
    save_all=True, append_images=pal_frames[1:],
    duration=durations, loop=0, disposal=2, transparency=0, optimize=False,
)
print("gif saved (note: gif transparency is approximate)")

# 5) ALSO save a transparent WEBP animation (better alpha) + keep PNG frames
try:
    frames_img[0].save(
        os.path.join(BASE, "lishen.webp"),
        save_all=True,
        append_images=[frames_img[i] for i in seq[1:]],
        duration=durations, loop=0, allow_mixed=True, lossless=True,
    )
    print("webp animation saved (true alpha)")
except Exception as e:
    print("webp failed:", e)
