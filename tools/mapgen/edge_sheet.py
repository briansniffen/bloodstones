"""Contact sheet of candidate edges, each cropped at the shared border.

Usage: python edge_sheet.py map.png labels.png edges.json out.png [max_len] [a-b ...]
Blue tint = first region, yellow tint = second, red = shared boundary.
"""
import json
import sys

import cv2
import numpy as np

img = cv2.imread(sys.argv[1])
L = cv2.imread(sys.argv[2], -1).astype(int)
edges = sorted(json.load(open(sys.argv[3])), key=lambda x: x["len"])
max_len = int(sys.argv[5]) if len(sys.argv) > 5 else 130
extra = {tuple(int(v) for v in p.split("-")) for p in sys.argv[6:]}
edges = [e for e in edges if e["len"] < max_len or (e["a"], e["b"]) in extra][:48]
cell, cols, H = 230, 8, 130
rows = (len(edges) + cols - 1) // cols
sheet = np.full((rows * (cell + 26), cols * cell, 3), 255, np.uint8)
pad = cv2.copyMakeBorder(img, H, H, H, H, cv2.BORDER_CONSTANT, value=(255, 255, 255))
Lp = np.pad(L, H)
k = np.ones((5, 5), np.uint8)
for i, e in enumerate(edges):
    a, b = e["a"], e["b"]
    ma, mb = (Lp == a), (Lp == b)
    bd = cv2.dilate(ma.astype(np.uint8), k).astype(bool) & cv2.dilate(mb.astype(np.uint8), k).astype(bool)
    ys, xs = np.nonzero(bd)
    cy, cx = int(ys.mean()), int(xs.mean())
    sl = (slice(cy - H, cy + H), slice(cx - H, cx + H))
    p = pad[sl].copy()
    for msk, col in ((ma[sl], (255, 120, 0)), (mb[sl], (0, 220, 255))):
        p[msk] = (p[msk] * 0.7 + np.array(col) * 0.3).astype(np.uint8)
    p[bd[sl]] = (0, 0, 255)
    p = cv2.resize(p, (cell - 6, cell - 6))
    r, c = divmod(i, cols)
    oy, ox = r * (cell + 26), c * cell
    sheet[oy:oy + cell - 6, ox:ox + cell - 6] = p
    cv2.putText(sheet, "%d-%d (%d)" % (a, b, e["len"]), (ox + 4, oy + cell + 14),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 0, 180), 2)
cv2.imwrite(sys.argv[4], sheet)
print(len(edges), "edges on sheet")
