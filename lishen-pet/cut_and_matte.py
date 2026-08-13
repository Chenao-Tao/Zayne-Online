import cv2
import numpy as np
from PIL import Image
import os

BASE = "/sessions/bold-tender-cray/mnt/outputs/lishen-pet/assets"
FRAMES = os.path.join(BASE, "frames")
os.makedirs(FRAMES, exist_ok=True)

def remove_bg_edgewall(bgr):
    """Flood fill background from the border, using the character's dark outlines
    (Canny edges) as barrier walls so the pale-blue float/sofa is preserved."""
    h, w = bgr.shape[:2]
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)

    # Strong outline detection: chibi has bold dark lines.
    edges = cv2.Canny(gray, 40, 110)
    # also treat very dark pixels (black outlines/clothes edges) as walls
    dark = (gray < 90).astype(np.uint8) * 255
    walls = cv2.bitwise_or(edges, dark)
    walls = cv2.dilate(walls, np.ones((3, 3), np.uint8), iterations=2)

    # Build flood-fill mask: barriers = walls (non-zero blocks the fill)
    mask = np.zeros((h + 2, w + 2), np.uint8)
    mask[1:-1, 1:-1][walls > 0] = 1

    # Seed a 1px border frame of background points around the edges
    img = bgr.copy()
    flags = 4 | (255 << 8) | cv2.FLOODFILL_MASK_ONLY
    seeds = []
    step = 20
    for x in range(0, w, step):
        seeds += [(x, 0), (x, h - 1)]
    for y in range(0, h, step):
        seeds += [(0, y), (w - 1, y)]
    for (sx, sy) in seeds:
        if mask[sy + 1, sx + 1] == 0:  # only seed on non-wall bg
            cv2.floodFill(img, mask, (sx, sy), 255, (30, 30, 30), (30, 30, 30), flags)

    filled = (mask[1:-1, 1:-1] == 255)  # reachable background
    alpha = np.where(filled, 0, 255).astype(np.uint8)

    # The walls were excluded from fill; keep them as part of foreground.
    # Fill small holes inside the character, then keep large components.
    alpha = cv2.morphologyEx(alpha, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8), 1)

    num, labels, stats, _ = cv2.connectedComponentsWithStats(alpha, connectivity=8)
    keep = np.zeros_like(alpha)
    for i in range(1, num):
        if stats[i, cv2.CC_STAT_AREA] > 4000:
            keep[labels == i] = 255
    alpha = keep

    # Erode by 1 to shave residual bg halo, then feather
    alpha = cv2.erode(alpha, np.ones((3, 3), np.uint8), 1)
    alpha = cv2.GaussianBlur(alpha, (3, 3), 0)

    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    return np.dstack([rgb, alpha])

sheet = cv2.imread(os.path.join(BASE, "spritesheet.jpg"))
H, W = sheet.shape[:2]
cols, rows = 2, 3
cw, ch = W // cols, H // rows
order = [(0,0),(0,1),(1,1),(1,0),(2,0),(2,1)]
for n, (r, c) in enumerate(order):
    cell = sheet[r*ch:(r+1)*ch, c*cw:(c+1)*cw]
    rgba = remove_bg_edgewall(cell)
    out = Image.fromarray(rgba, "RGBA")
    bbox = out.getbbox()
    if bbox:
        pad = 10
        l, t, rr, bb = bbox
        out = out.crop((max(0,l-pad), max(0,t-pad),
                        min(out.width,rr+pad), min(out.height,bb+pad)))
    out.save(os.path.join(FRAMES, f"frame_{n}.png"))
    print(f"frame_{n}.png cell({r},{c}) {out.size}")
print("done")
