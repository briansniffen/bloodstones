# Decisions

Settled choices, with where each came from. "Brian" means the decision came
from him, the project owner. Newest at the bottom of each section.

## Where the spec lives

The tech spec (v0.2+, March 2026) was written in a claude.ai chat and merged
with Brian's own edited copy (`bloodstones-ipad-techspec.md`). Brian's local
copy has since been lost (Oct 2026), so this file is the record.
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

## Faction tiles

- `data/factions.json` was transcribed from the faction cards (rulebook
  pp. 24–26) by Claude on 12 Oct 2026. Every bag sums to 36 tiles;
  Necromancers' 4 Undead are kept aside, outside the bag.
- The March spec's "Dragon Riders: 20 Lizardmen" was wrong. The 20 on every
  card is villages; Dragon Riders have 4 Lizardmen.
- Three cost differences printed on the cards: Hill Folk castles cost 1 block
  (the card says they're cheaper); Chaos Horde cavalry cost 1 block and show
  4 pips (the card says they're cheaper); Necromancer shields show 2 blocks
  where every other faction's show 1.


## Mission 1: Dragon Hunt

- Routes checked (Claude, 12 Oct 2026): all 21 steps of the three Dragon
  Rider paths are borders in `tyrants_lament.json`. Each crosses one sea
  (36, 46, 62) and all end at the player citadel on 61.
- Hill Folk line (Brian, 12 Oct 2026): the mission's truncated "No faction may
  attack or move north of" means an east-west line. Regions 1–25 and
  31–33 are out of the game. The Hill Folk units (ships 26, 34; castles
  27, 29, 30, 39, 41) cannot be attacked, so nobody may enter their regions
  either (entering means battle). That leaves 47 regions, all connected,
  40 of them enterable.
- Dragons moving onto an undefended village is plain movement; the capture
  happens at the start of the Dragon Riders' next turn, as usual. (Brian,
  12 Oct 2026)
- Dragon Rider hand (Brian, 12 Oct 2026): each drawn activation tile is
  kept in hand. Ships are built from a ship tile in hand, with any build
  cost paid by discarding other hand tiles; an army that reaches a sea with
  no ship in hand waits where it is. Substitutions also come from the hand.
  No regroup, so the 21-tile bag is the game clock.

## Engine rules calls (Claude, 12 Oct 2026; for Brian to confirm or overrule)

Confirmed by Brian (12 Oct 2026): armies with a ship on the next sea step
cross all the way in one activation ("armies never hang out on water");
withdrawal moves the whole force; a castle is a unit, so a lost castle is
the casualty.

Base rules:
- Withdrawal is all or nothing: the whole defending force goes, to one area.
- A beaten force with castles or a citadel loses all of them, and that is
  its casualty; no further unit is chosen. Survivors then retreat.
- Ships, dragons and land units move in separate groups. Each leader in a
  land group carries one unit free: a group of n with L leaders pays for
  max(1, n − L) units.
- Paying with a tile that isn't needed is rejected (overpaying by part of
  a tile is fine, as the rulebook allows).
- Solo battles: the human draws and decides on substitution first, then
  the non-player draws. Between two people, both draw at the start of
  each round and the attacker decides first.
- `legalActions` lists one canonical payment per choice (least waste, then
  fewest tiles, then lowest IDs); `apply` accepts any valid payment.

Mission 1 Dragon Riders:
- Turn order: capture villages where they stand → fight any region they
  share with the player → draw and activate → move the army → move the
  dragons → build the army's village → desert check.
- With a Dragon Rider ship on the next sea step, the army crosses to the
  land beyond in one activation. With an enemy unit on that sea, it waits.
- A ship is paid for with their lowest-pip non-ship hand tile.
- They substitute the lowest-pip hand tile that wins (sparing ships),
  replacing their lowest Battle tile. For a defender with shields, a tie
  counts as a win.
- "Undefended village": a player village with no player units on it.
- Their village goes only where no village of any faction and no non-DR
  unit already stand; adjacency is ignored, terrain limits are not.
- A dragon attacked on its starting region has no "towards home" option,
  so it takes the highest-numbered one. From 49 that is mountain 58, where
  Horse Lords can't follow; it only comes down for an undefended village.
