"""Contact sheet of detected circles, labelled #index, for assigning numbers by eye.

Usage: python circle_sheet.py map.png circles.json sorted_out.json sheet.png
Sorts circles top-to-bottom, left-to-right (rows ~60 px tall) and writes the
sorted list, so the sheet's #index matches sorted_out.json.
"""
import json
import sys

import cv2
import numpy as np

img = cv2.imread(sys.argv[1])
c = json.load(open(sys.argv[2]))
c.sort(key=lambda d: (round(d["cy"] / 60), d["cx"]))
json.dump(c, open(sys.argv[3], "w"))
cell, cols = 90, 13
rows = (len(c) + cols - 1) // cols
sheet = np.full((rows * (cell + 28), cols * cell, 3), 255, np.uint8)
for i, d in enumerate(c):
    r, x, y = int(d["r"]), int(d["cx"]), int(d["cy"])
    p = cv2.resize(img[y - r:y + r, x - r:x + r], (cell - 10, cell - 10))
    R, C = divmod(i, cols)
    oy, ox = R * (cell + 28), C * cell
    sheet[oy + 5:oy + cell - 5, ox + 5:ox + cell - 5] = p
    cv2.putText(sheet, "#%d" % i, (ox + 12, oy + cell + 18), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 200), 2)
cv2.imwrite(sys.argv[4], sheet)
