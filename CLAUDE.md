# Bloodstones for iPad

Brian is building a pass-and-play iPad adaptation of *Bloodstones* (Martin
Wallace): local competitive play for 2–6 players, and Stephen Hurn's
18-mission solo campaign. This is a personal project. Brian owns the
physical game and has the final say on rules questions.

## Where things stand (Oct 2026)

- **Map data is done.** `data/maps/*.json` holds all five maps: regions,
  terrain and borders, checked against the mission army routes and the
  triangle rule. Treat these files as fixed inputs. The pipeline that made
  them is `tools/mapgen/` (Python, documented in README.md). Don't hand-edit
  the JSON; change `source/<map>_review.json` or the terrain file and rebuild.
- **The engine has not been started.** That's the next job.
- **There's no tech spec in the repo.** The March spec was lost.
  `docs/decisions.md` records every decision that is known for certain; follow
  it, and ask Brian whenever the rulebook and the decisions log don't settle
  a question.

## Next task: the engine, Mission 1 first

Build a pure Swift package (no UI) at `BloodstonesEngine/`, tested with
`swift test`:

- `MapGraph` loads `data/maps/<id>.json`; it handles adjacency, terrain,
  shortest paths and reachability.
- `GameState` is a Codable value type. The engine is pure functions:
  `apply(action, to: state) throws -> GameState` and `legalActions(in: state)`.
  Any randomness (tile bags) comes from a seeded generator held in the
  state, so games replay exactly.
- The first vertical slice is Mission 1, "Dragon Hunt", on Tyrant's Lament:
  Horse Lords as the player, Dragon Riders hostile, Hill Folk neutral.
  The non-player armies follow the fixed routes printed in the mission, and
  every step of those routes is a border in the map data. Tests should
  check that.
- Each mission's non-player behaviour is its own small Swift type behind a
  protocol. There is no general rules language.

The SwiftUI app comes after the engine. Target iPadOS 17 with SwiftData,
landscape only, fully offline.

## Map JSON

```
{ mapId, displayName,
  coordinateSpace: {width, height},      // px of the playable area at 300 dpi
  stats: {totalRegions, adjacencyEdges},
  regions: [{ id, terrain,               // plains|forest|hills|mountains|desert|sea
              adjacentTo: [ids],         // symmetric; rivers count as borders
              displayPosition: [x, y],   // centre of the number circle
              polygon: [[x, y], ...] }],
  provenance: {...} }                    // how it was made and checked
```

Missions → maps: Tyrant's Lament 1–4, 9 · Swan Dance 5–8 · Lady of the
Lake 10, 16 · Sorcerer's Crucible 11–13, 18 · Remains of the Past 14, 15, 17.

## Source material

The rulebook and the 18 mission PDFs are publisher material, so they stay
out of git. If Brian puts them in `pdfs/` (gitignored), read them there.
`pdftotext -layout` works well on the mission text. Region numbers on the
maps are images, not text.

## Working with Brian

- He's technical, so be direct and skip the basics.
- Record settled decisions in `docs/decisions.md`, with who made each one and when.
- Commit in small steps with clear messages; `main` is fine for now.
