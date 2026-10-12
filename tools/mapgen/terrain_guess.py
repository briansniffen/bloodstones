"""Guess each land region's terrain from its colours, using maps whose terrain
is confirmed as training data. A cross-check on readings by eye, not a
replacement for them.

Usage:
  python terrain_guess.py train <map_id> [<map_id> ...] -- <target_map_id>

Each map needs source/<id>_key.png, source/<id>_labels.png,
source/<id>_markers.json and data/maps/<id>.json (for training maps) or
source/<id>_frame.json (for the target's sea list). Prints, per land region
of the target, the guess and the runner-up with a margin.
"""
import json
import sys

import cv2
import numpy as np

KINDS = ["plains", "forest", "hills", "mountains", "desert"]


def features(img, labels, markers):
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV).astype(np.float32)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    # colour families seen on the confirmed maps
    fam = {
        "pink": ((h >= 160) | (h <= 4)) & (s > 45) & (v > 120),
        "tan": (h >= 10) & (h <= 24) & (s > 50) & (v > 170),
        "dkgreen": (h >= 30) & (h <= 75) & (v < 150) & (s > 80),
        "ltgreen": (h >= 27) & (h <= 45) & (v >= 150) & (s > 60),
        "grey": (s < 45) & (v > 110) & (v < 235),
    }
    k = np.ones((9, 9), np.uint8)
    out = {}
    for m in markers:
        i = m["id"]
        reg = cv2.erode((labels == i).astype(np.uint8), k).astype(bool)
        yy, xx = np.ogrid[:labels.shape[0], :labels.shape[1]]
        reg &= (yy - m["cy"]) ** 2 + (xx - m["cx"]) ** 2 > (m["r"] * 1.4) ** 2
        n = reg.sum()
        if n < 200:
            continue
        f = [fam[k][reg].mean() for k in ("pink", "tan", "dkgreen", "ltgreen", "grey")]
        f += [np.median(s[reg]) / 255, np.median(v[reg]) / 255]
        out[i] = np.array(f)
    return out


def load(mid):
    img = cv2.imread(f"source/{mid}_key.png")
    lab = cv2.imread(f"source/{mid}_labels.png", -1).astype(np.int32)
    mk = json.load(open(f"source/{mid}_markers.json"))
    return features(img, lab, mk)


def main():
    a = sys.argv[2:]
    train_ids, target = a[:a.index("--")], a[a.index("--") + 1]
    X, y = [], []
    for mid in train_ids:
        f = load(mid)
        terr = {r["id"]: r["terrain"] for r in json.load(open(f"data/maps/{mid}.json"))["regions"]}
        for i, v in f.items():
            if terr[i] in KINDS:
                X.append(v)
                y.append(terr[i])
    X = np.array(X)
    mu, sd = X.mean(0), X.std(0) + 1e-6
    Xn = (X - mu) / sd
    sea = set(json.load(open(f"source/{target}_frame.json"))["sea"])
    for i, v in sorted(load(target).items()):
        if i in sea:
            continue
        d = np.linalg.norm(Xn - (v - mu) / sd, axis=1)
        idx = np.argsort(d)[:5]  # 5 nearest confirmed regions vote
        votes = {}
        for j in idx:
            votes[y[j]] = votes.get(y[j], 0) + 1 / (d[j] + 0.1)
        ranked = sorted(votes.items(), key=lambda t: -t[1])
        best = ranked[0]
        second = ranked[1] if len(ranked) > 1 else ("-", 0)
        conf = best[1] / (best[1] + second[1])
        print(json.dumps({"id": i, "guess": best[0], "second": second[0], "conf": round(conf, 2)}))


if __name__ == "__main__":
    main()
