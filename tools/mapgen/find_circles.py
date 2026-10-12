"""Find the white numbered region-marker circles on a Bloodstones key map.

Usage: python find_circles.py map.png out.json [--crop x0,y0,x1,y1]

Writes a list of {cx, cy, r} in full-image pixel coordinates. Numbers are
assigned in a separate step (OCR + manual review), since the region numbers
are vector glyphs, not text.
"""
import json
import sys

import cv2
import numpy as np


def find_circles(img, crop=None):
    x0, y0 = 0, 0
    if crop:
        x0, y0, x1, y1 = crop
        img = img[y0:y1, x0:x1]
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    # near-white: low saturation, high value
    white = ((hsv[..., 1] < 40) & (hsv[..., 2] > 225)).astype(np.uint8) * 255
    # fill in the dark numeral strokes inside each circle
    white = cv2.morphologyEx(white, cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8))
    n, lab, stats, cents = cv2.connectedComponentsWithStats(white)
    out = []
    for i in range(1, n):
        x, y, w, h, area = stats[i]
        if area < 1500 or area > 12000:
            continue
        if not (0.75 < w / h < 1.33):
            continue
        fill = area / (np.pi * (w / 2) * (h / 2))
        if fill < 0.8:
            continue
        cx, cy = cents[i]
        out.append({"cx": float(cx + x0), "cy": float(cy + y0), "r": float((w + h) / 4)})
    return out


if __name__ == "__main__":
    img = cv2.imread(sys.argv[1])
    crop = None
    if "--crop" in sys.argv:
        crop = [int(v) for v in sys.argv[sys.argv.index("--crop") + 1].split(",")]
    circles = find_circles(img, crop)
    json.dump(circles, open(sys.argv[2], "w"), indent=1)
    print(len(circles), "circles")
