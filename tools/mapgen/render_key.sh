#!/bin/sh
# Render a mission PDF's key-map page at 300 dpi and keep the map half.
# usage: render_key.sh <mission.pdf> <page> <left|right> <out.png>
# Tyrant's Lament: render_key.sh 01_Solo_Mission_1.pdf 2 right source/tyrants_lament_key.png
set -e
tmp=$(mktemp -d)
pdftoppm -r 300 -f "$2" -l "$2" -png "$1" "$tmp/p"
python3 - "$tmp"/p-*.png "$3" "$4" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]); w, h = im.size
box = (w // 2, 0, w, h) if sys.argv[2] == "right" else (0, 0, w // 2, h)
im.crop(box).save(sys.argv[3])
PY
rm -rf "$tmp"
