"""Source for data/factions.json, transcribed from the faction cards
(rulebook pp. 24-26). Run: python3 tools/factions_src.py > data/factions.json

Each row: unit, count, buildCost (stone blocks, 0-2; None = cannot be built),
pips (1-5; 0 = none), battle bonus, condition, extras.
"""
import json

F, T = "inForest", "inPlains"
ATK, DEF, ALW, FORT = "attacking", "defending", "always", "vsCastleOrCitadel"

def u(unit, count, build, pips, bonus=0, when=ALW, **kw):
    d = {"unit": unit, "count": count, "buildCost": build, "pips": pips,
         "battleBonus": bonus, "bonusWhen": when}
    d.update(kw)
    return d

BLANK = lambda n: u("blank", n, None, 5, 0, None)
COMMON = {
    "skirmishers": lambda n: u("skirmishers", n, 0, 2, 1, F),
    "shield": lambda n, b=1: u("shield", n, b, 3, 1, DEF, winsTiesDefending=True),
    "cavalry": lambda n, b=2, p=3: u("cavalry", n, b, p, 1, T),
    "siege": lambda n: u("siegeEngine", n, 1, 3, 2, FORT),
    "leader": lambda n: u("leader", n, 2, 5, 1, ALW, movesOneExtraUnitFree=True),
    "ship": lambda n: u("ship", n, 1, 4, 1, ALW, carriesLandUnitsAcrossSea=True),
    "castle": lambda n, b=2: u("castle", n, b, 4, 3, DEF, immobile=True),
}
C = COMMON

factions = [
    {"faction": "dragonRiders", "name": "Dragon Riders", "handSize": 6, "villages": 20,
     "citadel": {"battleBonus": 5, "bonusWhen": DEF},
     "tiles": [C["skirmishers"](4), u("swords", 4, 1, 4, 1), C["shield"](4), C["cavalry"](4),
               u("lizardmen", 4, 0, 2, 1, ATK, mayRemainInDesert=True), C["siege"](2),
               C["leader"](1), C["ship"](5), C["castle"](4),
               u("dragon", 2, 2, 5, 4, ALW, special="dragon"), BLANK(2)],
     "notes": ["Dragon: if part of a successful attack it goes to the discard pile. A force with "
               "dragons can withdraw (unless defending castles/citadel); no opposing force can "
               "withdraw from dragons. 1 pip to enter any terrain, including mountains. May "
               "remain in desert, mountains and sea."]},
    {"faction": "horseLords", "name": "Horse Lords", "handSize": 7, "villages": 20,
     "citadel": {"battleBonus": 5, "bonusWhen": DEF},
     "tiles": [C["skirmishers"](4), u("swords", 6, 1, 4, 1), C["shield"](4), C["cavalry"](6),
               C["siege"](2), C["castle"](4), C["leader"](2), C["ship"](5), BLANK(3)],
     "notes": ["Special power: hand size of seven tiles."]},
    {"faction": "necromancers", "name": "Necromancers", "handSize": 6, "villages": 20,
     "citadel": {"battleBonus": 5, "bonusWhen": DEF},
     "tiles": [C["skirmishers"](4), u("swords", 2, 1, 4, 1), C["shield"](2, b=2), C["cavalry"](4),
               u("goblins", 8, 0, 3, 1, ATK, mayRemainInDesert=True), C["siege"](2),
               C["leader"](1), C["ship"](5), C["castle"](4),
               u("necromancer", 4, 2, 5, 1, ALW, special="necromancer")],
     "asideTiles": [u("undead", 4, None, 0, 1, ALW, special="undead")],
     "notes": ["Necromancer: if one or more are in a winning battle, may replace each eliminated "
               "enemy unit with one Undead.",
               "Undead are kept aside, not in the bag. They move up to two areas in the Move Undead "
               "phase only, ignore terrain costs, can enter mountains, remain in deserts, and can "
               "move by sea using ships.",
               "Necromancer Shield shows two build blocks, unlike every other faction's one."]},
    {"faction": "hillFolk", "name": "Hill Folk", "handSize": 6, "villages": 20,
     "citadel": {"battleBonus": 5, "bonusWhen": DEF},
     "tiles": [C["skirmishers"](4), u("swords", 2, 1, 4, 1), C["shield"](4), C["cavalry"](4),
               u("reivers", 4, 0, 2, 1, ATK), C["siege"](2), C["leader"](1), C["ship"](5),
               C["castle"](6, b=1), u("giant", 2, 2, 5, 2, ALW, alwaysDrawFourInBattle=True),
               BLANK(2)],
     "notes": ["Castles cost one block, not two.",
               "Faction power (rulebook): moving into hills costs two pips."]},
    {"faction": "chaosHorde", "name": "Chaos Horde", "handSize": 6, "villages": 0,
     "citadel": None, "startingVP": 10, "vpPerCapturedVillage": 2,
     "tiles": [C["cavalry"](10, b=1, p=4), u("hordes", 20, 0, 3, 1, ATK), C["leader"](2),
               C["ship"](2), BLANK(2)],
     "notes": ["Places initial units after all citadels are placed. Builds where it already has "
               "units; ships adjacent to land units and vice versa.",
               "Captures villages as one Core Action (once per turn, at most one tile spent) "
               "instead of in the Capture Villages phase. Scores 2 VP per captured village at game end.",
               "Cavalry cost one block and show four pips."]},
    {"faction": "corsairs", "name": "Corsairs", "handSize": 6, "villages": 20,
     "citadel": {"battleBonus": 5, "bonusWhen": DEF},
     "tiles": [C["skirmishers"](4), u("axes", 12, 1, 4, 1), C["shield"](4), C["siege"](1),
               C["castle"](2), C["leader"](1), C["ship"](8), BLANK(4)],
     "notes": ["+1 when fighting at sea. Land units can retreat by sea when defending (except from "
               "dragons). When attacking adjacent to one of their ships, defenders can only retreat "
               "with cavalry or dragons present. May substitute a battle tile after the other side "
               "reveals. +1 VP for winning a battle."]},
]

for f in factions:
    assert sum(t["count"] for t in f["tiles"]) == 36, f["faction"]

print(json.dumps({
    "source": "Bloodstones rulebook faction cards, pp. 24-26; transcribed by Claude 2026-10-12, "
              "awaiting Brian's check against the physical tiles",
    "everyFactionAlsoHas": "1 victory-point marker and 1 regroup marker (the two round tokens on each card)",
    "factions": factions}, indent=1))
