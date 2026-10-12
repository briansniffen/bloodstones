# Bloodstones for iPad

A pass-and-play iPad adaptation of *Bloodstones* (Martin Wallace), covering
local competitive play and Stephen Hurn's 18-mission solo campaign.

Personal project; the game, its art and its rules belong to their
publishers. Publisher PDFs and map renders are not committed. Rebuild them
locally from your own copies (see below).

## Layout

| Path | What |
|---|---|
| `docs/` | Decisions log and plan. The full tech spec lives with Brian (see `docs/decisions.md`). |
| `data/maps/` | Map JSON the app loads: regions, terrain, adjacency, polygons. |
| `source/` | Per-map inputs for the map pipeline (marker positions, frame, terrain, segmentation output). |
| `tools/mapgen/` | Map extraction pipeline. |
| `review/` | The border-review page (published as a claude.ai artifact). |

## Map pipeline

Each mission PDF opens with a numbered key map. Region numbers are vector
glyphs, so the pipeline works from the rendered image:

1. `render_key.sh` renders the key-map page at 300 dpi.
2. `find_circles.py` finds the white number circles. Numbers are then
   assigned by eye from a contact sheet and saved in `source/<map>_markers.json`.
3. `segment.py` floods each region outward from its circle (marker-based
   watershed over ink lines, rivers and coastline). Sea regions flood only
   water and land regions only land, so nothing reaches across a strait.
   Two regions are adjacent when their floods share a border.
4. `build_map.py` merges that with hand-entered terrain into `data/maps/<map>.json`.
   Short shared borders (under 80 px) are listed in `provenance.reviewEdges`.
5. `edge_sheet.py` makes a contact sheet of doubtful edges cropped from the
   map, and the review page lets the map owner confirm, rule out, or add borders.

```sh
tools/mapgen/render_key.sh 01_Solo_Mission_1.pdf 2 right source/tyrants_lament_key.png
python3 tools/mapgen/segment.py source/tyrants_lament_key.png \
  source/tyrants_lament_markers.json source/tyrants_lament_frame.json /tmp/tl
python3 tools/mapgen/build_map.py source/tyrants_lament_key.png \
  source/tyrants_lament_markers.json source/tyrants_lament_frame.json \
  source/tyrants_lament_terrain.json /tmp/tl_labels.png /tmp/tl_edges.json \
  data/maps/tyrants_lament.json
```

Needs Python 3 with `opencv-python`, `numpy`, `scipy`, `scikit-image`, `Pillow`,
and poppler's `pdftoppm`.

## Status

| Map | Missions | Regions | Borders | State |
|---|---|---|---|---|
| Tyrant's Lament | 1, 2, 3, 4, 9 | 75 | 197 | Traced; awaiting review |
| Swan Dance | 5, 6, 7, 8 | | | Not started |
| Lady of the Lake | 10, 16 | | | Not started |
| Sorcerer's Crucible | 11, 12, 13, 18 | | | Not started |
| Remains of the Past | 14, 15, 17 | | | Not started |
