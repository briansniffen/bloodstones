# Decisions

Settled choices, with where each came from. "Brian" means the decision came
from him, the project owner. Newest at the bottom of each section.

## Where the spec lives

The tech spec (v0.2+, March 2026) was written in a claude.ai chat and merged
with Brian's own edited copy (`bloodstones-ipad-techspec.md`). Brian's local
copy is the source of truth; it should be committed here as `docs/tech-spec.md`.
The March map JSON files were not saved and are superseded by `data/maps/`.

## Platform

- iPadOS 17 minimum, SwiftData for persistence. (Brian, Mar 2026)
- SwiftUI views over a pure-Swift engine: `apply(action, state) -> state`,
  `legalActions(state)`. `GameState` is a Codable value type saved after
  every action. (spec v0.2)
- Landscape only, fully offline, no accounts or telemetry. (spec v0.2)

## Scope

- Campaign is solo only; no 2-player co-op. (Brian's spec edit, Mar 2026)
- 6 missions unlocked at start, one per faction: six mini-campaigns.
  Completed missions are freely replayable. (Brian, Mar 2026)
- Deferred: Cutiecorn optional rules, background music. (Brian, Mar 2026)

## Rules clarifications

- Swords modifier applies always, not only when attacking; Cavalry +1 in
  plains; Ships always count and let land units cross sea. (Brian's spec edit)
- Brian clarified Undead movement in his spec edit; see his copy.
- Rivers are ordinary borders and do not inhibit movement. (Rulebook, "Move Units")

## Battle UX in pass-and-play (Brian, Mar 2026)

- Attacker sees the bags draw, their own tiles face up, and the backs of the
  defender's drawn tiles (the count). Attacker decides whether to substitute.
- "Pass to the defender" interstitial showing the defender's faction icon.
- Defender sees the attacker's tile backs (count, and which are
  substitutions) and their own tiles face up, then decides on substitution.
- Corsairs defending: the defender also sees the attacker's tile fronts.
- Corsairs attacking: the defender's information has to come first, so the
  order flips.

## Map data

- Regions are irregular areas numbered as on each mission's key map
  (Tyrant's Lament: 1 = top-left sea, 75 = bottom-right desert).
- Each region entry is the single source of truth for terrain and
  adjacency. Summary stats are limited to `totalRegions` and `adjacencyEdges`.
  Asymmetric adjacency is allowed by the schema for future maps. (Brian)
- Region entries also carry `displayPosition` (the number circle's centre) and
  `polygon`, both in pixels of the map's playable area at 300 dpi; the size is
  in `coordinateSpace`. (Oct 2026)
- Terrain on Tyrant's Lament comes from Brian, reading the physical map.
- The March 176-edge Tyrant's Lament graph was wrong and is discarded. It
  listed non-touching pairs such as 2–8, 3–10, 4–12 and 19–27. (Oct 2026)
- Adjacency is extracted by segmentation and checked two ways: every step of
  every fixed army route in Missions 1, 3 and 4 (45 pairs) must be an edge,
  and Brian reviews the short borders on the review page. (Oct 2026)
- Tyrant's Lament reviewed by Brian (12 Oct 2026): all 16 short borders
  confirmed, sea 1–sea 9 added (segmentation missed it). 198 borders, final.
- Swan Dance (12 Oct 2026): 197 borders traced. Mission 5 has the only fixed
  routes on this map: 14 of 15 steps are borders. The 15th, 47 to 42, is
  marked "(sea)" in the mission text: dragons cross water there, so it is
  not a border. Terrain was Claude's reading of the map art.
- Region 6 on Swan Dance shows through a gap in the score track, and a strip
  of it runs under the 0-3 boxes above region 8. Score-track boxes are
  masked per map rather than cropped off.
- Swan Dance reviewed by Brian (12 Oct 2026): every traced border and every
  terrain correct; sea 1–land 10 added. 198 borders, final.
- Triangle rule (Brian, 12 Oct 2026): every junction is three-way, so every
  face of the adjacency graph, with the frame as a node, is a triangle. A
  four-cycle with no diagonal at one junction means a missing border.
  `quads.py` checks this on every map before review.
- Both border misses had a cause, now fixed: Swan 1–10 was a four-way corner
  (caught by the triangle rule); Tyrant's 1–9 was a narrow water channel cut
  off by a rock, which segmentation gave to the shore. Water pockets now go
  to a sea within 120 px.
- Brian (12 Oct 2026): "just do the other maps and come to me with any
  great uncertainty." Lady of the Lake, Sorcerer's Crucible and Remains of
  the Past were traced and checked by Claude, not reviewed on a page:
  - every border under 80 px inspected by eye on a contact sheet;
  - triangle rule clean on all three; graphs symmetric and connected;
  - terrain read by eye and cross-checked against a colour classifier
    trained on Brian's two confirmed maps; 168 of 174 agreed, and the 6
    disagreements were checked and the reading kept.
  - None of these missions has fixed army routes, so there is no route check.
- Sorcerer's Crucible 86–88 is not a border: they touch for 5 px at the
  mouth of a water inlet. The faces around it close as triangles through
  sea 97 without it.

