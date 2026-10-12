"""Generate a map's review page folder from review/template.html.

Usage: python make_review.py data/maps/<id>.json source/<id>_key.png source/<id>_frame.json
Writes review/<id>/index.html, <id>.json and <id>.jpg (the jpg is publisher
art and stays out of git).
"""
import json
import os
import shutil
import sys

import cv2

m = json.load(open(sys.argv[1]))
mid, W, H = m["mapId"], m["coordinateSpace"]["width"], m["coordinateSpace"]["height"]
x0, y0, x1, y1 = json.load(open(sys.argv[3]))["inner"]
img = cv2.imread(sys.argv[2])[y0:y1, x0:x1]
s = 1400 / img.shape[1]
img = cv2.resize(img, None, fx=s, fy=s, interpolation=cv2.INTER_AREA)
out = os.path.join("review", mid)
os.makedirs(out, exist_ok=True)
cv2.imwrite(os.path.join(out, mid + ".jpg"), img, [cv2.IMWRITE_JPEG_QUALITY, 82])
shutil.copy(sys.argv[1], os.path.join(out, mid + ".json"))
t = open("review/template.html").read()
for k, v in {"NAME": m["displayName"], "ID": mid, "W": W, "H": H,
             "IW": img.shape[1], "IH": img.shape[0]}.items():
    t = t.replace("{{%s}}" % k, str(v))
assert "{{" not in t
open(os.path.join(out, "index.html"), "w").write(t)
print(out, img.shape[1], "x", img.shape[0])
