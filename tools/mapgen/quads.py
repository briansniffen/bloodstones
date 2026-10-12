"""Brian's triangle rule: on these maps every junction is three-way, so in the
adjacency graph (with the map frame as one extra node, 0) every face around a
junction is a triangle. Wherever four or more regions meet within RADIUS px
and their borders there form a cycle of four or more with no diagonal, one
diagonal is probably missing (or the corner was given to the wrong side).

Usage: python quads.py labels.png adjacency.json [radius]
adjacency.json is either an edges list ([{a, b, len}]) or a map JSON
(regions with adjacentTo). Prints one JSON line per suspicious junction:
{"regions": [...], "missing": [[a, b], ...], "at": [x, y]}
"""
import itertools
import json
import sys

import cv2
import numpy as np


def load_adjacency(path):
    d = json.load(open(path))
    if isinstance(d, dict):
        return {(min(r["id"], n), max(r["id"], n)) for r in d["regions"] for n in r["adjacentTo"]}
    return {(e["a"], e["b"]) for e in d if e.get("len") is None or e["len"] >= 8}


def frame_neighbours(L):
    """Regions that touch label 0 (outside the map, or score-track boxes)."""
    out = set()
    for a, b in ((L[:, :-1], L[:, 1:]), (L[:-1, :], L[1:, :])):
        m = (a == 0) & (b > 0)
        out |= set(np.unique(b[m]).tolist())
        m = (b == 0) & (a > 0)
        out |= set(np.unique(a[m]).tolist())
    return {(0, int(i)) for i in out}


def is_chordless_cycle(nodes, adj):
    """True if the induced subgraph on these nodes is exactly one cycle."""
    deg = {n: 0 for n in nodes}
    count = 0
    for a, b in itertools.combinations(nodes, 2):
        if (min(a, b), max(a, b)) in adj:
            deg[a] += 1
            deg[b] += 1
            count += 1
    return count == len(nodes) and all(v == 2 for v in deg.values())


def main():
    L = cv2.imread(sys.argv[1], -1).astype(np.int32)
    adj = load_adjacency(sys.argv[2]) | frame_neighbours(L)
    radius = int(sys.argv[3]) if len(sys.argv) > 3 else 25
    s = 3  # work at 1/3 scale for speed
    Ls = L[::s, ::s]
    r = max(1, radius // s)
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))
    ids = [int(i) for i in np.unique(Ls)]
    near = np.zeros(Ls.shape, np.uint8)
    masks = {}
    for i in ids:
        masks[i] = cv2.dilate((Ls == i).astype(np.uint8), k).astype(bool)
        near += masks[i]
    seen = {}
    for y, x in zip(*np.nonzero(near >= 4)):
        here = tuple(i for i in ids if masks[i][y, x])
        for n in range(4, len(here) + 1):
            for sub in itertools.combinations(here, n):
                if sub not in seen and is_chordless_cycle(sub, adj):
                    seen[sub] = (int(x) * s, int(y) * s)
    for sub, (x, y) in sorted(seen.items()):
        missing = [[a, b] for a, b in itertools.combinations(sub, 2)
                   if (min(a, b), max(a, b)) not in adj]
        print(json.dumps({"regions": list(sub), "missing": missing, "at": [x, y]}))


if __name__ == "__main__":
    main()
