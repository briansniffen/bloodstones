"""Segment a Bloodstones key map into regions and derive adjacency.

Usage:
  python segment.py map.png markers.json frame.json out_prefix

markers.json: [{id, cx, cy, r}] for every numbered region (pixel coords).
frame.json:   {"inner": [x0, y0, x1, y1], "sea": [ids]} -- the playable map
              rectangle (outside = non-region) and, optionally, the sea
              region ids (otherwise guessed from water around each circle).
              Optional "outside": [[x0, y0, x1, y1], ...] rectangles inside the
              frame that are not map, e.g. score-track boxes drawn over it.

Method: build a "border cost" image (dark ink lines, thin blue rivers,
land/sea transitions), then run marker-based watershed from each region's
number circle. Two regions are adjacent when their labels share enough
boundary pixels. Internal artwork (dune strokes, forest hatching) does not
split regions because it has no competing marker behind it.

Outputs:
  <prefix>_labels.png   label image (uint16 PNG, 0 = outside)
  <prefix>_edges.json   [{a, b, len}] candidate adjacencies with border length
  <prefix>_overlay.png  visual check: region tints, centers, edges
"""
import json
import sys

import cv2
import numpy as np
from scipy.ndimage import distance_transform_edt
from skimage.morphology import remove_small_holes
from skimage.segmentation import watershed

OUTSIDE = 10_000


def border_cost(img):
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    h, s, v = hsv[..., 0].astype(int), hsv[..., 1].astype(int), hsv[..., 2].astype(int)

    # 1. dark ink lines (region borders are dark brown)
    dark = np.clip((150 - v) / 70.0, 0, 1)

    # 2. water: rivers are thin blue strokes; sea is large blue areas
    # include pale shallow water; then fill wave scribbles / sea creatures
    blue = ((h > 58) & (h < 125) & (s > 25) & (v > 90)).astype(np.uint8)
    blue = cv2.morphologyEx(blue, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    # close over wave scribbles before deciding what is open water
    blue = cv2.morphologyEx(blue, cv2.MORPH_CLOSE,
                            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11)))
    # 25px opening drops rivers (~15px wide at 300dpi) but keeps straits
    big = cv2.morphologyEx(blue, cv2.MORPH_OPEN,
                           cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (25, 25)))
    big = remove_small_holes(big.astype(bool), max_size=6000).astype(np.uint8)
    blue = np.maximum(blue, big)
    river = (blue & (1 - big)).astype(float)

    # 3. coastline: the edge of the large-water mask
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))
    coast = (cv2.dilate(big, k) - cv2.erode(big, k)).astype(float)

    cost = np.maximum.reduce([dark, river, coast])
    cost = cv2.GaussianBlur(cost, (7, 7), 0)
    return (cost * 1000).astype(np.int32), big.astype(bool)


def erase_markers(img, markers):
    """Paint each white number circle with the median colour of the ring
    just outside it, so circles don't read as islands or coastlines."""
    out = img.copy()
    yy, xx = np.mgrid[0:img.shape[0], 0:img.shape[1]]
    for m in markers:
        cx, cy, r = int(m["cx"]), int(m["cy"]), m["r"]
        y0, y1, x0, x1 = cy - int(2 * r), cy + int(2 * r), cx - int(2 * r), cx + int(2 * r)
        d = np.hypot(yy[y0:y1, x0:x1] - cy, xx[y0:y1, x0:x1] - cx)
        ring = img[y0:y1, x0:x1][(d > r * 1.25) & (d < r * 1.6)]
        out[y0:y1, x0:x1][d <= r * 1.25] = np.median(ring, axis=0).astype(np.uint8)
    return out


def classify_sea(water, markers):
    """A region is sea if most of the ring around its circle is open water."""
    sea = set()
    yy, xx = np.mgrid[0:water.shape[0], 0:water.shape[1]]
    for m in markers:
        cx, cy, r = int(m["cx"]), int(m["cy"]), m["r"]
        sl = (slice(cy - int(3 * r), cy + int(3 * r)), slice(cx - int(3 * r), cx + int(3 * r)))
        d = np.hypot(yy[sl] - cy, xx[sl] - cx)
        if water[sl][(d > 1.4 * r) & (d < 2.8 * r)].mean() > 0.6:
            sea.add(int(m["id"]))
    return sea


def segment(img, markers, inner, sea_ids=None, outside=None):
    """Land regions flood only land pixels and sea regions only open water,
    so a land region can never reach across a strait to another shore."""
    cost, water = border_cost(erase_markers(img, markers))
    if sea_ids is None:
        sea_ids = classify_sea(water, markers)
    x0, y0, x1, y1 = inner
    inside = np.zeros(water.shape, bool)
    inside[y0:y1, x0:x1] = True
    for ox0, oy0, ox1, oy1 in outside or []:  # score-track boxes drawn over the map
        inside[oy0:oy1, ox0:ox1] = False
    # marker circles themselves belong to their own region's medium
    for m in markers:
        c = (int(m["cx"]), int(m["cy"]))
        disk = np.zeros(water.shape, np.uint8)
        cv2.circle(disk, c, int(m["r"] * 1.6), 1, -1)
        water[disk.astype(bool)] = int(m["id"]) in sea_ids
        cv2.circle(cost, c, int(m["r"] * 1.6), 0, -1)  # never start walled in

    labels = np.zeros(water.shape, np.int32)
    for is_sea in (True, False):
        seeds = np.zeros(water.shape, np.int32)
        for m in markers:
            if (int(m["id"]) in sea_ids) == is_sea:
                cv2.circle(seeds, (int(m["cx"]), int(m["cy"])), int(m["r"] * 1.3), int(m["id"]), -1)
        medium = inside & (water if is_sea else ~water)
        part = watershed(cost, seeds, mask=medium)
        labels[medium] = part[medium]

    # pixels no seed could reach (islands, lakes): give to the nearest region
    unl = inside & (labels == 0)
    if unl.any():
        _, (iy, ix) = distance_transform_edt(labels == 0, return_indices=True)
        labels[unl] = labels[iy[unl], ix[unl]]
    return labels, cost, sea_ids


def adjacency(labels):
    counts = {}
    for a, b in ((labels[:, :-1], labels[:, 1:]), (labels[:-1, :], labels[1:, :])):
        diff = (a != b) & (a > 0) & (b > 0)
        pa, pb = a[diff], b[diff]
        lo, hi = np.minimum(pa, pb), np.maximum(pa, pb)
        keys, n = np.unique(lo.astype(np.int64) * 1000 + hi, return_counts=True)
        for k, c in zip(keys, n):
            counts[(int(k // 1000), int(k % 1000))] = counts.get((int(k // 1000), int(k % 1000)), 0) + int(c)
    return [{"a": a, "b": b, "len": n} for (a, b), n in sorted(counts.items())]


def overlay(img, labels, markers, edges, min_len):
    rng = np.random.default_rng(7)
    pal = rng.integers(60, 255, (labels.max() + 1, 3)).astype(np.uint8)
    pal[0] = 0
    tint = cv2.addWeighted(img, 0.45, pal[labels], 0.55, 0)
    bnd = np.zeros(labels.shape, bool)
    bnd[:, 1:] |= labels[:, 1:] != labels[:, :-1]
    bnd[1:, :] |= labels[1:, :] != labels[:-1, :]
    tint[bnd] = (0, 0, 0)
    pos = {m["id"]: (int(m["cx"]), int(m["cy"])) for m in markers}
    for e in edges:
        if e["len"] >= min_len:
            cv2.line(tint, pos[e["a"]], pos[e["b"]], (0, 0, 255), 3)
    for i, p in pos.items():
        cv2.circle(tint, p, 26, (255, 255, 255), -1)
        cv2.putText(tint, str(i), (p[0] - 20, p[1] + 10), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 0, 0), 2)
    return tint


if __name__ == "__main__":
    img = cv2.imread(sys.argv[1])
    markers = json.load(open(sys.argv[2]))
    cfg = json.load(open(sys.argv[3]))
    inner = cfg["inner"]
    prefix = sys.argv[4]
    labels, cost, sea_ids = segment(img, markers, inner, set(cfg["sea"]) if "sea" in cfg else None,
                                    cfg.get("outside"))
    print("sea regions:", sorted(sea_ids))
    edges = adjacency(labels)
    cv2.imwrite(prefix + "_labels.png", labels.astype(np.uint16))
    cv2.imwrite(prefix + "_cost.png", (np.clip(cost, 0, 1000) / 1000 * 255).astype(np.uint8))
    json.dump(edges, open(prefix + "_edges.json", "w"), indent=0)
    cv2.imwrite(prefix + "_overlay.png", overlay(img, labels, markers, edges, 20))
    print(len(edges), "candidate edges")
