"""Assemble the app's map JSON from segmentation output plus hand-entered data.

Usage:
  python build_map.py map.png markers.json frame.json terrain.json labels.png edges.json out.json [review.json]

terrain.json: {"mapId", "displayName", "terrain": {"hills": [ids], ...}}
              Any land id not listed is plains; ids in frame.json "sea" are sea.
review.json (optional): the map owner's rulings, {"confirmed", "added", "removed"}
              as lists of [a, b]. Added/removed edges override segmentation;
              confirmed edges come off the review list; "flag" adds edges to it.
Edges shorter than REVIEW_LEN shared-border pixels are listed for review.
Coordinates are in pixels of the frame's inner rectangle (origin top-left),
with its size given in "coordinateSpace".
"""
import json
import sys

import cv2
import numpy as np

REVIEW_LEN = 80
MIN_LEN = 8  # below this a shared border is a segmentation sliver, not a border


def polygon(labels, rid, eps=3.0):
    m = (labels == rid).astype(np.uint8)
    cs, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    c = max(cs, key=cv2.contourArea)
    c = cv2.approxPolyDP(c, eps, True)
    return [[int(p[0][0]), int(p[0][1])] for p in c]


def main():
    _, markers_p, frame_p, terrain_p, labels_p, edges_p, out_p = sys.argv[1:8]
    markers = {m["id"]: m for m in json.load(open(markers_p))}
    frame = json.load(open(frame_p))
    tcfg = json.load(open(terrain_p))
    x0, y0, x1, y1 = frame["inner"]
    labels = cv2.imread(labels_p, -1).astype(np.int32)[y0:y1, x0:x1]
    edges = [e for e in json.load(open(edges_p)) if e["len"] >= MIN_LEN]
    review = json.load(open(sys.argv[8])) if len(sys.argv) > 8 else {}
    norm = lambda ab: tuple(sorted(ab))
    removed = {norm(ab) for ab in review.get("removed", [])}
    confirmed = {norm(ab) for ab in review.get("confirmed", [])}
    edges = [e for e in edges if (e["a"], e["b"]) not in removed]
    have = {(e["a"], e["b"]) for e in edges}
    for a, b in map(norm, review.get("added", [])):
        confirmed.add((a, b))  # the owner put it there, so it is confirmed
        if (a, b) not in have:
            edges.append({"a": a, "b": b, "len": None})

    terrain = {i: "plains" for i in markers}
    for i in frame["sea"]:
        terrain[i] = "sea"
    for kind, ids in tcfg["terrain"].items():
        for i in ids:
            terrain[i] = kind

    adj = {i: [] for i in markers}
    for e in edges:
        adj[e["a"]].append(e["b"])
        adj[e["b"]].append(e["a"])

    regions = []
    for i in sorted(markers):
        m = markers[i]
        regions.append({
            "id": i,
            "terrain": terrain[i],
            "adjacentTo": sorted(adj[i]),
            "displayPosition": [round(m["cx"] - x0, 1), round(m["cy"] - y0, 1)],
            "polygon": polygon(labels, i),
        })

    flag = {norm(ab) for ab in review.get("flag", [])}
    pending = [[e["a"], e["b"]] for e in edges
               if ((e["len"] is not None and e["len"] < REVIEW_LEN) or (e["a"], e["b"]) in flag)
               and (e["a"], e["b"]) not in confirmed]
    out = {
        "mapId": tcfg["mapId"],
        "displayName": tcfg["displayName"],
        "coordinateSpace": {"width": x1 - x0, "height": y1 - y0},
        "stats": {"totalRegions": len(regions), "adjacencyEdges": len(edges)},
        "regions": regions,
        "provenance": {
            "adjacency": "watershed segmentation of key map, then owner review",
            "terrain": tcfg.get("terrainSource", "annotated by Brian from the physical map"),
            "terrainUncertain": tcfg.get("uncertain", []),
            "reviewEdges": pending,
            "addedByReview": [list(norm(ab)) for ab in review.get("added", [])],
            "removedByReview": [list(norm(ab)) for ab in review.get("removed", [])],
            "reviewedBy": review.get("reviewedBy"),
            "reviewedOn": review.get("reviewedOn"),
            "status": "reviewed" if review and not pending else "draft",
        },
    }
    json.dump(out, open(out_p, "w"), indent=1)
    print(out_p, out["stats"], "review:", len(out["provenance"]["reviewEdges"]))


if __name__ == "__main__":
    main()
