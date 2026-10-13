# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow", "numpy", "scipy"]
# ///
"""Cut the app's artwork out of the publisher PDFs in pdfs/.

  uv run tools/art/extract_art.py [--pdfs pdfs] [--out art] [--check DIR]

Writes art/ (gitignored, like the PDFs):
  maps/<mapId>.jpg      the board at 300 dpi, the playable area plus a margin
  units/<faction>/<unit>.png   the figure from each faction-card tile, with
                        a transparent background (map pieces)
  tiles/<faction>/<unit>.png   the whole tile as printed, with its build-cost
                        knots (left) and pip marks (right); blank.png too
  citadels/<faction>.png, villages/<faction>.png
  cards/<faction>.jpg   the faction cards (rulebook pp. 24-26)
  border/corner.png, border/edge.png   the knotwork frame, to draw around
                        any map (the Tyrant's Lament key map is cut off)
  art.json              tile colours per faction, each map's inset, and
                        the border's measurements

--check DIR also writes contact sheets there: the maps with every region's
displayPosition marked, and all the cut-outs.
"""
import argparse
import json
import re
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]

# Key-map pages (see README): mission PDF, page, which half of the page.
MAPS = {
    "tyrants_lament": ("01_Solo_Mission_1.pdf", 2, "right"),
    "swan_dance": ("05_Solo_Mission_5.pdf", 3, "full"),
    "lady_of_the_lake": ("10_Solo_Mission_10.pdf", 3, "full"),
    "sorcerers_crucible": ("11_Solo_Mission_11.pdf", 3, "full"),
    "remains_of_the_past": ("14_Solo_Mission_14.pdf", 3, "full"),
}
MAP_MARGIN = 110  # px of board frame kept around the playable area

# The knotwork border, measured on the Sorcerer's Crucible map image (the
# cleanest full frame): the band is 105 px deep and the knot repeats every
# 244/3 px, mirror-symmetric every half repeat. A corner cut at 176 px ends
# on a symmetry point, so corners and edge tiles join seamlessly.
BORDER_MAP = "sorcerers_crucible"
BORDER_WIDTH = 105
BORDER_CORNER = 176
BORDER_TILE = 244  # three repeats

RULEBOOK = "00_English_Rulebook.pdf"
TILE_DPI = 600
# Faction cards: rulebook PDF page (each is a spread) and the card's
# rectangle in points.
CARDS = {
    "dragonRiders": (13, (59, 80, 522, 403)),
    "horseLords": (13, (59, 434, 522, 757)),
    "necromancers": (13, (640, 78, 1104, 400)),
    "hillFolk": (13, (640, 431, 1104, 754)),
    "chaosHorde": (14, (59, 58, 523, 381)),
    "corsairs": (14, (59, 410, 523, 733)),
}
LABELS = {
    "SKIRMISHERS": "skirmishers", "SWORDS": "swords", "SHIELD": "shield",
    "CAVALRY": "cavalry", "SIEGE": "siegeEngine", "LEADER": "leader",
    "SHIP": "ship", "CASTLE": "castle", "LIZARDMEN": "lizardmen",
    "DRAGON": "dragon", "GOBLINS": "goblins", "NECROMANCER": "necromancer",
    "UNDEAD": "undead", "REIVERS": "reivers", "GIANT": "giant",
    "HORDES": "hordes", "AXES": "axes", "CITADEL": "citadel",
}


def render(pdf, page, dpi):
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["pdftoppm", "-r", str(dpi), "-f", str(page), "-l", str(page),
                        "-png", str(pdf), f"{tmp}/p"], check=True)
        return Image.open(next(Path(tmp).glob("p-*.png"))).convert("RGB")


def words(pdf, page):
    """(xMin, yMin, xMax, yMax, text) in points for each word on a page."""
    out = subprocess.run(["pdftotext", "-f", str(page), "-l", str(page), "-bbox", str(pdf), "-"],
                         capture_output=True, text=True, check=True).stdout
    pat = re.compile(r'xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">([^<]*)<')
    return [(float(a), float(b), float(c), float(d), t) for a, b, c, d, t in pat.findall(out)]


# ---------------------------------------------------------------- maps

def extract_map(pdfs, out, map_id):
    pdf, page, side = MAPS[map_id]
    im = render(pdfs / pdf, page, 300)
    w, h = im.size
    if side == "right":
        im = im.crop((w // 2, 0, w, h))
    frame = json.load(open(ROOT / f"source/{map_id}_frame.json"))
    x0, y0, x1, y1 = frame["inner"]
    m = MAP_MARGIN
    box = (max(0, x0 - m), max(0, y0 - m), min(im.width, x1 + m), min(im.height, y1 + m))
    im.crop(box).save(out / f"maps/{map_id}.jpg", quality=85, optimize=True)
    return {"file": f"maps/{map_id}.jpg", "inset": [x0 - box[0], y0 - box[1]]}


def check_map(out, map_id, info, check):
    im = Image.open(out / info["file"]).convert("RGB")
    d = ImageDraw.Draw(im)
    dx, dy = info["inset"]
    data = json.load(open(ROOT / f"data/maps/{map_id}.json"))
    for r in data["regions"]:
        x, y = r["displayPosition"]
        d.ellipse((x + dx - 9, y + dy - 9, x + dx + 9, y + dy + 9), outline="red", width=4)
        d.polygon([(px + dx, py + dy) for px, py in r["polygon"]], outline="magenta")
    im.thumbnail((1400, 1400))
    im.save(check / f"map-{map_id}.jpg", quality=80)


# ---------------------------------------------------------------- tiles

def mode_colour(px):
    q = (px // 8).reshape(-1, 3)
    vals, counts = np.unique(q, axis=0, return_counts=True)
    c = vals[counts.argmax()]
    sel = np.all(q == c, axis=1)
    return px.reshape(-1, 3)[sel].mean(axis=0)


def dist(a, c):
    return np.sqrt(((a.astype(float) - c) ** 2).sum(axis=-1))


def find_tile(arr, box, paper):
    """The tile (a flat rounded rectangle) inside box: its bbox and colour."""
    x0, y0, x1, y1 = box
    win = arr[y0:y1, x0:x1]
    bg = mode_colour(win[dist(win, paper) > 30])
    lab, n = ndimage.label(dist(win, bg) < 18)
    sizes = ndimage.sum(np.ones_like(lab), lab, range(1, n + 1))
    k = int(np.argmax(sizes)) + 1
    ys, xs = np.nonzero(lab == k)
    return (x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1), bg


def figure(arr, tile, bg):
    """The unit figure between the tile's pip marks, background made clear."""
    x0, y0, x1, y1 = tile
    tw, th = x1 - x0, y1 - y0
    fx0, fx1 = x0 + int(tw * 0.17), x0 + int(tw * 0.83)
    fy0, fy1 = y0 + int(th * 0.04), y1 - int(th * 0.04)
    px = arr[fy0:fy1, fx0:fx1].astype(float)
    a = np.clip((dist(px, bg) - 12) / 60, 0, 1)
    # Unmix the anti-aliased edge from the tile colour.
    safe = np.maximum(a, 1e-3)[..., None]
    fg = np.clip((px - (1 - a[..., None]) * bg) / safe, 0, 255)
    rgba = np.dstack([fg, a * 255]).astype(np.uint8)
    img = Image.fromarray(rgba, "RGBA")
    bb = img.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox()
    return img.crop(bb) if bb else img


def find_blob(arr, box, paper):
    """The largest non-parchment shape in box (citadels, village icons)."""
    x0, y0, x1, y1 = box
    win = arr[y0:y1, x0:x1]
    mask = ndimage.binary_closing(dist(win, paper) > 45, iterations=3)
    mask = ndimage.binary_fill_holes(mask)
    lab, n = ndimage.label(mask)
    sizes = ndimage.sum(mask, lab, range(1, n + 1))
    k = int(np.argmax(sizes)) + 1
    ys, xs = np.nonzero(lab == k)
    return (x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1), lab == k, (x0, y0)


def cutout(im, arr, found, round_=False):
    (bx0, by0, bx1, by1), mask, (wx, wy) = found
    crop = im.crop((bx0, by0, bx1, by1)).convert("RGBA")
    if round_:
        alpha = Image.new("L", crop.size, 0)
        ImageDraw.Draw(alpha).ellipse((0, 0, crop.width - 1, crop.height - 1), fill=255)
    else:
        m = mask[by0 - wy:by1 - wy, bx0 - wx:bx1 - wx]
        alpha = Image.fromarray((m * 255).astype(np.uint8), "L")
    crop.putalpha(alpha)
    return crop


def whole_tile(im, tile):
    """The whole tile, build-cost knots and pip marks included, with its
    rounded corners made clear."""
    crop = im.crop(tile).convert("RGBA")
    alpha = Image.new("L", crop.size, 0)
    r = int(crop.height * 0.17)
    ImageDraw.Draw(alpha).rounded_rectangle((0, 0, crop.width - 1, crop.height - 1), radius=r, fill=255)
    crop.putalpha(alpha)
    return crop


def find_blanks(arr, card, bg, found):
    """Blank tiles: the card prints them with a count but no label. They're
    tile-coloured rectangles the size of the labelled tiles, found nowhere else."""
    x0, y0, x1, y1 = card
    win = arr[y0:y1, x0:x1]
    lab, n = ndimage.label(dist(win, bg) < 18)
    w = np.median([t[2] - t[0] for t in found])
    h = np.median([t[3] - t[1] for t in found])
    blanks = []
    for k, sl in enumerate(ndimage.find_objects(lab), start=1):
        bw, bh = sl[1].stop - sl[1].start, sl[0].stop - sl[0].start
        if abs(bw - w) > 0.1 * w or abs(bh - h) > 0.1 * h:
            continue
        box = (x0 + sl[1].start, y0 + sl[0].start, x0 + sl[1].stop, y0 + sl[0].stop)
        if not any(box[0] < t[2] and t[0] < box[2] and box[1] < t[3] and t[1] < box[3] for t in found):
            blanks.append(box)
    return blanks


def hexcol(c):
    return "#%02x%02x%02x" % tuple(int(round(v)) for v in c)


def extract_cards(pdfs, out):
    pdf = pdfs / RULEBOOK
    s = TILE_DPI / 72
    pages = {p: (render(pdf, p, TILE_DPI), words(pdf, p)) for p in {p for p, _ in CARDS.values()}}
    factions = {}
    for faction, (page, (cx0, cy0, cx1, cy1)) in CARDS.items():
        im, ws = pages[page]
        arr = np.asarray(im)
        inside = [w for w in ws if cx0 <= w[0] <= cx1 and cy0 <= w[1] <= cy1]
        card = im.crop(tuple(int(v * s) for v in (cx0, cy0, cx1, cy1)))
        card.thumbnail((1600, 1600))
        card.convert("RGB").save(out / f"cards/{faction}.jpg", quality=85)
        paper = mode_colour(arr[int(cy0 * s):int(cy1 * s), int(cx0 * s):int(cx1 * s)])
        (out / f"units/{faction}").mkdir(parents=True, exist_ok=True)
        (out / f"tiles/{faction}").mkdir(parents=True, exist_ok=True)
        tile_bg = None
        tiles_found = []
        for x, y, _, _, text in inside:
            unit = LABELS.get(text)
            if unit is None:
                continue
            if unit == "citadel":
                box = (x - 4, y + 4, x + 52, y + 58)
                found = find_blob(arr, tuple(int(v * s) for v in box), paper)
                cutout(im, arr, found, round_=True).save(out / f"citadels/{faction}.png")
                continue
            box = tuple(int(v * s) for v in (x - 6, y + 9, x + 52, y + 42))
            tile, bg = find_tile(arr, box, paper)
            figure(arr, tile, bg).save(out / f"units/{faction}/{unit}.png")
            whole_tile(im, tile).save(out / f"tiles/{faction}/{unit}.png")
            tiles_found.append(tile)
            tile_bg = tile_bg if tile_bg is not None else bg
        blanks = find_blanks(arr, tuple(int(v * s) for v in (cx0, cy0, cx1, cy1)), tile_bg, tiles_found)
        if blanks:
            whole_tile(im, blanks[0]).save(out / f"tiles/{faction}/blank.png")
        else:
            print(f"no blank tile found for {faction}")
        # Village icon: right of the "20" beside the faction name.
        twenty = [w for w in inside if w[4] == "20" and w[1] < cy0 + 45]
        entry = {"tile": hexcol(tile_bg)}
        if twenty:
            x, y, xm, _, _ = twenty[0]
            found = find_blob(arr, tuple(int(v * s) for v in (xm + 2, y - 10, xm + 40, y + 24)), paper)
            cutout(im, arr, found).save(out / f"villages/{faction}.png")
        factions[faction] = entry
    return factions


def contact_sheet(out, check):
    imgs = sorted(p for d in ("tiles", "units", "citadels", "villages") for p in (out / d).rglob("*.png"))
    cell = 140
    cols = 10
    sheet = Image.new("RGB", (cols * cell, ((len(imgs) + cols - 1) // cols) * (cell + 16)), "#888")
    d = ImageDraw.Draw(sheet)
    for i, p in enumerate(imgs):
        im = Image.open(p)
        im.thumbnail((cell - 10, cell - 10))
        x, y = (i % cols) * cell, (i // cols) * (cell + 16)
        sheet.paste(im, (x + 5, y + 5), im)
        d.text((x + 4, y + cell), f"{p.parent.name[:6]}/{p.stem}", fill="white")
    sheet.save(check / "pieces.png")


def extract_border(out):
    """The top-left corner, made symmetric about its diagonal so either arm
    can continue into an edge, with the map inside the band cut away; and
    one top-edge tile, outer side up. Other sides are these rotated."""
    im = Image.open(out / f"maps/{BORDER_MAP}.jpg").convert("RGBA")
    b, c, t = BORDER_WIDTH, BORDER_CORNER, BORDER_TILE
    corner = np.asarray(im.crop((0, 0, c, c))).copy()
    lower = np.tril_indices(c, -1)
    corner[lower] = corner.transpose(1, 0, 2)[lower]
    corner[b:, b:, 3] = 0
    Image.fromarray(corner).save(out / "border/corner.png", optimize=True)
    im.crop((c, 0, c + t, b)).convert("RGB").save(out / "border/edge.png", optimize=True)
    return {"corner": "border/corner.png", "edge": "border/edge.png",
            "width": b, "unit": t / 6}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pdfs", default=ROOT / "pdfs", type=Path)
    ap.add_argument("--out", default=ROOT / "art", type=Path)
    ap.add_argument("--check", type=Path)
    a = ap.parse_args()
    for d in ("maps", "units", "tiles", "citadels", "villages", "cards", "border"):
        (a.out / d).mkdir(parents=True, exist_ok=True)
    maps = {m: extract_map(a.pdfs, a.out, m) for m in MAPS}
    border = extract_border(a.out)
    factions = extract_cards(a.pdfs, a.out)
    json.dump({"maps": maps, "factions": factions, "border": border}, open(a.out / "art.json", "w"), indent=1)
    if a.check:
        a.check.mkdir(parents=True, exist_ok=True)
        for m, info in maps.items():
            check_map(a.out, m, info, a.check)
        contact_sheet(a.out, a.check)
    print(f"wrote {a.out}")


if __name__ == "__main__":
    main()
