# Bloodstones for iPad

A pass-and-play iPad adaptation of *Bloodstones* (Martin Wallace), covering
local competitive play and Stephen Hurn's 18-mission solo campaign.

Personal project; the game, its art and its rules belong to their
publishers. Publisher PDFs and map renders are not committed. Rebuild them
locally from your own copies (see below).

## Layout

| Path | What |
|---|---|
| `CLAUDE.md` | Orientation for Claude Code sessions: status, next task, map schema. |
| `docs/` | Decisions log. The March tech spec was lost; decisions.md is the record. |
| `data/maps/` | Map JSON the app loads: regions, terrain, adjacency, polygons. |
| `source/` | Per-map inputs for the map pipeline (marker positions, frame, terrain, segmentation output). |
| `tools/mapgen/` | Map extraction pipeline. |
| `BloodstonesEngine/` | Swift package: the rules engine (`swift test`) and a text-mode player for Mission 1 (`swift run --package-path BloodstonesEngine bloodstones [--seed N]`). |
| `App/` | Xcode project for the iPad app (iPadOS 17, landscape, SwiftData). Open `App/Bloodstones.xcodeproj`; the screens live in the package's `BloodstonesUI` library, and `swift run --package-path BloodstonesEngine BloodstonesSnapshot <dir>` renders them to PNGs on a Mac. |
| `review/` | `template.html` for the per-map review pages, which `make_review.py` generates into `review/<map>/`. |

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
5. `quads.py` applies Brian's triangle rule. Every junction on these maps is
   three-way, so with the frame counted as one region, every face of the
   adjacency graph is a triangle. Wherever four regions meet within 25 px with
   no diagonal between them, a border is missing or the corner went to the
   wrong side.
6. `edge_sheet.py` makes a contact sheet of doubtful edges cropped from the
   map, and the review page lets the map owner confirm, rule out, or add borders.
7. The owner's rulings are saved in `source/<map>_review.json` and applied by
   `build_map.py`, so a re-run of segmentation never loses them.

Per-map settings in `source/<map>_frame.json`: the playable rectangle, the sea
regions, and `outside` rectangles for score-track boxes drawn over the map.
`"outside": "auto"` detects the boxes instead, and stretches any box within 30 px
of the frame out to it, so no strip of map behind the track joins regions.
`"waterHueMin"` (default 58) separates water from blue-green forest; Remains
of the Past needs 76.

Key-map pages: Tyrant's Lament is Mission 1 p.2 (right half of a spread);
the others are p.3 (full page) of Missions 5, 10, 11 and 14.

`terrain_guess.py` cross-checks a terrain reading against a colour classifier
trained on the confirmed maps (about 95% right on held-out maps; weakest on
mountains and on Remains of the Past's pale hills).

```sh
tools/mapgen/render_key.sh 01_Solo_Mission_1.pdf 2 right source/tyrants_lament_key.png
python3 tools/mapgen/segment.py source/tyrants_lament_key.png \
  source/tyrants_lament_markers.json source/tyrants_lament_frame.json /tmp/tl
python3 tools/mapgen/build_map.py source/tyrants_lament_key.png \
  source/tyrants_lament_markers.json source/tyrants_lament_frame.json \
  source/tyrants_lament_terrain.json /tmp/tl_labels.png /tmp/tl_edges.json \
  data/maps/tyrants_lament.json source/tyrants_lament_review.json
```

Needs Python 3 with `opencv-python`, `numpy`, `scipy`, `scikit-image`, `Pillow`,
and poppler's `pdftoppm`.

## Status

| Map | Missions | Regions | Borders | State |
|---|---|---|---|---|
| Tyrant's Lament | 1, 2, 3, 4, 9 | 75 | 198 | Reviewed by Brian, Oct 2026 |
| Swan Dance | 5, 6, 7, 8 | 76 | 198 | Reviewed by Brian, Oct 2026 |
| Lady of the Lake | 10, 16 | 44 | 110 | Checked by Claude (Brian delegated), Oct 2026 |
| Sorcerer's Crucible | 11, 12, 13, 18 | 98 | 273 | Checked by Claude (Brian delegated), Oct 2026 |
| Remains of the Past | 14, 15, 17 | 69 | 177 | Checked by Claude (Brian delegated), Oct 2026 |
