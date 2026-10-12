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
